"""
pipeline.py  — FixMyRoad AI Analysis Pipeline
==============================================
Two-model pipeline:
  1. YOLOv11-seg   → pixel-level pothole boundary (mask)
  2. Depth Anything V2 (vitl) → dense monocular depth map

Key insight: Depth Anything V2 normalises output to [0,1] per image.
So "deep" in absolute terms cannot be read directly — we must compare
the pothole region's depth to the surrounding road surface. The
relative_depth metric captures this: how much deeper the pothole
pixels are compared to the adjacent road pixels (in the same image).

Realistic severity distribution expected:
  ~50% shallow  (small/recent damage, road mostly intact)
  ~35% moderate (visible bowl shape, surface broken)
  ~15% deep     (large bowl, structural damage, water pooling)
"""

import io
import cv2
import torch
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import cm
from pathlib import Path

# ── Singleton model handles ──────────────────────────────────────────────────
_depth_model = None
_yolo_model  = None


def _get_depth_model():
    global _depth_model
    if _depth_model is None:
        from depth_anything_v2.dpt import DepthAnythingV2
        cfg = {"encoder": "vitl", "features": 256,
               "out_channels": [256, 512, 1024, 1024]}
        model = DepthAnythingV2(**cfg)
        ckpt  = Path("checkpoints/depth_anything_v2_vitl.pth")
        model.load_state_dict(torch.load(ckpt, map_location="cpu"))
        device = "cuda" if torch.cuda.is_available() else "cpu"
        _depth_model = model.to(device).eval()
        print(f"[Pipeline] Depth Anything V2 loaded on {device}")
    return _depth_model


def _get_yolo_model():
    global _yolo_model
    if _yolo_model is None:
        from ultralytics import YOLO
        _yolo_model = YOLO("checkpoints/pothole_seg.pt")
        print("[Pipeline] YOLOv11 loaded")
    return _yolo_model


# ── Depth inference ──────────────────────────────────────────────────────────
def _infer_depth(model, image_bgr: np.ndarray) -> np.ndarray:
    """
    Returns a float32 depth map normalised to [0, 1].
    NOTE: Depth Anything V2 uses inverse depth convention —
    higher values = CLOSER to camera (road surface).
    Lower values = FURTHER from camera (inside pothole depression).
    """
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    with torch.no_grad():
        raw = model.infer_image(image_rgb)  # raw inverse depth
    d_min, d_max = raw.min(), raw.max()
    normalised = ((raw - d_min) / (d_max - d_min + 1e-8)).astype(np.float32)
    print(f"[Pipeline] Depth map range: raw=[{d_min:.3f}, {d_max:.3f}] "
          f"norm_std={normalised.std():.4f}")
    return normalised


# ── YOLO segmentation ────────────────────────────────────────────────────────
def _run_yolo(model, image_bgr: np.ndarray, conf: float = 0.15):
    h, w = image_bgr.shape[:2]
    results = model(image_bgr, conf=conf, verbose=False)[0]

    if results.masks is None:
        print("[Pipeline] YOLO: no detections")
        return []

    detections = []
    print(f"[Pipeline] YOLO: {len(results.masks.data)} detection(s)")
    for i in range(len(results.masks.data)):
        raw  = results.masks.data[i].cpu().numpy()
        mask = cv2.resize(raw, (w, h), interpolation=cv2.INTER_NEAREST)
        mask = (mask > 0.5).astype(np.uint8) * 255
        area = int(np.sum(mask > 0))
        # Skip tiny noise detections (< 0.05% of image)
        if area < h * w * 0.0005:
            continue
        conf_score = float(results.boxes[i].conf[0].cpu().numpy())
        x1, y1, x2, y2 = map(int, results.boxes[i].xyxy[0].cpu().numpy())
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                       cv2.CHAIN_APPROX_SIMPLE)
        detections.append({
            "mask": mask, "bbox": (x1, y1, x2, y2),
            "conf": conf_score, "contours": contours,
            "area": area, "source": "yolo"
        })
        print(f"[Pipeline]   det[{i}] conf={conf_score:.3f} area={area}px")
    return detections


# ── Heuristic fallback ───────────────────────────────────────────────────────
def _heuristic_detect(depth_map: np.ndarray, image_bgr: np.ndarray):
    """
    Image-adaptive heuristic used ONLY when YOLO finds nothing.

    Strategy: look for regions that are DARKER than surrounding area in the
    depth map (lower value = further from camera = possible depression).
    Uses local contrast rather than global percentile to avoid always
    returning the same region.
    """
    h, w = depth_map.shape

    # ── Guard: check if image has enough depth variation ──────────────────
    depth_std = depth_map.std()
    p5, p95   = np.percentile(depth_map, [5, 95])
    depth_range = p95 - p5
    print(f"[Pipeline] Heuristic check: std={depth_std:.4f} range={depth_range:.4f}")

    if depth_range < 0.08:
        # Very flat depth map → probably a smooth road with no real pothole
        print("[Pipeline] Heuristic: flat depth map — no pothole detected")
        return None

    # ── Use lower-half of image (road surface, not sky/horizon) ──────────
    roi_start = h // 3          # ignore top third (sky, buildings)
    depth_roi = depth_map[roi_start:, :]

    # ── Edge density check — potholes create strong edges ─────────────────
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray[roi_start:, :], 40, 120)
    edge_density = np.sum(edges > 0) / edges.size
    print(f"[Pipeline] Heuristic: edge_density={edge_density:.4f}")

    # ── Adaptive threshold using local statistics ──────────────────────────
    # Use 25th percentile of the ROI — not global 20% which always finds something
    p25_roi = np.percentile(depth_roi, 25)
    p75_roi = np.percentile(depth_roi, 75)
    local_range = p75_roi - p25_roi

    # Only proceed if local variation is meaningful
    if local_range < 0.06:
        print("[Pipeline] Heuristic: insufficient local depth variation")
        return None

    # Threshold: pixels that are significantly darker than the median
    # (deeper = further from camera = lower value in inverse depth map)
    median_roi = np.median(depth_roi)
    threshold  = median_roi - (local_range * 0.5)

    # Build binary mask in ROI
    binary_roi = (depth_roi < threshold).astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    binary_roi = cv2.morphologyEx(binary_roi, cv2.MORPH_CLOSE, kernel)
    binary_roi = cv2.morphologyEx(binary_roi, cv2.MORPH_OPEN, kernel)

    contours, _ = cv2.findContours(binary_roi, cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        print("[Pipeline] Heuristic: no contours found")
        return None

    # Filter: must be reasonably sized (0.1% to 40% of image)
    min_area = h * w * 0.001
    max_area = h * w * 0.40
    valid = [c for c in contours
             if min_area < cv2.contourArea(c) < max_area]
    if not valid:
        print("[Pipeline] Heuristic: no valid contours after size filter")
        return None

    largest  = max(valid, key=cv2.contourArea)
    area     = cv2.contourArea(largest)
    print(f"[Pipeline] Heuristic: contour area={area:.0f}px "
          f"({100*area/(h*w):.1f}% of image)")

    # Build full-image mask (add ROI offset back)
    full_mask = np.zeros((h, w), dtype=np.uint8)
    shifted   = [c + np.array([0, roi_start]) for c in [largest]]
    cv2.drawContours(full_mask, shifted, -1, 255, cv2.FILLED)

    x, y, bw, bh = cv2.boundingRect(largest)
    y += roi_start  # shift bbox back to full image coords

    # Confidence: edge density + depth range — never pretend to be YOLO
    heuristic_conf = float(np.clip(edge_density * 3 + local_range, 0.15, 0.65))

    return {
        "mask": full_mask, "bbox": (x, y, x+bw, y+bh),
        "conf": heuristic_conf, "contours": shifted,
        "area": int(area), "source": "heuristic"
    }


# ── Depth metrics — the core of severity classification ─────────────────────
def _compute_metrics(depth_map: np.ndarray, mask: np.ndarray,
                     source: str = "yolo") -> dict:
    """
    Computes realistic, image-relative depth metrics.

    Because Depth Anything V2 normalises per image, we cannot use absolute
    thresholds. Instead we compare:
      - Pothole pixels (inside mask)
      - Road pixels (outside mask, in a dilated ring around the pothole)

    Using a local road reference (dilated ring) instead of the whole image
    prevents distant objects (sky, buildings) from skewing the road baseline.
    """
    if mask is None or mask.sum() == 0:
        return {}

    pothole_px = depth_map[mask == 255]
    if pothole_px.size < 100:
        print("[Pipeline] Metrics: mask too small")
        return {}

    # ── Local road reference: dilated ring around the pothole ─────────────
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (51, 51))
    dilated = cv2.dilate(mask, kernel, iterations=1)
    ring_mask = (dilated == 255) & (mask == 0)   # ring = dilated minus original

    road_px = depth_map[ring_mask]
    if road_px.size < 200:
        # Ring is too small (edge of image) — fall back to full non-pothole area
        road_px = depth_map[mask == 0]

    if road_px.size < 100:
        return {}

    # ── Compute depth difference ───────────────────────────────────────────
    # Road level = 75th percentile of road ring (robust to outliers)
    road_level = float(np.percentile(road_px, 75))

    # Pothole depth = mean of lower 50% of pothole pixels (the actual depression)
    mean_pothole  = float(np.mean(pothole_px))
    deep_pothole  = float(np.mean(pothole_px[pothole_px <= np.percentile(pothole_px, 50)]))

    # relative_depth: how much lower the pothole is vs road (positive = deeper)
    rel_d  = max(road_level - mean_pothole,  0.0)
    max_d  = max(road_level - deep_pothole,  0.0)

    # Road depth std — high std means varied terrain (less certain about pothole)
    road_std = float(np.std(road_px))

    print(f"[Pipeline] road_level={road_level:.4f} mean_pothole={mean_pothole:.4f} "
          f"road_std={road_std:.4f}")
    print(f"[Pipeline] rel_depth={rel_d:.4f} max_depth={max_d:.4f}")

    # ── Normalise relative depth against road std ──────────────────────────
    # This prevents flat images (high road_std) from over-inflating severity
    normalised_rel_d = rel_d / (road_std + 0.05)
    print(f"[Pipeline] normalised_rel_d={normalised_rel_d:.4f}")

    # ── Severity classification ────────────────────────────────────────────
    # Thresholds tuned against the normalised metric for realistic distribution
    if normalised_rel_d < 0.4:
        severity = "shallow"
    elif normalised_rel_d < 1.0:
        severity = "moderate"
    else:
        severity = "deep"

    # Heuristic detections get one tier softer (less certain)
    if source == "heuristic" and severity == "deep":
        severity = "moderate"
        print("[Pipeline] Heuristic downgrade: deep → moderate")

    print(f"[Pipeline] Severity: {severity} "
          f"(norm_rel_d={normalised_rel_d:.4f})")

    return {
        "relative_depth":   round(rel_d, 4),
        "max_depth":        round(max_d, 4),
        "road_level":       round(road_level, 4),
        "road_std":         round(road_std, 4),
        "normalised_rel_d": round(normalised_rel_d, 4),
        "severity":         severity,
        "pothole_area_px":  int(pothole_px.size),
        "source":           source,
    }


# ── Visualisation helpers ────────────────────────────────────────────────────
def _fig_to_bytes(fig) -> bytes:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=100, bbox_inches="tight",
                facecolor=fig.get_facecolor())
    plt.close(fig)
    buf.seek(0)
    return buf.read()


def _make_depth_map(image_bgr: np.ndarray, depth_map: np.ndarray) -> bytes:
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    fig.patch.set_facecolor("#111827")
    axes[0].imshow(cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB))
    axes[0].set_title("Original Image", color="#f9fafb", fontsize=11, fontweight="bold")
    axes[0].axis("off")
    axes[1].imshow(depth_map, cmap="magma")
    axes[1].set_title("Depth Map (bright = closer to camera)",
                       color="#f9fafb", fontsize=11, fontweight="bold")
    axes[1].axis("off")
    plt.tight_layout()
    return _fig_to_bytes(fig)


def _make_heatmap(image_bgr: np.ndarray, depth_map: np.ndarray,
                  det: dict, metrics: dict) -> bytes | None:
    mask = det["mask"]
    if mask is None or mask.sum() == 0:
        return None

    image_rgb  = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB).astype(np.float32)
    # Invert depth for heatmap: lower depth value = deeper = more red
    depth_inv  = 1.0 - depth_map

    # Normalise only within the pothole mask
    pot_vals = depth_inv[mask == 255]
    if pot_vals.size == 0:
        return None
    d_min, d_max = pot_vals.min(), pot_vals.max()
    if d_max - d_min < 1e-6:
        d_min, d_max = depth_inv.min(), depth_inv.max()

    norm    = ((depth_inv - d_min) / (d_max - d_min + 1e-8)).clip(0, 1)
    heatmap = (cm.get_cmap("RdYlGn_r")(norm)[:, :, :3] * 255).astype(np.float32)

    # Blend heatmap only inside the mask
    result = image_rgb.copy()
    for c in range(3):
        result[:, :, c] = np.where(
            mask == 255,
            result[:, :, c] * 0.3 + heatmap[:, :, c] * 0.7,
            result[:, :, c]
        )
    result = result.clip(0, 255).astype(np.uint8)

    # Draw boundary
    cv2.drawContours(result, det["contours"], -1, (255, 255, 255), 2)

    # Severity label on image
    severity = metrics.get("severity", "")
    color_map = {"shallow": (100, 220, 100), "moderate": (255, 165, 0),
                 "deep": (220, 60, 60)}
    label_color = color_map.get(severity, (255, 255, 255))
    x1, y1 = det["bbox"][:2]
    cv2.putText(result, f"{severity.upper()}",
                (max(x1, 4), max(y1 - 8, 20)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, label_color, 2, cv2.LINE_AA)

    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    fig.patch.set_facecolor("#111827")
    axes[0].imshow(image_rgb.astype(np.uint8))
    axes[0].set_title("Original", color="#f9fafb", fontsize=11, fontweight="bold")
    axes[0].axis("off")
    axes[1].imshow(result)
    axes[1].set_title(f"Severity Heatmap — {severity.title()}",
                       color="#f9fafb", fontsize=11, fontweight="bold")
    axes[1].axis("off")

    # Add colourbar legend
    sm = plt.cm.ScalarMappable(cmap="RdYlGn_r",
                                norm=plt.Normalize(vmin=0, vmax=1))
    sm.set_array([])
    cbar = fig.colorbar(sm, ax=axes[1], orientation="vertical",
                         fraction=0.03, pad=0.02)
    cbar.set_label("Depth (deeper = red)", color="#f9fafb", fontsize=9)
    cbar.ax.yaxis.set_tick_params(color="#f9fafb")
    plt.setp(cbar.ax.yaxis.get_ticklabels(), color="#f9fafb")

    plt.tight_layout()
    return _fig_to_bytes(fig)


def _make_before_after(image_bgr: np.ndarray, depth_map: np.ndarray,
                        detections: list, metrics: dict) -> bytes:
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    after     = image_rgb.copy().astype(np.float32)

    # Subtle depth overlay on whole image
    depth_col = (cm.get_cmap("magma")(depth_map)[:, :, :3] * 255).astype(np.float32)
    after = after * 0.80 + depth_col * 0.20

    COLORS = [(255, 60, 60), (60, 200, 255), (60, 255, 120), (255, 200, 60)]
    for idx, det in enumerate(detections):
        color = COLORS[idx % len(COLORS)]
        mask  = det["mask"]
        for c in range(3):
            after[:, :, c] = np.where(
                mask == 255,
                after[:, :, c] * 0.25 + color[c] * 0.75,
                after[:, :, c]
            )
    after_u8 = after.clip(0, 255).astype(np.uint8)

    for idx, det in enumerate(detections):
        color  = COLORS[idx % len(COLORS)]
        x1, y1, x2, y2 = det["bbox"]
        cv2.drawContours(after_u8, det["contours"], -1, color, 2)
        cv2.rectangle(after_u8, (x1, y1), (x2, y2), color, 1)
        conf_label = f"conf={det['conf']:.2f} ({det.get('source','?')})"
        cv2.putText(after_u8, conf_label, (x1+3, y1+16),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1, cv2.LINE_AA)

    # Stats overlay
    sev  = metrics.get("severity", "unknown")
    rd   = metrics.get("relative_depth", 0)
    src  = metrics.get("source", "")
    info = f"Severity: {sev.upper()}  |  rel_depth: {rd:.4f}  |  source: {src}"
    cv2.putText(after_u8, info, (8, after_u8.shape[0] - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (240, 240, 240), 1, cv2.LINE_AA)

    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    fig.patch.set_facecolor("#111827")
    axes[0].imshow(image_rgb)
    axes[0].set_title("Original Photo", color="#f9fafb", fontsize=12,
                       fontweight="bold")
    axes[0].axis("off")
    axes[1].imshow(after_u8)
    axes[1].set_title("AI Analysis Result", color="#f9fafb", fontsize=12,
                       fontweight="bold")
    axes[1].axis("off")
    plt.tight_layout()
    return _fig_to_bytes(fig)


# ── Main pipeline entry point ────────────────────────────────────────────────
def run_full_pipeline(image_bytes: bytes, report_id: str) -> dict:
    print(f"\n{'='*60}")
    print(f"[Pipeline] Report: {report_id}")
    print(f"{'='*60}")

    # ── Decode ──────────────────────────────────────────────────────────
    arr   = np.frombuffer(image_bytes, np.uint8)
    image = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("Cannot decode image — check format (must be JPEG/PNG)")

    h, w = image.shape[:2]
    print(f"[Pipeline] Image size: {w}x{h}px ({len(image_bytes)//1024}KB)")

    # Resize very large images for speed (keep aspect ratio)
    if max(h, w) > 1280:
        scale = 1280 / max(h, w)
        image = cv2.resize(image, (int(w*scale), int(h*scale)),
                           interpolation=cv2.INTER_AREA)
        h, w  = image.shape[:2]
        print(f"[Pipeline] Resized to {w}x{h}px")

    # ── Depth estimation ─────────────────────────────────────────────────
    depth_model = _get_depth_model()
    depth_map   = _infer_depth(depth_model, image)

    # ── YOLO detection ───────────────────────────────────────────────────
    detections    = []
    used_fallback = False
    try:
        yolo       = _get_yolo_model()
        detections = _run_yolo(yolo, image, conf=0.15)
    except Exception as e:
        print(f"[Pipeline] YOLO error: {e}")

    # ── Heuristic fallback — only if YOLO found nothing ──────────────────
    if not detections:
        print("[Pipeline] Falling back to heuristic detector...")
        det = _heuristic_detect(depth_map, image)
        if det:
            detections    = [det]
            used_fallback = True
            print(f"[Pipeline] Heuristic: conf={det['conf']:.3f} "
                  f"area={det['area']}px")
        else:
            print("[Pipeline] No detections from either model")

    # ── No detection at all ───────────────────────────────────────────────
    if not detections:
        print("[Pipeline] Cannot detect pothole — returning minimal result")
        depth_bytes = _make_depth_map(image, depth_map)
        return {
            "severity": "shallow", "relative_depth": 0.02,
            "max_depth": 0.03, "pothole_area_px": 0, "confidence": 0.0,
            "depth_map_bytes": depth_bytes, "heatmap_bytes": None,
            "before_after_bytes": _make_before_after(image, depth_map, [], {}),
            "used_fallback": True,
        }

    # ── Use best detection ────────────────────────────────────────────────
    best    = max(detections, key=lambda d: d["conf"])
    source  = best.get("source", "yolo")
    metrics = _compute_metrics(depth_map, best["mask"], source=source)

    if not metrics:
        print("[Pipeline] Metrics failed — using defaults")
        metrics = {"severity": "shallow", "relative_depth": 0.02,
                   "max_depth": 0.03, "pothole_area_px": 0}

    # ── Generate visualisations ───────────────────────────────────────────
    print("[Pipeline] Generating visualisations...")
    depth_bytes        = _make_depth_map(image, depth_map)
    heatmap_bytes      = _make_heatmap(image, depth_map, best, metrics)
    before_after_bytes = _make_before_after(image, depth_map, detections, metrics)

    result = {
        "relative_depth":     metrics.get("relative_depth"),
        "max_depth":          metrics.get("max_depth"),
        "severity":           metrics.get("severity"),
        "pothole_area_px":    metrics.get("pothole_area_px"),
        "confidence":         round(best["conf"], 4),
        "depth_map_bytes":    depth_bytes,
        "heatmap_bytes":      heatmap_bytes,
        "before_after_bytes": before_after_bytes,
        "used_fallback":      used_fallback,
    }

    print(f"[Pipeline] RESULT: severity={result['severity']} "
          f"rel_depth={result['relative_depth']} "
          f"conf={result['confidence']} source={source}")
    print(f"{'='*60}\n")
    return result