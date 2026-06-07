alter table public.notification_preferences
  add column if not exists timezone text not null default 'UTC';

create table if not exists public.sports_followed_teams (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sport_id text not null,
  sport_name text not null,
  team_name text not null,
  team_key text not null,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  unique (user_id, sport_id, team_key)
);

create index if not exists sports_followed_teams_user_sport_idx
  on public.sports_followed_teams (user_id, sport_id, team_key);

alter table public.sports_followed_teams enable row level security;

drop policy if exists "Users can read followed sports teams" on public.sports_followed_teams;
create policy "Users can read followed sports teams"
on public.sports_followed_teams for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert followed sports teams" on public.sports_followed_teams;
create policy "Users can insert followed sports teams"
on public.sports_followed_teams for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete followed sports teams" on public.sports_followed_teams;
create policy "Users can delete followed sports teams"
on public.sports_followed_teams for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Service role can manage followed sports teams" on public.sports_followed_teams;
create policy "Service role can manage followed sports teams"
on public.sports_followed_teams for all
to service_role
using (true)
with check (true);

do $$
begin
  perform cron.unschedule('briefly-job-alerts');
exception
  when others then null;
end $$;

do $$
begin
  perform cron.unschedule('briefly-notification-dispatcher');
exception
  when others then null;
end $$;

select cron.schedule(
  'briefly-notification-dispatcher',
  '*/15 * * * *',
  $$
    select net.http_post(
      url := replace(
        (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_url'),
        '/daily-feed',
        '/notification-dispatcher'
      ),
      body := jsonb_build_object(
        'dryRun', false,
        'limit', 100
      ),
      headers := jsonb_build_object(
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key'),
        'Content-Type', 'application/json'
      ),
      timeout_milliseconds := 25000
    );
  $$
);
