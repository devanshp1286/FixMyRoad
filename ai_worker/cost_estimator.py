"""
cost_estimator.py — Realistic INR repair cost calculation
==========================================================
Uses actual depth and area metrics from the AI pipeline to produce
granular, image-specific cost estimates rather than fixed bracket ranges.

Real-world calibration (Indian road repair rates, 2024):
  - Asphalt cold mix: ₹15–25 per kg
  - Labour: ₹450–600 per hour (2 workers)
  - Minimum job cost: ₹500 (call-out + equipment)
  - Camera-to-road distance assumed: ~1.2m (phone held at waist)
  - pixels-to-m² calibration: 6000 px ≈ 1 m² at 1.2m height, 12MP photo
"""

import math

# ── Physical calibration ─────────────────────────────────────────────────────
PIXELS_PER_M2      = 6000    # px → m² at typical phone camera height
DEPTH_SCALE_M      = 0.20    # 1 normalised depth unit ≈ 0.20m (20cm) physical depth
ASPHALT_DENSITY    = 1.8     # kg per litre of asphalt
ASPHALT_PRICE_MIN  = 15      # INR per kg (cold mix, economy)
ASPHALT_PRICE_MAX  = 22      # INR per kg (hot mix, quality)
LABOUR_RATE        = 500     # INR per hour (2 workers combined)
CALL_OUT_COST      = 300     # INR minimum call-out + equipment wear
OVERHEAD_PCT       = 0.12    # 12% overhead (supervision, transport)

# ── Severity brackets — only used as a safety net if metrics are absent ──────
_BRACKET = {
    "shallow":  {"min": 500,   "max": 1800},
    "moderate": {"min": 1800,  "max": 6000},
    "deep":     {"min": 6000,  "max": 18000},
}

# ── Labour hours by severity ──────────────────────────────────────────────────
_LABOUR_HRS = {
    "shallow":  0.5,    # quick patch
    "moderate": 1.5,    # cut, clean, fill, compact
    "deep":     3.5,    # excavate, base repair, fill, compact, surface
}


def estimate_cost(severity: str | None) -> dict:
    """Returns the bracket cost range as a fallback / display range."""
    if severity is None or severity not in _BRACKET:
        return {"min": None, "max": None}
    return dict(_BRACKET[severity])


def estimate_materials(
    severity:  str | None,
    area_px:   float | None,
    rel_depth: float | None,
) -> dict:
    """
    Computes image-specific repair cost from actual AI metrics.

    The cost varies continuously based on real area and depth values,
    not just the severity bracket. Two reports with the same severity
    label will have different costs if their area or depth differs.
    """
    if severity is None or severity not in _LABOUR_HRS:
        return {"asphalt_kg": None, "labour_hours": None,
                "material_cost_est": None, "cost_min": None, "cost_max": None}

    # ── 1. Compute physical area ─────────────────────────────────────────
    if area_px is not None and area_px > 500:
        area_m2 = area_px / PIXELS_PER_M2
        # Sanity clamp: real potholes are 0.05m² to 4m²
        area_m2 = float(max(0.05, min(area_m2, 4.0)))
        area_source = "measured"
    else:
        # Severity-based default if no YOLO mask
        _default_area = {"shallow": 0.15, "moderate": 0.40, "deep": 0.90}
        area_m2 = _default_area[severity]
        area_source = "estimated"

    # ── 2. Compute physical depth ─────────────────────────────────────────
    if rel_depth is not None and rel_depth > 0:
        depth_m = rel_depth * DEPTH_SCALE_M
        # Sanity clamp: real potholes are 0.5cm to 25cm
        depth_m = float(max(0.005, min(depth_m, 0.25)))
        depth_source = "measured"
    else:
        _default_depth = {"shallow": 0.015, "moderate": 0.045, "deep": 0.10}
        depth_m = _default_depth[severity]
        depth_source = "estimated"

    # ── 3. Volume → asphalt quantity ─────────────────────────────────────
    # Add 30% compaction factor (asphalt compresses when tamped)
    volume_m3  = area_m2 * depth_m * 1.30
    volume_l   = volume_m3 * 1000
    asphalt_kg = volume_l * ASPHALT_DENSITY
    # Add 15% wastage (trimming, overfill)
    asphalt_kg *= 1.15

    # ── 4. Labour hours ───────────────────────────────────────────────────
    base_labour_hrs = _LABOUR_HRS[severity]
    # Scale slightly with area (larger job = more time)
    area_factor    = 1.0 + (area_m2 - 0.3) * 0.3   # ±30% for large/small
    labour_hrs     = round(base_labour_hrs * max(0.6, min(area_factor, 2.0)), 2)

    # ── 5. Material cost ──────────────────────────────────────────────────
    asphalt_cost_mid = asphalt_kg * ((ASPHALT_PRICE_MIN + ASPHALT_PRICE_MAX) / 2)
    labour_cost      = labour_hrs * LABOUR_RATE
    base_cost        = CALL_OUT_COST + asphalt_cost_mid + labour_cost
    total_cost       = base_cost * (1 + OVERHEAD_PCT)

    # ── 6. Cost range (±20% variation for quote purposes) ─────────────────
    cost_min = max(400, round(total_cost * 0.82, -1))   # round to nearest 10
    cost_max = round(total_cost * 1.22, -1)

    # Clamp to bracket limits (AI should not wildly exceed realistic ranges)
    bracket = _BRACKET[severity]
    cost_min = max(cost_min, bracket["min"])
    cost_max = min(cost_max, bracket["max"])

    # Ensure min < max
    if cost_min >= cost_max:
        cost_max = cost_min + 500

    print(f"[Cost] severity={severity} area={area_m2:.3f}m² ({area_source}) "
          f"depth={depth_m*100:.1f}cm ({depth_source})")
    print(f"[Cost] asphalt={asphalt_kg:.2f}kg labour={labour_hrs}hrs "
          f"cost=₹{cost_min:.0f}–₹{cost_max:.0f}")

    return {
        "asphalt_kg":        round(asphalt_kg, 2),
        "labour_hours":      labour_hrs,
        "material_cost_est": round(total_cost, 2),
        "cost_min":          cost_min,
        "cost_max":          cost_max,
        "area_m2":           round(area_m2, 3),
        "depth_cm":          round(depth_m * 100, 1),
    }