alter table public.book_reading_minutes
add column if not exists seconds integer not null default 0;

update public.book_reading_minutes
set seconds = greatest(seconds, minutes * 60)
where seconds = 0 and minutes > 0;

create table if not exists public.user_reading_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  daily_goal_minutes integer not null default 30 check (daily_goal_minutes between 1 and 1440),
  updated_at timestamptz not null default now(),
  unique (user_id)
);

alter table public.user_reading_goals enable row level security;

drop policy if exists "Users can read their own reading goal" on public.user_reading_goals;
create policy "Users can read their own reading goal"
on public.user_reading_goals for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own reading goal" on public.user_reading_goals;
create policy "Users can insert their own reading goal"
on public.user_reading_goals for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own reading goal" on public.user_reading_goals;
create policy "Users can update their own reading goal"
on public.user_reading_goals for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own reading goal" on public.user_reading_goals;
create policy "Users can delete their own reading goal"
on public.user_reading_goals for delete
using (auth.uid() = user_id);
