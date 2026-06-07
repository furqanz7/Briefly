drop policy if exists "Service role can manage news feed snapshots"
  on public.news_feed_snapshots;
create policy "Service role can manage news feed snapshots"
  on public.news_feed_snapshots
  for all
  using ((select auth.role()) = 'service_role')
  with check ((select auth.role()) = 'service_role');
