create table if not exists public.news_feed_snapshots (
  scope text primary key,
  payload jsonb not null,
  generated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.news_feed_snapshots enable row level security;

drop policy if exists "Service role can manage news feed snapshots"
  on public.news_feed_snapshots;
create policy "Service role can manage news feed snapshots"
  on public.news_feed_snapshots
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

create index if not exists news_feed_snapshots_expires_at_idx
  on public.news_feed_snapshots (expires_at);
