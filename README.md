<div align="center">

<img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS-brightgreen?style=for-the-badge&logo=flutter" />
<img src="https://img.shields.io/badge/AI-YOLOv11%20%2B%20Depth%20Anything%20V2-orange?style=for-the-badge&logo=python" />
<img src="https://img.shields.io/badge/Backend-FastAPI-009688?style=for-the-badge&logo=fastapi" />
<img src="https://img.shields.io/badge/Database-Supabase-3ECF8E?style=for-the-badge&logo=supabase" />
<img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" />

# 🚧 FixMyRoad

### AI-Powered Road Pothole Detection & Repair Estimation System

*A smart city platform that lets citizens report potholes, uses deep learning to analyse severity and estimate repair costs, and gives government engineers and administrators a complete management workflow — all in real time.*

**GLS University · B.Tech CSE Capstone Project 2025–26**

[Features](#-features) · [Architecture](#-architecture) · [Screenshots](#-screenshots) · [Quick Start](#-quick-start) · [API Docs](#-api-reference) · [Database](#-database-schema) · [Deployment](#-deployment)

</div>

---

## 📋 Table of Contents

- [About the Project](#-about-the-project)
- [Features](#-features)
- [Architecture](#-architecture)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Quick Start](#-quick-start)
  - [Prerequisites](#prerequisites)
  - [1 · Supabase Setup](#1--supabase-setup)
  - [2 · AI Worker Setup](#2--ai-worker-setup)
  - [3 · Flutter App Setup](#3--flutter-app-setup)
- [Configuration](#-configuration)
- [API Reference](#-api-reference)
- [Database Schema](#-database-schema)
- [AI Pipeline](#-ai-pipeline)
- [User Roles](#-user-roles)
- [Deployment](#-deployment)
- [Team](#-team)

---

## 🧠 About the Project

Road potholes cost Indian municipalities crores of rupees annually in vehicle damage claims, accident liability, and emergency repairs. Traditional monitoring is manual, slow, and inconsistent.

**FixMyRoad** automates the entire pothole management lifecycle:

| Before FixMyRoad | After FixMyRoad |
|---|---|
| Manual field inspection by engineers | Citizens report instantly via smartphone |
| Subjective severity assessment | AI-computed depth score + severity classification |
| Fixed-cost repair budgets | Per-pothole material & labour estimates in INR |
| Paper-based repair tracking | Real-time digital workflow with audit trail |
| No prioritisation logic | Weighted priority score: depth + upvotes + age + severity |

---

## ✨ Features

### 👤 Citizen App
- 📸 **One-tap photo reporting** with automatic GPS geo-tagging
- 🔍 **On-device photo quality check** — rejects blurry or dark images before upload
- 🗺️ **Live pothole map** (OpenStreetMap) with severity-coded markers
- 🔔 **Real-time notifications** when repair status changes
- 👍 **Community upvoting** to boost priority of dangerous potholes
- 📴 **Offline mode** — saves drafts locally, auto-submits on reconnection
- 🔁 **Duplicate detection** — warns if a report already exists within 15 metres
- 🤖 **AI chatbot** for status queries and severity explanations

### 🔧 Engineer App
- 📋 **Priority-sorted repair queue** — deepest, most-upvoted potholes first
- 🧭 **Navigate to site** button (opens Google Maps with directions)
- 📷 **Field update** — upload repair photo, log actual asphalt used and labour hours
- 📊 **Personal stats** — completion rate, total asphalt, total labour hours

### 🏛️ Admin Dashboard
- 📊 **Analytics** — severity pie chart, weekly report bar chart, resolution rate
- 💰 **Budget tracker** — configurable target vs AI-estimated spending
- 👷 **Engineer management** — assign repairs, view completion rates, promote to admin
- 📄 **Full report lifecycle** — assign, review, reject, mark fixed with one tap
- 🔍 **Filter & search** — by status, severity, date, engineer

### 🤖 AI Analysis Engine
- 🎯 **YOLOv11 instance segmentation** — pixel-level pothole boundary detection
- 📏 **Depth Anything V2 (ViT-Large)** — monocular depth estimation without sensors
- 📐 **Volume-based cost estimation** — asphalt kg, labour hours, INR range
- 🖼️ **3 visualisation outputs** — depth map, severity heatmap, before/after comparison
- 🔁 **Smart fallback** — heuristic detector when YOLO confidence is insufficient

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                        │
│                                                                   │
│   Flutter App (Android / iOS)                                     │
│   ├── Citizen: Map, Submit, My Reports, Notifications, Chatbot   │
│   ├── Engineer: Repair Queue, Field Update, Stats                 │
│   └── Admin: Reports, Analytics, Engineers, Budget               │
└──────────────────────┬───────────────────────────────────────────┘
                       │  HTTPS / REST + WebSocket (Realtime)
┌──────────────────────▼───────────────────────────────────────────┐
│                        BUSINESS LOGIC LAYER                       │
│                                                                   │
│   FastAPI AI Worker (Python)                                      │
│   ├── YOLOv11-seg — pothole boundary segmentation                │
│   ├── Depth Anything V2 — monocular depth estimation             │
│   ├── Cost Estimator — asphalt + labour + INR calculation        │
│   └── Visualisation — depth map, heatmap, before/after           │
└──────────────────────┬───────────────────────────────────────────┘
                       │  supabase-py (service role)
┌──────────────────────▼───────────────────────────────────────────┐
│                          DATA LAYER                               │
│                                                                   │
│   Supabase (PostgreSQL + PostGIS)                                 │
│   ├── Auth — JWT sessions, role management                        │
│   ├── Database — reports, ai_results, profiles, notifications     │
│   ├── Storage — pothole images, depth maps, repair photos         │
│   └── Realtime — WebSocket push to Flutter clients               │
└──────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| Mobile | Flutter | 3.22+ | Cross-platform UI (Android + iOS) |
| Mobile | Dart | 3.3+ | Null-safe language for Flutter |
| Mobile | flutter_map + latlong2 | 6.1.0 / 0.9.0 | OpenStreetMap integration |
| Mobile | flutter_riverpod | 2.5.1 | State management |
| Mobile | go_router | 14.2.7 | Declarative navigation |
| Mobile | supabase_flutter | 2.5.6 | Auth, DB, Storage, Realtime |
| Mobile | geolocator | 12.0.0 | GPS location |
| Mobile | sqflite | 2.3.3 | Local offline draft storage |
| Mobile | connectivity_plus | 6.0.3 | Network monitoring |
| Mobile | fl_chart | 0.68.0 | Admin analytics charts |
| AI Backend | Python | 3.10+ | AI pipeline language |
| AI Backend | FastAPI | 0.115.0 | REST API server |
| AI Backend | Ultralytics YOLO | 8.3.0 | YOLOv11 inference |
| AI Backend | Depth Anything V2 | ViT-L | Depth estimation |
| AI Backend | PyTorch | 2.4.1 | Deep learning framework |
| AI Backend | OpenCV | 4.10.0 | Image processing |
| AI Backend | Matplotlib | 3.9.2 | Visualisation generation |
| Database | PostgreSQL + PostGIS | 15 + 3.x | Spatial database |
| Cloud | Supabase | Hosted | Auth + DB + Storage + Realtime |

---

## 📁 Project Structure

```
fixmyroad/
│
├── flutter_app/                    # Flutter mobile application
│   ├── android/                    # Android-specific config
│   │   └── app/src/main/
│   │       └── AndroidManifest.xml # Permissions + Maps API key
│   ├── lib/
│   │   ├── main.dart               # App entry point
│   │   ├── core/
│   │   │   ├── constants.dart      # API keys, URLs, thresholds
│   │   │   ├── router.dart         # GoRouter navigation
│   │   │   └── theme.dart          # Colours, severity colours
│   │   ├── features/
│   │   │   ├── auth/               # Login, register, profile
│   │   │   ├── reports/            # Submit, list, detail, result
│   │   │   ├── map/                # OpenStreetMap pothole map
│   │   │   ├── notifications/      # Notification feed
│   │   │   ├── chatbot/            # AI chat assistant
│   │   │   ├── engineer/           # Repair queue + field update
│   │   │   └── admin/              # Dashboard, analytics, team
│   │   └── shared/
│   │       ├── models/models.dart  # Report, AiResult, Profile, etc.
│   │       ├── services/           # Supabase, AI trigger, offline, quality
│   │       ├── widgets/widgets.dart # SeverityBadge, ReportCard, etc.
│   │       └── screens/            # Splash screen, main shell nav
│   └── pubspec.yaml                # Flutter dependencies
│
├── ai_worker/                      # Python FastAPI AI backend
│   ├── main.py                     # FastAPI server + /analyze endpoint
│   ├── pipeline.py                 # YOLOv11 + Depth Anything V2 pipeline
│   ├── cost_estimator.py           # INR repair cost calculation
│   ├── supabase_client.py          # Supabase Python client
│   ├── pdf_generator.py            # Monthly report PDF generator (stub)
│   ├── requirements.txt            # Python dependencies
│   └── checkpoints/                # AI model weights (git-ignored)
│       ├── pothole_seg.pt          # Fine-tuned YOLOv11 weights
│       └── depth_anything_v2_vitl.pth  # Depth model weights
│
└── supabase/                       # Database SQL files
    ├── schema.sql                  # All table definitions + ENUM types
    ├── rls_policies.sql            # Row Level Security policies
    └── triggers.sql                # Database automation triggers
```

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version | Download |
|---|---|---|
| Flutter SDK | 3.22+ | [flutter.dev](https://flutter.dev) |
| Dart SDK | 3.3+ | Included with Flutter |
| Python | 3.10+ | [python.org](https://python.org) |
| Git | Any | [git-scm.com](https://git-scm.com) |
| Android Studio / VS Code | Latest | For Flutter development |

---

### 1 · Supabase Setup

**Step 1** — Create a free project at [supabase.com](https://supabase.com)

**Step 2** — Open the **SQL Editor** and run the following in order:

```sql
-- 1. Create ENUM types
CREATE TYPE user_role       AS ENUM ('citizen', 'engineer', 'admin');
CREATE TYPE report_status   AS ENUM ('submitted', 'under_review', 'assigned',
                                     'in_progress', 'fixed', 'rejected');
CREATE TYPE pothole_severity AS ENUM ('shallow', 'moderate', 'deep');

-- 2. Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 3. Create profiles table
CREATE TABLE profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT,
  phone       TEXT,
  avatar_url  TEXT,
  role        user_role    NOT NULL DEFAULT 'citizen',
  fcm_token   TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 4. Create reports table
CREATE TABLE reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  citizen_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assigned_to  UUID REFERENCES profiles(id) ON DELETE SET NULL,
  status       report_status NOT NULL DEFAULT 'submitted',
  description  TEXT,
  image_url    TEXT NOT NULL,
  latitude     FLOAT8 NOT NULL,
  longitude    FLOAT8 NOT NULL,
  location     GEOGRAPHY(POINT, 4326),
  address      TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX reports_location_idx ON reports USING GIST (location);

-- 5. Create ai_results table
CREATE TABLE ai_results (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id        UUID NOT NULL UNIQUE REFERENCES reports(id) ON DELETE CASCADE,
  relative_depth   FLOAT8,
  max_depth        FLOAT8,
  severity         pothole_severity,
  pothole_area_px  FLOAT8,
  confidence       FLOAT8,
  repair_cost_min  FLOAT8,
  repair_cost_max  FLOAT8,
  asphalt_kg       FLOAT8,
  labour_hours     FLOAT8,
  material_cost_est FLOAT8,
  priority_score   FLOAT8,
  depth_map_url    TEXT,
  heatmap_url      TEXT,
  before_after_url TEXT,
  model_encoder    TEXT DEFAULT 'vitl',
  processing_time_s FLOAT8,
  processed_at     TIMESTAMPTZ DEFAULT now()
);

-- 6. Create upvotes table
CREATE TABLE upvotes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  citizen_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(report_id, citizen_id)
);

-- 7. Create status_history table
CREATE TABLE status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  changed_by  UUID NOT NULL REFERENCES profiles(id),
  old_status  report_status,
  new_status  report_status NOT NULL,
  note        TEXT,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. Create notifications table
CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  report_id   UUID REFERENCES reports(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  is_read     BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Step 3** — Add storage buckets:

Go to **Storage → New bucket** and create these three (all public):
- `pothole-images`
- `depth-maps`
- `repair-photos`

Then run this storage policy:
```sql
CREATE POLICY "Allow all storage"
ON storage.objects FOR ALL USING (true) WITH CHECK (true);
```

**Step 4** — Enable Row Level Security:

```sql
-- Allow public read of reports
ALTER TABLE reports   ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE upvotes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE status_history ENABLE ROW LEVEL SECURITY;

-- Profiles: read own, engineers/admins read all
CREATE POLICY "profiles_read" ON profiles FOR SELECT
  USING (id = auth.uid() OR
         (auth.jwt() ->> 'role') IN ('engineer', 'admin'));

CREATE POLICY "profiles_insert" ON profiles FOR INSERT
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update" ON profiles FOR UPDATE
  USING (id = auth.uid());

-- Reports: public read, citizen insert own, update by all authenticated
CREATE POLICY "reports_read_all"   ON reports FOR SELECT USING (true);
CREATE POLICY "reports_insert"     ON reports FOR INSERT
  WITH CHECK (citizen_id = auth.uid());
CREATE POLICY "reports_update_all" ON reports FOR UPDATE
  USING (true) WITH CHECK (true);

-- AI results: authenticated read
CREATE POLICY "ai_results_read" ON ai_results FOR SELECT
  USING (auth.uid() IS NOT NULL);
CREATE POLICY "ai_results_write" ON ai_results FOR ALL USING (true) WITH CHECK (true);

-- Upvotes
CREATE POLICY "upvotes_read"   ON upvotes FOR SELECT USING (true);
CREATE POLICY "upvotes_insert" ON upvotes FOR INSERT WITH CHECK (citizen_id = auth.uid());

-- Notifications: own only
CREATE POLICY "notifications_read"   ON notifications FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "notifications_update" ON notifications FOR UPDATE
  USING (user_id = auth.uid());
CREATE POLICY "notifications_insert" ON notifications FOR ALL
  USING (true) WITH CHECK (true);

-- Status history: authenticated read
CREATE POLICY "history_read" ON status_history FOR SELECT
  USING (auth.uid() IS NOT NULL);
CREATE POLICY "history_insert" ON status_history FOR INSERT WITH CHECK (true);
```

**Step 5** — Add database triggers:

```sql
-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO profiles (id, full_name, role)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', 'citizen')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Auto-set PostGIS location from lat/lng
CREATE OR REPLACE FUNCTION set_report_location()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
  RETURN NEW;
END;
$$;
CREATE TRIGGER set_location
  BEFORE INSERT OR UPDATE OF latitude, longitude ON reports
  FOR EACH ROW EXECUTE FUNCTION set_report_location();

-- Auto-log status changes
CREATE OR REPLACE FUNCTION log_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO status_history (report_id, changed_by, old_status, new_status)
    VALUES (NEW.id, COALESCE(auth.uid(), NEW.citizen_id), OLD.status, NEW.status);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_status_change
  AFTER UPDATE OF status ON reports
  FOR EACH ROW EXECUTE FUNCTION log_status_change();

-- Auto-create notification on status change
CREATE OR REPLACE FUNCTION notify_citizen()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE msg TEXT;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    msg := CASE NEW.status
      WHEN 'under_review' THEN 'Your report is being reviewed.'
      WHEN 'assigned'     THEN 'An engineer has been assigned to your pothole.'
      WHEN 'in_progress'  THEN 'Repair work has started on your pothole.'
      WHEN 'fixed'        THEN '✅ Your pothole has been repaired!'
      WHEN 'rejected'     THEN 'Your report could not be actioned at this time.'
      ELSE 'Your report status has been updated.'
    END;
    INSERT INTO notifications (user_id, report_id, title, body)
    VALUES (NEW.citizen_id, NEW.id, 'Report update', msg);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER on_report_notify
  AFTER UPDATE OF status ON reports
  FOR EACH ROW EXECUTE FUNCTION notify_citizen();
```

---

### 2 · AI Worker Setup

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/fixmyroad.git
cd fixmyroad/ai_worker

# Create and activate virtual environment
python -m venv venv
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Download model weights
# Place these files in ai_worker/checkpoints/
#   pothole_seg.pt            — your fine-tuned YOLOv11-seg weights
#   depth_anything_v2_vitl.pth — from https://huggingface.co/depth-anything/Depth-Anything-V2-Large
mkdir checkpoints
```

**Set environment variables:**

```bash
# Windows CMD
set SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
set SUPABASE_SERVICE_KEY=YOUR_SERVICE_ROLE_KEY

# macOS / Linux
export SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
export SUPABASE_SERVICE_KEY=YOUR_SERVICE_ROLE_KEY
```

**Start the server:**

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Verify it's running:
```
http://localhost:8000/health
# → {"status":"ok","gpu":false}
```

Interactive API docs: `http://localhost:8000/docs`

---

### 3 · Flutter App Setup

```bash
cd fixmyroad/flutter_app

# Install dependencies
flutter pub get
```

**Update `lib/core/constants.dart`:**

```dart
class AppConstants {
  // Your Supabase project URL (from Settings → API)
  static const supabaseUrl     = 'https://YOUR_PROJECT_REF.supabase.co';
  
  // Your Supabase anon key (from Settings → API)
  static const supabaseAnonKey = 'YOUR_ANON_KEY';

  // AI Worker URL:
  //   Emulator → 'http://10.0.2.2:8000'
  //   Real phone (same WiFi) → 'http://192.168.x.x:8000'
  //   Deployed → 'https://your-render-app.onrender.com'
  static const aiWorkerUrl     = 'http://10.0.2.2:8000';
}
```

**Run the app:**

```bash
# On emulator
flutter run

# On connected Android phone
flutter run -d YOUR_DEVICE_ID

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

---

## ⚙️ Configuration

| File | Variable | Description |
|---|---|---|
| `constants.dart` | `supabaseUrl` | Supabase project URL |
| `constants.dart` | `supabaseAnonKey` | Supabase public anon key |
| `constants.dart` | `aiWorkerUrl` | FastAPI server URL |
| `constants.dart` | `duplicateRadiusMetres` | Duplicate report detection radius (default: 15m) |
| `constants.dart` | `blurThreshold` | Photo sharpness minimum (default: 50.0) |
| `constants.dart` | `brightnessThreshold` | Photo brightness minimum (default: 30.0) |
| `ai_worker/.env` | `SUPABASE_URL` | Supabase URL for Python backend |
| `ai_worker/.env` | `SUPABASE_SERVICE_KEY` | Service role key (bypasses RLS) |
| `pipeline.py` | `conf=0.15` | YOLO detection confidence threshold |
| `cost_estimator.py` | `PIXELS_PER_M2` | Camera calibration (default: 6000 px/m²) |
| `cost_estimator.py` | `LABOUR_RATE` | Labour cost in INR/hour (default: ₹500) |

---

## 📡 API Reference

Base URL: `http://localhost:8000`

### `GET /health`
Returns server status and GPU availability.

```json
{
  "status": "ok",
  "gpu": false,
  "gpu_name": null
}
```

---

### `POST /analyze`
Triggers AI analysis for a submitted report.

**Request body:**
```json
{
  "report_id": "uuid-of-the-report",
  "image_url": "https://your-supabase-url/storage/v1/.../photo.jpg"
}
```

**Response:**
```json
{
  "report_id":        "uuid",
  "severity":         "moderate",
  "relative_depth":   0.0842,
  "max_depth":        0.1134,
  "pothole_area_px":  4821,
  "confidence":       0.7340,
  "repair_cost_min":  1800,
  "repair_cost_max":  4200,
  "asphalt_kg":       3.24,
  "labour_hours":     1.5,
  "material_cost_est": 2840.50,
  "depth_map_url":    "https://.../_depth.png",
  "heatmap_url":      "https://.../_heatmap.png",
  "before_after_url": "https://.../_before_after.png",
  "processing_time_s": 48.3
}
```

---

### `GET /results/{report_id}`
Returns stored AI results for an already-processed report.

---

## 🗄️ Database Schema

```
profiles ──────────┐
  id (PK)          │ 1
  full_name        │          reports ──────────────────┐
  role (ENUM)      ├──────── citizen_id (FK)  1         │
  phone            │         assigned_to (FK) ──────────┤
  fcm_token        │         status (ENUM)              │ 1
                   │         image_url                   │
                   │         latitude / longitude         ├── ai_results (1:1)
                   │         location (PostGIS)           │     severity (ENUM)
                   │         submitted_at                 │     relative_depth
                   │                                      │     repair_cost_min/max
                   │                          N           │     asphalt_kg
                   ├──────── upvotes ──────────────────── │     heatmap_url
                   │           report_id (FK)             │
                   │           citizen_id (FK)            │ N
                   │           UNIQUE constraint          ├── status_history
                   │                                      │     old_status
                   │                          N           │     new_status
                   └──────── notifications ──────────────  └── (immutable log)
                                user_id (FK)
                                report_id (FK)
                                is_read
```

**Priority Score Formula:**
```
P = (max_depth × 40) + min(upvotes × 0.3, 30) + min(age_days × 0.2, 20) + (severity_weight × 10)

severity_weight: shallow=0.3  moderate=0.6  deep=1.0
Range: 0 – 100
```

---

## 🤖 AI Pipeline

```
Input: JPEG/PNG photo from citizen's phone
           │
           ▼
┌──────────────────────┐
│  Image preprocessing  │  Resize to max 1280px, decode with OpenCV
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Depth Anything V2   │  ViT-Large encoder → dense float32 depth map
│  (monocular depth)   │  Output: [0,1] per-image, higher = closer
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  YOLOv11-seg         │  conf=0.15, produces binary segmentation mask
│  (pothole detection) │  Falls back to heuristic if nothing detected
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Depth metrics       │  Local road reference (51px dilated ring)
│  (severity)          │  rel_depth / road_std → normalised severity score
│                      │  Thresholds: <0.4=shallow  0.4–1.0=moderate  >1.0=deep
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Cost estimation     │  area_px→m², rel_depth→cm, volume→litres→kg
│  (INR)               │  asphalt_kg × ₹18.5 + labour_hrs × ₹500 + overhead
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Visualisations      │  Depth map (magma), heatmap (RdYlGn), before/after
└──────────┬───────────┘
           │
           ▼
Output: severity, depth, cost estimate, 3 PNG images → Supabase
```

**Severity thresholds (normalised relative depth):**

| Range | Severity | Est. Physical Depth | Cost Range |
|---|---|---|---|
| < 0.40 | 🟢 Shallow | < 2 cm | ₹500 – ₹1,800 |
| 0.40 – 1.00 | 🟡 Moderate | 2 – 5 cm | ₹1,800 – ₹6,000 |
| > 1.00 | 🔴 Deep | > 5 cm | ₹6,000 – ₹18,000 |

---

## 👥 User Roles

| Feature | Citizen | Engineer | Admin |
|---|---|---|---|
| Submit pothole report | ✅ | ❌ | ❌ |
| View public map | ✅ | ✅ | ✅ |
| View own reports | ✅ | ❌ | ✅ |
| View severity badge | ✅ | ✅ | ✅ |
| View repair cost / depth metrics | ❌ | ✅ | ✅ |
| Upvote reports | ✅ | ❌ | ❌ |
| View assigned repairs | ❌ | ✅ | ✅ |
| Update repair status | ❌ | ✅ | ✅ |
| Upload repair photo | ❌ | ✅ | ✅ |
| Assign engineers | ❌ | ❌ | ✅ |
| View analytics dashboard | ❌ | ❌ | ✅ |
| Manage engineer team | ❌ | ❌ | ✅ |
| View budget tracker | ❌ | ❌ | ✅ |

**To change a user's role** (Supabase Table Editor):
```sql
UPDATE profiles SET role = 'engineer' WHERE id = 'USER_UUID';
UPDATE profiles SET role = 'admin'    WHERE id = 'USER_UUID';
```

---

## 🚢 Deployment

### AI Worker Options

| Option | Cost | GPU | Best for |
|---|---|---|---|
| **ngrok** (local PC) | Free | Your PC's | Quick demo |
| **Google Colab** | Free | T4 GPU | Presentation day |
| **Render.com** | Free | CPU only | Permanent hosting |
| **Railway.app** | ~$5/mo | CPU only | Production |

**Google Colab (recommended for demo):**
```python
!pip install fastapi uvicorn pyngrok supabase ultralytics -q
from pyngrok import ngrok
ngrok.set_auth_token("YOUR_TOKEN")    # free at ngrok.com
import subprocess, threading
threading.Thread(
  target=lambda: subprocess.run(["uvicorn","main:app","--port","8000"]),
  daemon=True
).start()
import time; time.sleep(3)
url = ngrok.connect(8000)
print(f"AI Worker URL: {url}")        # paste this into constants.dart
```

**Render.com:**
1. Push `ai_worker/` to GitHub
2. New Web Service → connect repo → branch: `main`
3. Build: `pip install -r requirements.txt`
4. Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
5. Add env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`

### Flutter App

```bash
# Release APK (share directly — no Play Store needed)
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Play Store App Bundle
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

---

## 📦 requirements.txt

```txt
fastapi==0.115.0
uvicorn[standard]==0.30.6
httpx==0.27.0
python-multipart==0.0.9
pydantic==2.8.2
supabase==2.7.4
ultralytics==8.3.0
torch==2.4.1
torchvision==0.19.1
opencv-python==4.10.0.84
numpy==1.26.4
matplotlib==3.9.2
Pillow==10.4.0
```

---

## 🔒 Security Notes

- The **service role key** in `ai_worker/` **must never** be committed to git or included in the Flutter app. Add `ai_worker/.env` to `.gitignore`.
- All Supabase tables have **Row Level Security** enabled.
- Citizen app uses the **anon key** only — restricted by RLS policies.
- GPS data is collected only during active report submission with explicit user consent.
- Report images are stored in access-controlled Supabase Storage buckets.

### `.gitignore` additions
```
# Secrets
ai_worker/.env
ai_worker/checkpoints/

# Flutter
flutter_app/lib/core/constants.dart   # add keys locally only

# Python
ai_worker/__pycache__/
ai_worker/venv/
```

---

## 👨‍💻 Team

| Name | Enrollment No. | Role |
|---|---|---|
| Tirth Goti | 202302626010087 | AI Pipeline + Backend |
| Devansh Prajapati | 202302626010102 | Flutter App + UI/UX |
| Ujas Dubal | 202302626010148 | Database + Supabase |
| Jaimin Solanki | 202302626010152 | Testing + Documentation |

**Project Guide:** Ms. Twinkle K. Patel, Assistant Professor, Dept. of CSE  
**Institution:** Faculty of Engineering and Technology, GLS University, Ahmedabad  
**Academic Year:** 2025–26

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

Made with ❤️ at GLS University, Ahmedabad

⭐ Star this repo if you found it useful!

</div>
