-- 0017_push_tokens.sql
-- Push notifications for likes: where to send them, and the hook that sends.
--
--   1. `device_tokens` — one row per APNs device token, owned by the member
--      signed in on that device. A token is a device, not a person: when
--      another member signs in on the same phone, the insert trigger hands
--      the token over to them, so a push never lands on a stranger.
--   2. An AFTER INSERT trigger on `notifications` posts the new row's id to
--      the `send-like-push` Edge Function through pg_net. The function's URL
--      and the shared secret it checks live in Vault, NOT in this file — they
--      are written at apply time (see the apply script / README). If either
--      is missing the trigger does nothing, so the in-app bell keeps working
--      with push simply off.
--
-- Push is a courtesy on top of the in-app notification, never the record:
-- `notifications` is written first and is what the app shows. A failed push
-- costs a buzz, not a like.

create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. Device tokens
-- ---------------------------------------------------------------------------

create table if not exists public.device_tokens (
    -- The APNs token as lowercase hex. Primary key: a device has one token.
    token       text        primary key,
    user_id     uuid        not null references auth.users (id) on delete cascade,
    -- Debug builds on a device register with APNs sandbox; TestFlight and the
    -- App Store use production. Sending to the wrong host is a BadDeviceToken.
    environment text        not null check (environment in ('sandbox', 'production')),
    updated_at  timestamptz not null default now()
);

create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

-- The device now belongs to whoever is registering it. Runs as owner, so it
-- can remove the previous member's row, which RLS would otherwise hide from
-- the new one — and would otherwise leave the previous member's likes
-- buzzing a phone they've signed out of.
create or replace function public.claim_device_token()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.device_tokens
     where token = new.token and user_id <> new.user_id;
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists device_tokens_claim on public.device_tokens;
create trigger device_tokens_claim
    before insert or update on public.device_tokens
    for each row execute function public.claim_device_token();

alter table public.device_tokens enable row level security;

drop policy if exists "Members read their own device tokens" on public.device_tokens;
create policy "Members read their own device tokens"
    on public.device_tokens for select to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Members register their own device" on public.device_tokens;
create policy "Members register their own device"
    on public.device_tokens for insert to authenticated
    with check (
        auth.uid() = user_id
        and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true
    );

drop policy if exists "Members refresh their own device" on public.device_tokens;
create policy "Members refresh their own device"
    on public.device_tokens for update to authenticated
    using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Members forget their own device" on public.device_tokens;
create policy "Members forget their own device"
    on public.device_tokens for delete to authenticated
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2. The hook
-- ---------------------------------------------------------------------------
--
-- Vault secrets (created at apply time, never in a migration):
--   push_function_url     https://<ref>.supabase.co/functions/v1/send-like-push
--   push_webhook_secret   a random string; the function refuses any call
--                         without it in `x-webhook-secret`
--
-- The function is deployed with --no-verify-jwt (pg_net carries no user JWT)
-- and the secret is the only thing standing between it and the internet,
-- which is why it is long, random, and in Vault.

create or replace function public.push_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    url    text;
    secret text;
    req    bigint;
begin
    select decrypted_secret into url    from vault.decrypted_secrets where name = 'push_function_url'   limit 1;
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'push_webhook_secret' limit 1;
    if url is null or secret is null then
        return new;   -- push not configured; the in-app bell still works
    end if;
    select net.http_post(
        url     := url,
        headers := jsonb_build_object('Content-Type', 'application/json',
                                      'x-webhook-secret', secret),
        body    := jsonb_build_object('notification_id', new.id),
        timeout_milliseconds := 5000
    ) into req;
    return new;
exception when others then
    -- Never let a push problem block the like that caused it.
    raise warning 'push_notification: %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
    after insert on public.notifications
    for each row execute function public.push_notification();

-- ---------------------------------------------------------------------------
-- Verification (one call each)
--
--   select extname from pg_extension where extname = 'pg_net';
--   select name from vault.decrypted_secrets where name like 'push_%';   -- 2 rows once configured
--   -- as a member: upsert a token → 201; as a guest → 42501
--   -- as a second member on the SAME token → the first member's row is gone
--   -- like a practice → select * from net._http_response order by created desc limit 1  (status 200 from the function)
-- ---------------------------------------------------------------------------
