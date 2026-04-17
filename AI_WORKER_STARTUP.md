# AI Worker Startup Guide

## Quick Start

### 1. Open Terminal in `ai_worker` folder:
```bash
cd d:\fix\ai_worker
```

### 2. Start the AI Worker:
```bash
python main.py
```

OR use uvicorn directly:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 3. Verify it's running:
- Check console: Should see `Uvicorn running on http://0.0.0.0:8000`
- Open browser: http://localhost:8000/health
- Should return: `{"status": "ok", "gpu": true/false, ...}`

### 3.5. RUN DIAGNOSTIC TEST (Important!)
Before submitting reports, verify Supabase connectivity:
```bash
python test_supabase_connection.py
```
This will check:
- ✓ Supabase connection
- ✓ ai_results table access
- ✓ reports table access
- ✓ INSERT/UPDATE permissions
- ✓ Recent reports status

**If any test fails, DO NOT proceed until fixed!**

### 4. In Flutter App:
- Submit a report with a photo
- Check Flutter console logs for:
  - `[Report] ✓ Report created with ID: ...`
  - `[AI Worker] ✓ SUCCESS - Report ... sent to AI worker`
- Check AI Worker console for:
  - `[AI] Starting analysis for report: ...`
  - `[AI] Pipeline complete: severity=...`
  - `[AI] ai_results inserted`

## Troubleshooting

### ⚠️ FIRST STEP: Run the diagnostic test!
```bash
cd d:\fix\ai_worker
python test_supabase_connection.py
```

Look for `✓` marks - if you see `✗` anywhere, this is the problem!

**Common diagnostic failures:**
- `✗ ConnectTimeout / Connection failed` → **Network issue** - See [NETWORK_TROUBLESHOOTING.md](NETWORK_TROUBLESHOOTING.md)
  - Your computer cannot reach Supabase servers
  - Could be: firewall, VPN, ISP blocking, or network down
  - Solution: Run network diagnostic commands in NETWORK_TROUBLESHOOTING.md
- `✗ Supabase initialization failed` → Wrong URL/key
- `✗ Cannot access ai_results table` → Table doesn't exist or RLS issue
- `✗ INSERT failed` → No write permissions

### Problem 1: Connection Error: "Connection refused"
**→ AI worker is not running!**
- Make sure terminal is in `d:\fix\ai_worker`
- Run `python main.py`

### Problem 2: Report submitted but NO AI results in Supabase
**Debug steps:**

### Error: "Module not found"
**→ Dependencies not installed**
```bash
pip install -r requirements.txt
```

### Error: "Port 8000 already in use"
**→ Something else is using port 8000**
```bash
# Find and kill process using port 8000
netstat -ano | findstr :8000
taskkill /PID <PID> /F
```

### No AI results after submitting report
**→ Check logs:**
1. **Flutter logs**: Should show `[AI Worker] ✓ SUCCESS`
2. **AI Worker logs**: Should show analysis progress
3. **Supabase**: Check `ai_results` table to see if row was inserted

## Key URLs

- **Health check**: http://localhost:8000/health
- **Analyze endpoint**: http://localhost:8000/analyze (POST)
- **Models location**: `ai_worker/checkpoints/`
  - `depth_anything_v2_vitl.pth` - Depth estimation model (2.5GB)
  - `pothole_seg.pt` - Pothole detection model

## Configuration

**Constants.dart** (Flutter):
```dart
static const aiWorkerUrl = 'http://127.0.0.1:8000';
```

**supabase_client.py** (AI Worker):
```python
SUPABASE_URL = "https://umuqhnzqutumhuykuiwc.supabase.co"
SUPABASE_SERVICE_KEY = "eyJ..." # Stored in environment
```

## Environment Variables (Optional)

You can override defaults by setting environment variables:
```bash
set SUPABASE_URL=your-url
set SUPABASE_SERVICE_KEY=your-key
set AI_WORKER_URL=http://0.0.0.0:8000
python main.py
```

## Performance Notes

- First run: ~30s (loads models)
- Subsequent runs: ~5-15s per report (depends on image size and GPU)
- GPU: ~4GB VRAM needed for ViT-L
- CPU fallback available but slower

## API Endpoints

### GET /health
Check if server is online
```json
{
  "status": "ok",
  "gpu": true,
  "gpu_name": "NVIDIA GeForce RTX 3090",
  "models_loaded": true,
  "ai_worker_version": "1.0.0"
}
```

### POST /analyze
Analyze a pothole image
```json
{
  "report_id": "uuid",
  "image_url": "https://..."
}
```

Response:
```json
{
  "report_id": "uuid",
  "severity": "moderate",
  "relative_depth": 0.08,
  "max_depth": 0.1,
  "pothole_area_px": 45000,
  "confidence": 0.92,
  "repair_cost_min": 1200,
  "repair_cost_max": 2400,
  "asphalt_kg": 32.5,
  "labour_hours": 2.5,
  "material_cost_est": 1950,
  "processing_time_s": 8.3
}
```

### GET /results/{report_id}
Retrieve stored AI results
```bash
curl http://localhost:8000/results/your-report-id
```
