# Briefly

Briefly is a SwiftUI iOS app for AI-powered summaries across news, live sports, job matches, books, and saved content. This repo uses direct REST integrations where practical so the app stays self-contained.

## Stack

- SwiftUI
- Supabase Auth + PostgREST via REST
- NewsData.io + mediastack + NewsAPI + GNews + The Guardian + New York Times + World News API for articles
- Groq or Gemini for `Ask Briefly`
- MVVM-style view models

## Setup

1. Open `/Users/Furqan/Desktop/Briefly/Briefly.xcodeproj` in Xcode.
2. Duplicate `/Users/Furqan/Desktop/Briefly/Briefly/Secrets.plist.example` as `Secrets.plist`.
3. Fill these values in `Secrets.plist`:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `NEWSDATA_API_KEY`
   - `MEDIASTACK_API_KEY`
   - `NEWSAPI_API_KEY`
   - `GNEWS_API_KEY`
   - `GUARDIAN_API_KEY`
   - `WORLDNEWS_API_KEY`
   - `NYT_API_KEY`
   - `NYT_API_SECRET`
   - `MASSIVE_REST_API_KEY`
   - `MASSIVE_ACCESS_KEY_ID`
   - `MASSIVE_SECRET_ACCESS_KEY`
   - `MASSIVE_S3_ENDPOINT`
   - `MASSIVE_BUCKET`
   - `AI_PROVIDER`
   - `AI_BASE_URL`
   - `AI_MODEL`
   - `AI_API_KEY`
4. Build and run the `Briefly` scheme on iPhone simulator or device.

If `Secrets.plist` is missing, the app still boots with mock article data so the UI is reviewable.

## Environment Keys

`Secrets.plist` requires:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `NEWSDATA_API_KEY`
- `MEDIASTACK_API_KEY`
- `NEWSAPI_API_KEY`
- `GNEWS_API_KEY`
- `GUARDIAN_API_KEY`
- `WORLDNEWS_API_KEY`
- `NYT_API_KEY`
- `NYT_API_SECRET`
- `MASSIVE_REST_API_KEY`
- `MASSIVE_ACCESS_KEY_ID`
- `MASSIVE_SECRET_ACCESS_KEY`
- `MASSIVE_S3_ENDPOINT`
- `MASSIVE_BUCKET`
- `AI_PROVIDER`
- `AI_BASE_URL`
- `AI_MODEL`
- `AI_API_KEY`

## Supabase

Enable email/password auth and create this table:

```sql
create table if not exists public.saved_articles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  article_id text not null,
  headline text not null,
  source text not null,
  image_url text,
  original_url text,
  plain_summary text not null,
  raw_description text not null,
  raw_content text not null,
  category text not null,
  summary_cards text[] not null,
  created_at timestamptz not null default now(),
  unique (user_id, article_id)
);

alter table public.saved_articles enable row level security;

create policy "Users can read their own saved articles"
on public.saved_articles for select
using (auth.uid() = user_id);

create policy "Users can insert their own saved articles"
on public.saved_articles for insert
with check (auth.uid() = user_id);

create policy "Users can delete their own saved articles"
on public.saved_articles for delete
using (auth.uid() = user_id);
```

Recommended auth settings:

- Enable email/password sign-in
- Disable email confirmation for assignment/demo flow
- Enable Apple provider if you want Apple Sign In active in the running app

The SQL above is also included in:

- `/Users/Furqan/Desktop/Briefly/supabase/migrations/20260402195000_saved_articles.sql`

### Account deletion function

The app includes an in-app account deletion flow in Profile. Deploy the Supabase Edge Function in:

- `/Users/Furqan/Desktop/Briefly/supabase/functions/delete-account/index.ts`

Required function secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Example deployment:

```bash
supabase functions deploy delete-account
supabase functions deploy market-data
supabase secrets set SUPABASE_URL=https://your-project.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
supabase secrets set FINNHUB_API_KEY=your-finnhub-api-key
supabase secrets set TWELVEDATA_API_KEY=your-twelvedata-api-key
supabase secrets set ALPHAVANTAGE_API_KEY=your-alphavantage-api-key
```

## AI Provider Notes

- Default config is Groq using its OpenAI-compatible endpoint.
- Gemini also works by setting `AI_PROVIDER=gemini` and pointing `AI_BASE_URL` to `https://generativelanguage.googleapis.com/v1beta`.
- Ask Briefly now shows an in-app AI privacy sheet before first use and keeps that information accessible from the chat screen.

## News Source Notes

- `NEWSDATA_API_KEY`, `MEDIASTACK_API_KEY`, `NEWSAPI_API_KEY`, `GNEWS_API_KEY`, `GUARDIAN_API_KEY`, `WORLDNEWS_API_KEY`, and `NYT_API_KEY` are aggregated together for broader same-day coverage.
- The Home screen now includes a separate `Market` section.
- The Market section calls the Supabase `market-data` Edge Function only. Provider keys such as `FINNHUB_API_KEY`, `TWELVEDATA_API_KEY`, and `ALPHAVANTAGE_API_KEY` belong in Supabase secrets, not `Secrets.plist`.
- `market-data` caches snapshots, tracks provider usage in Postgres, applies provider-specific quota limits, and returns cached or stale data when live provider calls are paused.
- The Books tab calls the Supabase `books-data` Edge Function only. Book provider keys such as `AMAZON_BOOKS_RAPIDAPI_KEY`, `REALTIME_BOOKS_RAPIDAPI_KEY`, `HAPI_BOOKS_RAPIDAPI_KEY`, `ANNAS_ARCHIVE_RAPIDAPI_KEY`, `SUPERHERO_BOOKS_RAPIDAPI_KEY`, or a shared `RAPIDAPI_KEY` belong in Supabase secrets, not `Secrets.plist`.
- `books-data` aggregates Google Books, Open Library, Gutendex, Amazon Books, Realtime Books, HAPI Books, Anna's Archive search metadata, and Superhero Search, with provider snapshots and quota guards when the Supabase service role secret is configured.
- `MASSIVE_REST_API_KEY` is optional and no longer the active market source.
- `MASSIVE_ACCESS_KEY_ID`, `MASSIVE_SECRET_ACCESS_KEY`, `MASSIVE_S3_ENDPOINT`, and `MASSIVE_BUCKET` are flat-file/storage credentials and are not treated as article-news credentials.

## Assignment Notes

- Authentication persists through Keychain.
- Home includes featured carousel, search, and saved sync.
- Article detail includes 3 swipeable summary cards, in-app original article viewer, and contextual chat.
- Saved and Profile tabs are included.
- Apple Sign In is included.
