-- ─────────────────────────────────────────────────────────────────────────────
-- Pothole Reporter App — Supabase Schema
-- Paste this entire file into the Supabase SQL Editor and run it.
-- ─────────────────────────────────────────────────────────────────────────────

-- Enable PostGIS for GPS geometry queries
create extension if not exists postgis;

-- ── ENUM: report status lifecycle ────────────────────────────────────────────
create type report_status as enum (
  'submitted',      -- citizen just submitted
  'under_review',   -- government team reviewing
  'assigned',       -- assigned to an engineer
  'in_progress',    -- repair team on site
  'fixed',          -- repair complete
  'rejected'        -- duplicate or invalid report
);

-- ── ENUM: user roles ──────────────────────────────────────────────────────────
create type user_role as enum (
  'citizen',
  'engineer',
  'admin'
);

-- ── ENUM: severity ────────────────────────────────────────────────────────────
create type pothole_severity as enum (
  'shallow',
  'moderate',
  'deep'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: profiles
-- Extends Supabase auth.users — one row per registered user.
-- ─────────────────────────────────────────────────────────────────────────────
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text,
  phone         text,
  avatar_url    text,
  role          user_role not null default 'citizen',
  fcm_token     text,                        -- for push notifications (Firebase)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Auto-create a profile row when a new user signs up
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: reports
-- Core table — one row per pothole report submitted by a citizen.
-- ─────────────────────────────────────────────────────────────────────────────
create table reports (
  id              uuid primary key default gen_random_uuid(),
  citizen_id      uuid not null references profiles(id) on delete cascade,
  assigned_to     uuid references profiles(id) on delete set null,  -- engineer

  -- Status
  status          report_status not null default 'submitted',

  -- Report content
  description     text,
  image_url       text not null,             -- Supabase Storage public URL

  -- Location
  latitude        float8 not null,
  longitude       float8 not null,
  location        geography(point, 4326),    -- PostGIS geometry (auto-set below)
  address         text,                      -- reverse-geocoded address

  -- Timestamps
  submitted_at    timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Auto-populate PostGIS geography column from lat/lng
create or replace function set_report_location()
returns trigger language plpgsql as $$
begin
  new.location := st_point(new.longitude, new.latitude)::geography;
  return new;
end;
$$;

create trigger set_location_on_insert
  before insert or update of latitude, longitude on reports
  for each row execute procedure set_report_location();

-- Spatial index for fast "find potholes near me" queries
create index reports_location_idx on reports using gist(location);
create index reports_citizen_id_idx on reports(citizen_id);
create index reports_status_idx on reports(status);
create index reports_submitted_at_idx on reports(submitted_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: ai_results
-- One row per report — filled in by the FastAPI AI worker after analysis.
-- ─────────────────────────────────────────────────────────────────────────────
create table ai_results (
  id                  uuid primary key default gen_random_uuid(),
  report_id           uuid not null unique references reports(id) on delete cascade,

  -- Depth Anything V2 metrics
  relative_depth      float8,                -- normalized 0-1
  max_depth           float8,                -- normalized 0-1
  severity            pothole_severity,
  pothole_area_px     float8,                -- pixel count of mask
  confidence          float8,                -- YOLO detection confidence

  -- Repair cost estimate (in local currency)
  repair_cost_min     float8,
  repair_cost_max     float8,

  -- Output image URLs (stored in Supabase Storage)
  depth_map_url       text,
  heatmap_url         text,
  before_after_url    text,

  -- Processing metadata
  model_encoder       text default 'vitl',   -- vits / vitb / vitl
  processing_time_s   float8,
  processed_at        timestamptz default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: status_history
-- Audit trail — every status change is logged here.
-- ─────────────────────────────────────────────────────────────────────────────
create table status_history (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references reports(id) on delete cascade,
  changed_by    uuid not null references profiles(id),
  old_status    report_status,
  new_status    report_status not null,
  note          text,                        -- optional engineer comment
  changed_at    timestamptz not null default now()
);

create index status_history_report_idx on status_history(report_id);

-- Auto-log status changes in reports table
create or replace function log_status_change()
returns trigger language plpgsql security definer as $$
begin
  if old.status is distinct from new.status then
    insert into status_history (report_id, changed_by, old_status, new_status)
    values (new.id, auth.uid(), old.status, new.status);
  end if;
  return new;
end;
$$;

create trigger on_status_change
  after update of status on reports
  for each row execute procedure log_status_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: notifications
-- In-app notifications sent to citizens when their report status changes.
-- ─────────────────────────────────────────────────────────────────────────────
create table notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  report_id     uuid references reports(id) on delete cascade,
  title         text not null,
  body          text not null,
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);

create index notifications_user_idx on notifications(user_id, is_read);

-- Auto-create notification when report status changes
create or replace function notify_citizen_on_status_change()
returns trigger language plpgsql security definer as $$
declare
  citizen_id uuid;
  msg_title  text;
  msg_body   text;
begin
  if old.status is distinct from new.status then
    select r.citizen_id into citizen_id from reports r where r.id = new.id;

    msg_title := case new.status
      when 'under_review' then 'Report received'
      when 'assigned'     then 'Engineer assigned'
      when 'in_progress'  then 'Repair started'
      when 'fixed'        then 'Pothole fixed!'
      when 'rejected'     then 'Report update'
      else 'Report updated'
    end;

    msg_body := case new.status
      when 'under_review' then 'Your pothole report is being reviewed by the team.'
      when 'assigned'     then 'An engineer has been assigned to your report.'
      when 'in_progress'  then 'The repair team is working on your reported pothole.'
      when 'fixed'        then 'The pothole you reported has been repaired. Thank you!'
      when 'rejected'     then 'Your report has been reviewed and closed.'
      else 'Your report status has been updated to ' || new.status::text || '.'
    end;

    insert into notifications (user_id, report_id, title, body)
    values (citizen_id, new.id, msg_title, msg_body);
  end if;
  return new;
end;
$$;

create trigger on_report_status_notify
  after update of status on reports
  for each row execute procedure notify_citizen_on_status_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS)
-- ─────────────────────────────────────────────────────────────────────────────

-- profiles
alter table profiles enable row level security;
create policy "Users can view own profile"
  on profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on profiles for update using (auth.uid() = id);
create policy "Engineers can view all profiles"
  on profiles for select using (
    exists (select 1 from profiles where id = auth.uid() and role in ('engineer','admin'))
  );

-- reports
alter table reports enable row level security;
create policy "Citizens can insert own reports"
  on reports for insert with check (auth.uid() = citizen_id);
create policy "Citizens can view own reports"
  on reports for select using (auth.uid() = citizen_id);
create policy "Engineers can view all reports"
  on reports for select using (
    exists (select 1 from profiles where id = auth.uid() and role in ('engineer','admin'))
  );
create policy "Engineers can update reports"
  on reports for update using (
    exists (select 1 from profiles where id = auth.uid() and role in ('engineer','admin'))
  );

-- ai_results
alter table ai_results enable row level security;
create policy "Citizens can view own ai results"
  on ai_results for select using (
    exists (select 1 from reports where id = ai_results.report_id and citizen_id = auth.uid())
  );
create policy "Engineers can view all ai results"
  on ai_results for select using (
    exists (select 1 from profiles where id = auth.uid() and role in ('engineer','admin'))
  );
create policy "Service role can insert ai results"
  on ai_results for insert with check (true);  -- only AI worker (service key) inserts

-- status_history
alter table status_history enable row level security;
create policy "Citizens can view own status history"
  on status_history for select using (
    exists (select 1 from reports where id = status_history.report_id and citizen_id = auth.uid())
  );
create policy "Engineers can view all status history"
  on status_history for select using (
    exists (select 1 from profiles where id = auth.uid() and role in ('engineer','admin'))
  );

-- notifications
alter table notifications enable row level security;
create policy "Users can view own notifications"
  on notifications for select using (auth.uid() = user_id);
create policy "Users can mark own notifications read"
  on notifications for update using (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- USEFUL QUERIES (reference)
-- ─────────────────────────────────────────────────────────────────────────────

-- Find all potholes within 1km of a GPS point
-- select r.*, a.severity, a.repair_cost_max
-- from reports r
-- join ai_results a on a.report_id = r.id
-- where st_dwithin(
--   r.location,
--   st_point(74.0060, 40.7128)::geography,  -- lng, lat
--   1000                                     -- metres
-- )
-- order by r.submitted_at desc;

-- Get repair cost summary by severity
-- select
--   a.severity,
--   count(*) as total,
--   sum(a.repair_cost_max) as total_cost_estimate
-- from ai_results a
-- join reports r on r.id = a.report_id
-- where r.status != 'rejected'
-- group by a.severity;
