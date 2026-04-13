-- ─────────────────────────────────────────────────────────────────────────────
-- FixMyRoad — Functions, Triggers & Extra Tables
-- Run this AFTER supabase_schema.sql
-- ─────────────────────────────────────────────────────────────────────────────

-- ── STEP 1: Extra columns on ai_results ──────────────────────────────────────
alter table ai_results
  add column if not exists asphalt_kg         float8,
  add column if not exists labour_hours       float8,
  add column if not exists material_cost_est  float8,
  add column if not exists priority_score     float8;

-- ── STEP 2: Upvotes table ─────────────────────────────────────────────────────
create table if not exists upvotes (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references reports(id) on delete cascade,
  citizen_id  uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (report_id, citizen_id)
);

alter table upvotes enable row level security;

create policy "Citizens can upvote" on upvotes
  for insert with check (auth.uid() = citizen_id);

create policy "Anyone can read upvotes" on upvotes
  for select using (true);

-- ── STEP 3: Area scores table ─────────────────────────────────────────────────
create table if not exists area_scores (
  id              uuid primary key default gen_random_uuid(),
  area_name       text not null,
  location        geography(point, 4326),
  condition_score float8 not null default 100,
  report_count    int   not null default 0,
  calculated_at   timestamptz not null default now()
);

-- ── STEP 4: Helper — find nearby open report (duplicate detection) ─────────────
create or replace function find_nearby_open_report(
  p_lat    float8,
  p_lng    float8,
  p_radius float8 default 15.0
)
returns setof reports
language sql stable as $$
  select r.*
  from   reports r
  where  r.status not in ('fixed', 'rejected')
  and    st_dwithin(
           r.location,
           st_point(p_lng, p_lat)::geography,
           p_radius
         )
  order  by r.submitted_at desc
  limit  1;
$$;

-- ── STEP 5: Priority score — recalculate on upvote ────────────────────────────
create or replace function recalculate_priority_score()
returns trigger language plpgsql security definer as $$
declare
  v_report_id  uuid;
  v_upvotes    int;
  v_age_days   float8;
  v_sev_weight float8;
  v_max_depth  float8;
  v_score      float8;
begin
  v_report_id := new.report_id;

  select count(*) into v_upvotes
  from upvotes where report_id = v_report_id;

  select extract(epoch from now() - submitted_at) / 86400
  into v_age_days
  from reports where id = v_report_id;

  select
    case severity
      when 'deep'     then 1.0
      when 'moderate' then 0.6
      else 0.3
    end,
    coalesce(max_depth, 0)
  into v_sev_weight, v_max_depth
  from ai_results where report_id = v_report_id;

  v_score :=
    (coalesce(v_max_depth, 0) * 40)
    + least(coalesce(v_upvotes, 0) * 0.3, 30)
    + least(coalesce(v_age_days, 0) * 0.2, 20)
    + (coalesce(v_sev_weight, 0.3) * 10);

  update ai_results
  set priority_score = v_score
  where report_id = v_report_id;

  return new;
end;
$$;

create trigger on_upvote_recalculate
  after insert on upvotes
  for each row execute procedure recalculate_priority_score();

-- ── STEP 6: Priority score — recalculate on AI result insert ─────────────────
create or replace function recalculate_priority_on_ai_insert()
returns trigger language plpgsql security definer as $$
declare
  v_upvotes  int;
  v_age_days float8;
  v_sev_w    float8;
  v_score    float8;
begin
  select count(*) into v_upvotes
  from upvotes where report_id = new.report_id;

  select extract(epoch from now() - submitted_at) / 86400
  into v_age_days
  from reports where id = new.report_id;

  v_sev_w := case new.severity
    when 'deep'     then 1.0
    when 'moderate' then 0.6
    else 0.3
  end;

  v_score :=
    (coalesce(new.max_depth, 0) * 40)
    + least(coalesce(v_upvotes, 0) * 0.3, 30)
    + least(coalesce(v_age_days, 0) * 0.2, 20)
    + (v_sev_w * 10);

  new.priority_score := v_score;
  return new;
end;
$$;

create trigger on_ai_result_insert_score
  before insert on ai_results
  for each row execute procedure recalculate_priority_on_ai_insert();

-- ── STEP 7: Edge Function trigger (requires pg_net extension) ─────────────────
-- NOTE: Only run this section after enabling pg_net in Dashboard > Extensions
-- and after deploying the Edge Function.
-- Comment this out for now if you haven't deployed the Edge Function yet.

/*
create or replace function trigger_ai_worker()
returns trigger language plpgsql security definer as $$
begin
  perform net.http_post(
    url     := current_setting('app.edge_function_url') ||
               '/functions/v1/trigger-ai-worker',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key')
    ),
    body    := jsonb_build_object('record', row_to_json(new))
  );
  return new;
end;
$$;

create trigger on_report_inserted_trigger_ai
  after insert on reports
  for each row execute procedure trigger_ai_worker();
*/

-- ── STEP 8: Public view for map (no personal data) ────────────────────────────
create or replace view reports_public as
  select
    r.id,
    r.latitude,
    r.longitude,
    r.status,
    r.submitted_at,
    a.severity,
    a.priority_score
  from reports r
  left join ai_results a on a.report_id = r.id
  where r.status not in ('rejected');

grant select on reports_public to anon;
