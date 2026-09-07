-- 0009_integrity_hardening.sql
-- Closes six integrity gaps found in the 2026-09-07 security audit. Every one
-- of them is a case where the SERVER was documented as authoritative and
-- wasn't — the client, or an out-of-order webhook, could still move the value.
--
--   1. practice_plays: the payout clamp was bypassable (duration_seconds and the
--      title/category snapshots were left unfrozen by the integrity trigger).
--   2. bookings: `paid` could be downgraded to `failed` by a replayed or
--      out-of-order Stripe event.
--   3. bookings: money was stored as whole dollars, discarding cents.
--   4. bookings: account deletion cascaded a paid reservation out of existence.
--   5. profiles: the client could write its own `email`, which
--      create-payment-intent then used to address the Stripe customer.
--   6. practice_plays: the idempotency constraint evaporated for anonymised rows.
--
-- How to apply: Supabase dashboard → SQL Editor, or `supabase db push`.
-- Safe to re-run. Depends on 0001, 0002 and 0008.


-- ===========================================================================
-- 1. practice_plays — freeze every column the payout clamp depends on
-- ===========================================================================
--
-- 0008's trigger froze the identity columns but NOT `duration_seconds`, and the
-- clamp it applies is `least(new.seconds_played, new.duration_seconds)` — using
-- the value the client supplied in the SAME update. `recordPracticePlay` sends
-- duration on every heartbeat, so a modified client could send
-- `duration_seconds: 999999, seconds_played: 999999` and bill the full amount
-- against a 12-minute track. The clamp was only ever as strong as its bound.
--
-- `content_title` and `category` were unfrozen too, so the labels on a payout
-- report could be rewritten after the fact — the same reason `creator` is
-- frozen applies to them.

create or replace function public.enforce_practice_play_integrity()
returns trigger
language plpgsql
as $$
begin
    if tg_op = 'UPDATE' then
        -- Frozen identity.
        new.id              := old.id;
        -- `user_id` is frozen ONLY against being re-pointed at another member.
        -- A NULL must be allowed through, because that is how the foreign key's
        -- ON DELETE SET NULL anonymises this row when the member deletes their
        -- account — a referential action is an UPDATE, and an unconditional
        -- freeze here silently reverts it, leaving the deleted member's id
        -- attached to their history forever (and the FK itself violated).
        -- A client cannot exploit the gap: RLS's `with check (auth.uid() =
        -- user_id)` is evaluated after this trigger, and `auth.uid() = NULL`
        -- is NULL, not true, so a self-anonymising update is rejected.
        if new.user_id is not null then
            new.user_id     := old.user_id;
        end if;
        new.content_kind    := old.content_kind;
        new.content_id      := old.content_id;
        new.creator         := old.creator;
        new.client_event_id := old.client_event_id;
        new.started_at      := old.started_at;
        new.created_at      := old.created_at;

        -- Frozen snapshots. These are what a payout report is LABELLED with;
        -- letting an update rewrite them moves history just as re-pointing
        -- `creator` would.
        new.content_title   := old.content_title;
        new.category        := old.category;

        -- Frozen bound. `duration_seconds` is the practice's length at play
        -- time, and it is the ONLY thing standing between a client and an
        -- unbounded `seconds_played` — see the clamp below. Once set it cannot
        -- be raised; coalesce lets a later heartbeat fill in a length the
        -- first one didn't know (the written libraries start out null).
        new.duration_seconds := coalesce(old.duration_seconds, new.duration_seconds);

        -- Monotonic consumption, latching completion.
        new.seconds_played  := greatest(new.seconds_played, old.seconds_played);
        new.completed       := new.completed or old.completed;
    end if;

    -- Never bill more than the practice is long.
    if new.duration_seconds is not null then
        new.seconds_played   := least(new.seconds_played,   new.duration_seconds);
        new.position_seconds := least(new.position_seconds, new.duration_seconds);
    end if;

    new.updated_at := now();
    return new;
end;
$$;

-- (The trigger itself is unchanged from 0008; only the function body moved.)


-- ===========================================================================
-- 2. practice_plays — the idempotency key must survive anonymisation
-- ===========================================================================
--
-- Postgres treats NULLs as distinct in a unique constraint by default, so
-- `unique (user_id, client_event_id)` stopped constraining anything the moment
-- `user_id` became null. Harmless today (nothing writes after deletion), but it
-- is the constraint the whole "a retried heartbeat can't pay twice" argument
-- rests on, and it should not quietly weaken.

do $$
begin
    if exists (
        select 1 from pg_constraint
         where conrelid = 'public.practice_plays'::regclass
           and conname  = 'practice_plays_user_id_client_event_id_key'
    ) then
        alter table public.practice_plays
            drop constraint practice_plays_user_id_client_event_id_key;
    end if;
end $$;

alter table public.practice_plays
    add constraint practice_plays_user_event_key
    unique nulls not distinct (user_id, client_event_id);


-- ===========================================================================
-- 3. bookings — money in cents, not whole dollars
-- ===========================================================================
--
-- `amount_usd integer` with the webhook's `Math.round(pi.amount_received / 100)`
-- silently discarded cents. Stripe's native unit is the minor unit; store that
-- and format at the edge.

do $$
begin
    if exists (
        select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'bookings'
           and column_name = 'amount_usd'
    ) then
        alter table public.bookings rename column amount_usd to amount_cents;
        update public.bookings set amount_cents = amount_cents * 100;
    end if;
end $$;


-- ===========================================================================
-- 4. bookings — a paid reservation survives the member who made it
-- ===========================================================================
--
-- `on delete cascade` erased every booking when an account was deleted, taking
-- the attendee roster for a retreat someone had actually paid to attend. The
-- play ledger already made the opposite (correct) choice for exactly this
-- reason; bookings have more money attached, not less. RLS (`auth.uid() =
-- user_id`) hides the orphaned row from every client automatically, because
-- `auth.uid() = NULL` is NULL rather than true.

alter table public.bookings drop constraint if exists bookings_user_id_fkey;
alter table public.bookings alter column user_id drop not null;
alter table public.bookings
    add constraint bookings_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete set null;


-- ===========================================================================
-- 5. bookings — `paid` is terminal against webhook replay and reordering
-- ===========================================================================
--
-- The webhook upserts on `stripe_payment_intent_id` and overwrites `status`
-- unconditionally. Stripe does not guarantee event ordering, and one
-- PaymentIntent legitimately emits `payment_failed` (a declined first attempt)
-- before `succeeded`. A late or redelivered `payment_failed` therefore revoked
-- an entitlement the customer had paid for — and took the `already_booked`
-- guard in create-payment-intent down with it, opening a second charge.
--
-- A refund is a deliberate back-office action and is still allowed through.

create or replace function public.enforce_booking_status()
returns trigger
language plpgsql
as $$
begin
    if old.status = 'paid' and new.status in ('pending', 'failed') then
        new.status := old.status;
    end if;
    return new;
end;
$$;

drop trigger if exists bookings_status_latch on public.bookings;
create trigger bookings_status_latch
    before update on public.bookings
    for each row execute function public.enforce_booking_status();


-- ===========================================================================
-- 6. profiles — `email` and `stripe_customer_id` are server-owned
-- ===========================================================================
--
-- RLS only ever asserted `auth.uid() = id`; every other column was client
-- writable. `upsertProfile` sent `email`, and create-payment-intent preferred
-- `profile.email` over the verified `user.email` when creating the Stripe
-- customer — so a member could point their Stripe record, and its receipts, at
-- an address they don't own.
--
-- Column-level REVOKE is the obvious tool and the wrong one here: PostgREST
-- sends every column in an upsert, so revoking UPDATE(email) fails the whole
-- request rather than ignoring the field. A BEFORE trigger reverts it quietly
-- instead, which keeps the existing client working unchanged.
--
-- Scoped to the client roles. `handle_new_user` is SECURITY DEFINER, so inside
-- it `current_user` is the function owner and the guard correctly skips; the
-- Edge Functions use the service role and are likewise unaffected.

create or replace function public.protect_profile_server_columns()
returns trigger
language plpgsql
as $$
begin
    if current_user in ('anon', 'authenticated') then
        if tg_op = 'INSERT' then
            new.email              := (select u.email from auth.users u where u.id = new.id);
            new.stripe_customer_id := null;
        else
            new.email              := old.email;
            new.stripe_customer_id := old.stripe_customer_id;
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists profiles_protect_server_columns on public.profiles;
create trigger profiles_protect_server_columns
    before insert or update on public.profiles
    for each row execute function public.protect_profile_server_columns();


-- ---------------------------------------------------------------------------
-- …which means the server now has to keep `profiles.email` current itself.
-- ---------------------------------------------------------------------------
--
-- Before this migration the column was populated by the client's upsert. With
-- that path closed, mirror `auth.users.email` instead — which is the verified
-- address, and the one that should have been authoritative all along. This is
-- what carries an anonymous guest's upgrade (auth.update sets the email on
-- auth.users) through to their profile row.

create or replace function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.profiles
       set email = new.email
     where id = new.id
       and email is distinct from new.email;
    return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
    after update of email on auth.users
    for each row execute function public.sync_profile_email();

-- Backfill any row whose email drifted while the client owned the column.
update public.profiles p
   set email = u.email
  from auth.users u
 where u.id = p.id
   and p.email is distinct from u.email;


-- ===========================================================================
-- Verification — run these after applying. Each should fail closed.
-- ===========================================================================
--
-- 1. The clamp can no longer be lifted (as an authenticated member, via the API):
--      insert a play with duration_seconds = 600, then
--      patch it with { duration_seconds: 999999, seconds_played: 999999 }
--      → expect duration_seconds 600 and seconds_played 600, not 999999.
--
-- 2. Snapshots are frozen:
--      patch a play with { content_title: 'x', category: 'meditation' }
--      → expect the original values.
--
-- 3. `paid` is terminal:
--      update bookings set status = 'failed' where status = 'paid'
--      → expect the row to remain 'paid'. Then set it to 'refunded'
--      → expect that to succeed.
--
-- 4. Server-owned profile columns:
--      as a member, patch profiles with { email: 'attacker@example.com' }
--      → expect the row to keep the address from auth.users.
--
-- 5. Deletion anonymises rather than erases:
--      delete a test auth user that has a paid booking
--      → expect the bookings row to survive with user_id null, and to be
--        invisible to every client role.
