# AI Results Troubleshooting Checklist

**Problem**: Report submitted ✓, but AI results not in Supabase ✗

## Step 1: Run Diagnostic Test (MANDATORY)
```bash
cd d:\fix\ai_worker
python test_supabase_connection.py
```

Check output:
- [ ] `✓ Supabase client initialized`
- [ ] `✓ ai_results table is accessible`
- [ ] `✓ reports table is accessible`
- [ ] `✓ status_history table is accessible`
- [ ] `✓ INSERT successful` (or UPDATE successful)

**If any fails**: There's a database/permissions issue - FIX THIS FIRST!

---

## Step 2: Check AI Worker Console Logs

When you submit a report, look for this sequence in AI Worker console:

```
================================================================================
[AI] ★ STARTING AI ANALYSIS ★
```

↓ Wait for:

```
[AI] Pipeline complete: severity=...
[AI] Writing ai_results to Supabase...
[AI] ✓ ai_results inserted successfully
```

↓ Then:

```
[AI] ✓✓✓ AI ANALYSIS COMPLETE ✓✓✓
```

### If you see `✗ CRITICAL ERROR`:
This is the problem! AI worker tried to write but failed.
Look at error message - usually one of:
- "Invalid JSON" - wrong data format
- "No permissions" - Supabase access issue
- "Table not found" - schema missing

---

## Step 3: Check Flutter Console Logs

When you submit a report:

```
[Report] Uploading image to: ...
[Report] ✓ Report created with ID: uuid-here
[Report] Triggering AI analysis in background...
[AI Worker] Calling AI worker...
[AI Worker] Response status: 200
[AI Worker] ✓ SUCCESS
```

### If you don't see these logs:
- Report wasn't created → Check Flutter for upload errors
- AI worker call failed → Check constants.dart for correct URL

### If response status is NOT 200:
- 404 = AI worker URL is wrong
- 0 = AI worker not running or unreachable
- 500 = AI worker crashed (check its console)

---

## Step 4: Verify Supabase Data

In Supabase dashboard:

1. **Check reports table**:
   - Latest report should exist
   - Status should be `submitted` → `under_review` (after AI runs)

2. **Check ai_results table**:
   - Should have entry with same report_id as the report
   - Should have severity, depth, cost values populated

3. **Check status_history table**:
   - Should have entry showing status change to `under_review`

If data is NOT there after 30 seconds → AI worker didn't write it

---

## Step 5: Identify the Root Cause

| Symptom | Cause | Fix |
|---------|-------|-----|
| Report created ✓, AI results NOT there | AI worker not called | Check Flutter logs, check URL in constants.dart |
| AI Worker console shows errors | Supabase access issue | Run diagnostic test, check credentials |
| Status says "submitted" not "under_review" | Report status not updated | AI worker didn't complete analysis |
| All logs look good but no data | Network/firewall issue | Check if port 8000 is accessible |

---

## Quick Fixes

### Fix 1: AI Worker Not Running
```bash
cd d:\fix\ai_worker
python main.py
```

### Fix 2: Wrong URL in Flutter
Edit [constants.dart](flutter_app/lib/core/constants.dart):
```dart
// Change this:
static const aiWorkerUrl = 'http://10.183.62.19:8000';  // ✗ WRONG

// To this:
static const aiWorkerUrl = 'http://127.0.0.1:8000';  // ✓ CORRECT for local
```

### Fix 3: Supabase Permissions Issue
Run diagnostic and look for permission errors:
```bash
python test_supabase_connection.py
```

If INSERT fails:
1. Check Supabase dashboard
2. Go to Tables → ai_results → RLS (Row Level Security)
3. Verify service role can INSERT/UPDATE

### Fix 4: Clear Logs and Restart
```bash
# Terminal 1: Stop AI worker (Ctrl+C) and restart
cd d:\fix\ai_worker
python main.py

# Terminal 2: Kill and restart Flutter
flutter run
```

---

## What the Flow Should Look Like

```
Flutter App                  AI Worker                Supabase
     |                            |                        |
     |--- Submit Report ------→   |                        |
     |                            |                        |
     |                            |--- Insert into reports--|
     |                            |                        |
     |←--- Call AI /analyze ---   |                        |
     |                            |--- Download image --→ Storage
     |                            |                        |
     |                            |--- Process AI ----     |
     |                            |                        |
     |                            |--- Insert ai_results---|
     |                            |                        |
     |← Return 200 OK ←           |                        |
     |                            |--- Update reports -----|
     |                            |                        |
     |--- Poll /reports --------------- Fetch ai_results←--|
     |                            |                        |
     |← Show AI Results ←         |                        |
```

---

## Debug Commands

Check if AI worker is online:
```bash
curl http://localhost:8000/health
```

Test AI worker directly:
```bash
curl -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "report_id": "test-123",
    "image_url": "https://your-image-url.jpg"
  }'
```

Check Supabase tables have data:
```bash
# In supabase_client.py:
from supabase_client import supabase
reports = supabase.table("reports").select("*").limit(5).execute()
print(reports.data)

ai_results = supabase.table("ai_results").select("*").limit(5).execute()
print(ai_results.data)
```

---

## Final Checklist Before Testing

- [ ] AI Worker running (`python main.py`)
- [ ] Diagnostic test passes (all ✓)
- [ ] Flutter constants.dart has correct AI URL
- [ ] Supabase credentials valid (in supabase_client.py)
- [ ] Models loaded (check AI Worker startup logs)
- [ ] Network allows port 8000

If all checked ✓, submit a report and wait 30 seconds for AI analysis!
