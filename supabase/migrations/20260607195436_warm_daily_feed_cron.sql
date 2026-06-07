create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;

do $$
begin
  perform cron.unschedule('briefly-daily-feed-warmer');
exception
  when others then null;
end $$;

select cron.schedule(
  'briefly-daily-feed-warmer',
  '*/5 * * * *',
  $$
    select net.http_get(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_url'),
      params := jsonb_build_object(
        'count', '48',
        'ttl', '600',
        'lang', 'en',
        'country', 'in',
        'warm', '1'
      ),
      headers := jsonb_build_object(
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key'),
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'briefly_daily_feed_anon_key')
      ),
      timeout_milliseconds := 10000
    );
  $$
);
