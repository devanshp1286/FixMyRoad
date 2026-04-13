# FixMyRoad — Complete Setup Guide

## Project Structure

```
fixmyroad/
├── flutter_app/          # Flutter mobile app (citizen + engineer)
├── ai_worker/            # FastAPI + AI pipeline (Python)
└── supabase/             # SQL schema and Edge Functions
```

---

## Step 1 — Supabase Setup

1. Create a new project at https://supabase.com
2. Go to **Database → Extensions** and enable:
   - `postgis`
   - `pg_net`
3. Go to **SQL Editor** and run in order:
   - `supabase/supabase_schema.sql`  (from previous step)
   - `supabase/functions_and_triggers.sql`
4. Go to **Storage** and create these buckets (all public):
   - `pothole-images`
   - `depth-maps`
   - `repair-photos`
5. Go to **Settings → API** and copy:
   - Project URL → `SUPABASE_URL`
   - `anon` public key → `SUPABASE_ANON_KEY`
   - `service_role` key → `SUPABASE_SERVICE_KEY`

---

## Step 2 — AI Worker Setup

```bash
cd ai_worker

# Clone Depth Anything V2 into this folder
git clone https://github.com/DepthAnything/Depth-Anything-V2 .
pip install -r requirements.txt

# Download model checkpoint
mkdir checkpoints
# Download depth_anything_v2_vitl.pth from HuggingFace:
# https://huggingface.co/depth-anything/Depth-Anything-V2-Large
# Place it in: checkpoints/depth_anything_v2_vitl.pth

# Copy your YOLOv11 model
cp path/to/your/best.pt checkpoints/pothole_seg.pt

# Set environment variables
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_SERVICE_KEY="YOUR_SERVICE_ROLE_KEY"

# Run the server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Test it:
```bash
curl http://localhost:8000/health
```

---

## Step 3 — Deploy Edge Function

```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link your project
supabase link --project-ref YOUR_PROJECT_REF

# Set secrets
supabase secrets set AI_WORKER_URL=http://YOUR_SERVER_IP:8000

# Deploy
supabase functions deploy trigger-ai-worker
```

---

## Step 4 — Flutter App Setup

### Fill in constants
Edit `flutter_app/lib/core/constants.dart`:
```dart
static const supabaseUrl    = 'https://YOUR_PROJECT.supabase.co';
static const supabaseAnonKey= 'YOUR_ANON_KEY';
static const aiWorkerUrl    = 'http://YOUR_SERVER_IP:8000';
static const googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
```

### Add Google Maps API key

**Android** — `flutter_app/android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
  android:name="com.google.android.geo.API_KEY"
  android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
```

**iOS** — `flutter_app/ios/Runner/AppDelegate.swift`:
```swift
GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
```

### Firebase setup
1. Create Firebase project at https://console.firebase.google.com
2. Add Android app with package name `com.fixmyroad.app`
3. Add iOS app with bundle ID `com.fixmyroad.app`
4. Download and place:
   - `google-services.json` → `flutter_app/android/app/`
   - `GoogleService-Info.plist` → `flutter_app/ios/Runner/`

### Run the app
```bash
cd flutter_app
flutter pub get
flutter run
```

---

## Step 5 — Create First Engineer Account

1. Sign up normally in the app
2. Go to Supabase → Table Editor → `profiles`
3. Find your user and change `role` from `citizen` to `engineer`
4. Sign out and sign in again — you'll see the engineer home screen

---

## Quick Test Flow

1. Sign up as a citizen
2. Go to Report screen, take photo of any surface
3. Submit — watch the AI results appear in real time
4. Open Supabase → `ai_results` table to see the data
5. Sign in as engineer, update the report status
6. Check the citizen app for the status notification

---

## Environment Variables Reference

| Variable                | Where used      | Value |
|-------------------------|-----------------|-------|
| `SUPABASE_URL`          | AI worker       | Your Supabase project URL |
| `SUPABASE_SERVICE_KEY`  | AI worker       | Service role key (not anon) |
| `AI_WORKER_URL`         | Edge Function   | Your FastAPI server URL |
| `SUPABASE_URL`          | Edge Function   | Auto-available in Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function | Auto-available in Supabase |
