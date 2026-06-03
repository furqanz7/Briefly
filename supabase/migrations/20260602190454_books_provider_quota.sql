create table if not exists public.books_provider_usage (
  provider_id text primary key,
  period text not null check (period in ('hour', 'day', 'month')),
  window_started_at timestamptz not null,
  window_ends_at timestamptz not null,
  auto_limit integer not null check (auto_limit >= 0),
  used_count integer not null default 0 check (used_count >= 0),
  blocked_until timestamptz,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);

create table if not exists public.books_provider_snapshots (
  provider_id text not null,
  scope text not null,
  payload jsonb not null,
  generated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (provider_id, scope)
);

alter table public.books_provider_usage enable row level security;
alter table public.books_provider_snapshots enable row level security;

drop policy if exists "Service role can manage books provider usage"
  on public.books_provider_usage;
create policy "Service role can manage books provider usage"
  on public.books_provider_usage
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

drop policy if exists "Service role can manage books provider snapshots"
  on public.books_provider_snapshots;
create policy "Service role can manage books provider snapshots"
  on public.books_provider_snapshots
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

create index if not exists books_provider_usage_window_ends_at_idx
  on public.books_provider_usage (window_ends_at);

create index if not exists books_provider_usage_blocked_until_idx
  on public.books_provider_usage (blocked_until);

create index if not exists books_provider_snapshots_expires_at_idx
  on public.books_provider_snapshots (expires_at);
