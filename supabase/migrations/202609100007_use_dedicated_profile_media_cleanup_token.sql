-- The Storage worker is invoked by pg_cron, not by a mobile client. Keep its
-- credential independent from Supabase API-key rotation. The token is stored
-- both in Vault and in the Edge Function's secret environment under the same
-- value, never in this migration.

do $$
declare
  existing_job_id bigint;
  cleanup_command text := $job$
    select net.http_post(
      url := config.project_url || '/functions/v1/cleanup-finalized-profile-media',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', config.scheduler_token
      ),
      body := '{}'::jsonb
    )
    from (
      select
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_project_url'
        ) as project_url,
        max(secret.decrypted_secret) filter (
          where secret.name = 'account_deletion_cleanup_scheduler_token'
        ) as scheduler_token
      from vault.decrypted_secrets secret
      where secret.name in (
        'account_deletion_cleanup_project_url',
        'account_deletion_cleanup_scheduler_token'
      )
    ) config
    where config.project_url is not null
      and config.scheduler_token is not null;
  $job$;
begin
  if to_regclass('cron.job') is not null then
    select jobid into existing_job_id
    from cron.job
    where jobname = 'cleanup-finalized-profile-media';

    if existing_job_id is null then
      perform cron.schedule(
        'cleanup-finalized-profile-media',
        '23 * * * *',
        cleanup_command
      );
    else
      perform cron.alter_job(
        existing_job_id,
        schedule => '23 * * * *',
        command => cleanup_command
      );
    end if;
  end if;
exception
  when insufficient_privilege then
    raise notice 'Skipping profile-media cleanup cron update; update it with database owner privileges';
end;
$$;
