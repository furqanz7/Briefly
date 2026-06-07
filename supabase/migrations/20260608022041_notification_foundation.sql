create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null,
  platform text not null default 'ios',
  bundle_id text,
  app_version text,
  environment text not null default 'production',
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_devices_platform_check check (platform in ('ios')),
  constraint push_devices_environment_check check (environment in ('production', 'sandbox')),
  unique (user_id, device_token)
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_brief_enabled boolean not null default true,
  breaking_news_enabled boolean not null default false,
  jobs_enabled boolean not null default true,
  sports_enabled boolean not null default false,
  reading_goal_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  daily_brief_time time not null default '08:00',
  updated_at timestamptz not null default now()
);

create table if not exists public.job_activity_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  role_query text,
  job_id text,
  job_title text,
  company text,
  market text,
  deck text,
  location text,
  work_mode text,
  keywords text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint job_activity_events_event_type_check check (
    event_type in ('search', 'open', 'save', 'pass', 'apply')
  )
);

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id uuid references public.push_devices(id) on delete set null,
  notification_type text not null,
  title text not null,
  body text not null,
  target_url text,
  dedupe_key text,
  status text not null default 'queued',
  provider_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  constraint notification_deliveries_status_check check (
    status in ('queued', 'sent', 'failed', 'skipped')
  ),
  unique (user_id, device_id, notification_type, dedupe_key)
);

create index if not exists push_devices_user_enabled_idx
  on public.push_devices (user_id, enabled, last_seen_at desc);

create index if not exists job_activity_events_user_recent_idx
  on public.job_activity_events (user_id, created_at desc);

create index if not exists job_activity_events_user_event_recent_idx
  on public.job_activity_events (user_id, event_type, created_at desc);

create index if not exists notification_deliveries_user_recent_idx
  on public.notification_deliveries (user_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists push_devices_set_updated_at on public.push_devices;
create trigger push_devices_set_updated_at
before update on public.push_devices
for each row execute function public.set_updated_at();

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
before update on public.notification_preferences
for each row execute function public.set_updated_at();

alter table public.push_devices enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.job_activity_events enable row level security;
alter table public.notification_deliveries enable row level security;

drop policy if exists "Users can read their push devices" on public.push_devices;
create policy "Users can read their push devices"
on public.push_devices for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their push devices" on public.push_devices;
create policy "Users can insert their push devices"
on public.push_devices for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their push devices" on public.push_devices;
create policy "Users can update their push devices"
on public.push_devices for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their push devices" on public.push_devices;
create policy "Users can delete their push devices"
on public.push_devices for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Service role can manage push devices" on public.push_devices;
create policy "Service role can manage push devices"
on public.push_devices for all
to service_role
using (true)
with check (true);

drop policy if exists "Users can read notification preferences" on public.notification_preferences;
create policy "Users can read notification preferences"
on public.notification_preferences for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert notification preferences" on public.notification_preferences;
create policy "Users can insert notification preferences"
on public.notification_preferences for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update notification preferences" on public.notification_preferences;
create policy "Users can update notification preferences"
on public.notification_preferences for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Service role can manage notification preferences" on public.notification_preferences;
create policy "Service role can manage notification preferences"
on public.notification_preferences for all
to service_role
using (true)
with check (true);

drop policy if exists "Users can read their job activity" on public.job_activity_events;
create policy "Users can read their job activity"
on public.job_activity_events for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their job activity" on public.job_activity_events;
create policy "Users can insert their job activity"
on public.job_activity_events for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Service role can manage job activity" on public.job_activity_events;
create policy "Service role can manage job activity"
on public.job_activity_events for all
to service_role
using (true)
with check (true);

drop policy if exists "Users can read their notification deliveries" on public.notification_deliveries;
create policy "Users can read their notification deliveries"
on public.notification_deliveries for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Service role can manage notification deliveries" on public.notification_deliveries;
create policy "Service role can manage notification deliveries"
on public.notification_deliveries for all
to service_role
using (true)
with check (true);
