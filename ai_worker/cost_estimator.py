# ═══════════════════════════════════════════════════════════════════════════
# cost_estimator.py — INR repair cost + material estimation
# ═══════════════════════════════════════════════════════════════════════════

COST_TABLE = {
    "shallow":  {"min": 500,   "max": 1500},
    "moderate": {"min": 1500,  "max": 5000},
    "deep":     {"min": 5000,  "max": 15000},
}

ASPHALT_DENSITY  = 1.8    # kg per litre
LABOUR_RATE_INR  = 500    # INR per hour
PIXELS_PER_M2    = 8000   # calibration for typical phone camera at ~1m height
DEPTH_SCALE      = 0.15   # normalized depth unit → metres

def estimate_cost(severity: str | None) -> dict:
    if severity is None or severity not in COST_TABLE:
        return {"min": None, "max": None}
    return COST_TABLE[severity]

def estimate_materials(
    severity:  str | None,
    area_px:   float | None,
    rel_depth: float | None,
) -> dict:
    if severity is None:
        return {
            "asphalt_kg":        None,
            "labour_hours":      None,
            "material_cost_est": None,
        }

    # Use actual values if available, otherwise use severity-based defaults
    if area_px is not None and area_px > 0:
        area_m2 = area_px / PIXELS_PER_M2
    else:
        # Severity-based default area estimates
        area_defaults = {"shallow": 0.3, "moderate": 0.6, "deep": 1.2}
        area_m2 = area_defaults.get(severity, 0.5)

    if rel_depth is not None and rel_depth > 0:
        depth_m = rel_depth * DEPTH_SCALE
    else:
        # Severity-based default depth estimates
        depth_defaults = {"shallow": 0.02, "moderate": 0.05, "deep": 0.12}
        depth_m = depth_defaults.get(severity, 0.05)

    # Volume in litres
    volume_l   = area_m2 * depth_m * 1000
    asphalt_kg = volume_l * ASPHALT_DENSITY

    # Labour based on severity
    labour_map = {"shallow": 0.5, "moderate": 1.5, "deep": 4.0}
    labour_hrs = labour_map.get(severity, 1.5)

    material_cost = (asphalt_kg * 15) + (labour_hrs * LABOUR_RATE_INR)

    print(f"[Cost] severity={severity} area_m2={area_m2:.3f} depth_m={depth_m:.3f}")
    print(f"[Cost] asphalt={asphalt_kg:.2f}kg labour={labour_hrs}hrs cost=₹{material_cost:.0f}")

    return {
        "asphalt_kg":        round(asphalt_kg, 2),
        "labour_hours":      labour_hrs,
        "material_cost_est": round(material_cost, 2),
    }