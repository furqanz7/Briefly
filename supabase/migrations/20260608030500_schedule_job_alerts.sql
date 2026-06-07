create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

do $$
begin
  perform cron.unschedule('briefly-job-alerts');
exception
  when others then null;
end $$;

select cron.schedule(
  'briefly-job-alerts',
  '*/30 * * * *',
  $$
    select net.http_post(
      url := replace(
        (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_url'),
        '/daily-feed',
        '/job-alerts'
      ),
      body := jsonb_build_object(
        'dryRun', false,
        'limit', 50
      ),
      headers := jsonb_build_object(
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key'),
        'Content-Type', 'application/json'
      ),
      timeout_milliseconds := 20000
    );
  $$
);
