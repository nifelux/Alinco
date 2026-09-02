-- Supabase pg_cron uses UTC. 23:00 UTC is 00:00 in Nigeria (Africa/Lagos, UTC+1).
create extension if not exists pg_cron;

select cron.unschedule(jobid)
from cron.job
where jobname = 'alinco-daily-income';

select cron.schedule(
  'alinco-daily-income',
  '0 23 * * *',
  $$select public.collect_due_package_income((now() at time zone 'Africa/Lagos')::date);$$
);
