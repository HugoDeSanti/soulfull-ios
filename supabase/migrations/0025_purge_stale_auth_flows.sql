-- 0025_purge_stale_auth_flows.sql
-- Leftover email-confirmation flows, deleted nightly beside idle guests (0023).
--
-- Every confirmation email the app triggers is a PKCE flow: the guest upgrade
-- (`auth.update`, "email_change") and a plain sign-up each write a row to
-- auth.flow_state holding the code challenge whose verifier sits in the
-- phone's Keychain. GoTrue removes the row when the deep link's code is
-- exchanged on that phone, and nothing removes it otherwise, so a confirmation
-- finished by the emailed code, on another device, or never, stays forever.
-- flow_state has no foreign key to auth.users, so deleting an account leaves
-- its rows behind as well. On 2026-09-30 there were 7, all email_change, from
-- June to September: 5 for accounts that no longer exist, and 2 from the day
-- each live member confirmed (neither had a code issued, so both confirmed
-- some other way than the deep link).
--
-- A row is dead once its link can't be used. Supabase caps an email link's
-- lifetime at 24 hours, so anything older than 7 days is dead with room to
-- spare, whatever the flow. The only table that references flow_state is
-- saml_relay_states, which this project doesn't use.
--
-- Its own function and job rather than a second statement in
-- `purge_idle_guests`: each job's runs show up separately in
-- cron.job_run_details, and the guest purge keeps doing what its name says.
--
-- APPLIED 2026-09-30 through the Management API and recorded in
-- supabase_migrations.schema_migrations (0025), after a dry run inside an
-- aborted transaction. Verified live: both jobs are scheduled and active,
-- neither client role can execute the function, and the first run (03:27 UTC)
-- would take all 7 rows.

create or replace function public.purge_stale_auth_flows(older_than interval default interval '7 days')
returns integer
language plpgsql
set search_path = ''
as $$
declare
    purged integer;
begin
    delete from auth.flow_state
     where created_at < now() - older_than;
    get diagnostics purged = row_count;
    return purged;
end;
$$;

-- Server-only, like the guest purge.
revoke all on function public.purge_stale_auth_flows(interval) from public, anon, authenticated;

select cron.schedule(
    'purge-stale-auth-flows',
    '27 3 * * *',
    $$select public.purge_stale_auth_flows()$$
);

-- ---------------------------------------------------------------------------
-- Verification (each on its own)
-- ---------------------------------------------------------------------------
--
--   select jobname, schedule, command, active from cron.job order by jobname;
--   select j.jobname, d.status, d.return_message, d.start_time
--     from cron.job_run_details d join cron.job j using (jobid)
--    order by d.start_time desc limit 10;
--   -- What the next run would take (dry):
--   select count(*) from auth.flow_state where created_at < now() - interval '7 days';
