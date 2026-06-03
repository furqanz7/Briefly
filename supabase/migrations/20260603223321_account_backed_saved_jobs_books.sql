create extension if not exists pgcrypto;

create table if not exists public.saved_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id text not null,
  title text not null,
  company text not null,
  location text not null,
  work_mode text not null,
  salary text not null,
  match_score integer not null,
  posted_at text not null,
  company_summary text not null,
  role_summary text not null,
  skills text[] not null default '{}',
  perks text[] not null default '{}',
  requirements text[] not null default '{}',
  apply_url text,
  created_at timestamptz not null default now(),
  unique (user_id, job_id)
);

create table if not exists public.applied_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id text not null,
  title text not null,
  company text not null,
  location text not null,
  work_mode text not null,
  salary text not null,
  match_score integer not null,
  posted_at text not null,
  company_summary text not null,
  role_summary text not null,
  skills text[] not null default '{}',
  perks text[] not null default '{}',
  requirements text[] not null default '{}',
  apply_url text,
  created_at timestamptz not null default now(),
  unique (user_id, job_id)
);

create table if not exists public.saved_books (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id text not null,
  title text not null,
  authors text[] not null default '{}',
  genre text not null,
  description text not null,
  cover_url text,
  rating double precision,
  page_count integer,
  published_year text not null,
  publisher text not null,
  source text not null,
  availability text not null,
  preview_url text,
  download_url text,
  is_saved boolean not null default false,
  is_downloaded boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, book_id)
);

create table if not exists public.book_reading_minutes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reading_date date not null,
  minutes integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, reading_date)
);

alter table public.saved_jobs enable row level security;
alter table public.applied_jobs enable row level security;
alter table public.saved_books enable row level security;
alter table public.book_reading_minutes enable row level security;

drop policy if exists "Users can read their own saved jobs" on public.saved_jobs;
create policy "Users can read their own saved jobs"
on public.saved_jobs for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own saved jobs" on public.saved_jobs;
create policy "Users can insert their own saved jobs"
on public.saved_jobs for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own saved jobs" on public.saved_jobs;
create policy "Users can update their own saved jobs"
on public.saved_jobs for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own saved jobs" on public.saved_jobs;
create policy "Users can delete their own saved jobs"
on public.saved_jobs for delete
using (auth.uid() = user_id);

drop policy if exists "Users can read their own applied jobs" on public.applied_jobs;
create policy "Users can read their own applied jobs"
on public.applied_jobs for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own applied jobs" on public.applied_jobs;
create policy "Users can insert their own applied jobs"
on public.applied_jobs for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own applied jobs" on public.applied_jobs;
create policy "Users can update their own applied jobs"
on public.applied_jobs for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own applied jobs" on public.applied_jobs;
create policy "Users can delete their own applied jobs"
on public.applied_jobs for delete
using (auth.uid() = user_id);

drop policy if exists "Users can read their own saved books" on public.saved_books;
create policy "Users can read their own saved books"
on public.saved_books for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own saved books" on public.saved_books;
create policy "Users can insert their own saved books"
on public.saved_books for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own saved books" on public.saved_books;
create policy "Users can update their own saved books"
on public.saved_books for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own saved books" on public.saved_books;
create policy "Users can delete their own saved books"
on public.saved_books for delete
using (auth.uid() = user_id);

drop policy if exists "Users can read their own reading minutes" on public.book_reading_minutes;
create policy "Users can read their own reading minutes"
on public.book_reading_minutes for select
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own reading minutes" on public.book_reading_minutes;
create policy "Users can insert their own reading minutes"
on public.book_reading_minutes for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own reading minutes" on public.book_reading_minutes;
create policy "Users can update their own reading minutes"
on public.book_reading_minutes for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own reading minutes" on public.book_reading_minutes;
create policy "Users can delete their own reading minutes"
on public.book_reading_minutes for delete
using (auth.uid() = user_id);
