# D:\fix\ai_worker\evaluate.py
import requests, json, time

BASE = "http://localhost:8000"
TEST_IMAGES = [
    ("https://upload.wikimedia.org/wikipedia/commons/thumb/2/2e/Pothole_on_a_road.jpg/640px-Pothole_on_a_road.jpg", "deep pothole"),
    ("https://umuqhnzqutumhuykuiwc.supabase.co", "report from app"),
]

for url, label in TEST_IMAGES:
    print(f"\n--- Testing: {label} ---")
    t = time.time()
    r = requests.post(f"{BASE}/analyze", json={
        "report_id": f"test_{int(t)}",
        "image_url": url
    })
    elapsed = time.time() - t
    if r.ok:
        d = r.json()
        print(f"Severity:   {d.get('severity')}")
        print(f"Depth:      {d.get('relative_depth', 0):.4f}")
        print(f"Confidence: {d.get('confidence', 0):.3f}")
        print(f"Cost:       ₹{d.get('repair_cost_min')} – ₹{d.get('repair_cost_max')}")
        print(f"Time:       {elapsed:.1f}s")
    else:
        print(f"ERROR: {r.status_code} — {r.text[:200]}")