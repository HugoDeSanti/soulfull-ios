-- 0002_bookings.sql
-- Phase 2 (Retreat payments): one row per Stripe payment for a retreat.
--
-- Rows are written ONLY by the `stripe-webhook` Edge Function, which runs with
-- the service role and therefore bypasses RLS. The client can read its own
-- bookings but never writes payment state — amount and status are authoritative
-- from Stripe, never trusted from the app.
--
-- How to apply: Supabase dashboard → SQL Editor, or `supabase db push`.
-- Depends on 0001_profiles.sql (reuses its handle_profile_updated_at trigger fn).

create table if not exists public.bookings (
    id                       uuid        primary key default gen_random_uuid(),
    user_id                  uuid        not null references auth.users (id) on delete cascade,
    retreat_id               bigint      not null,                       -- matches retreats.id (no FK: retreats is seeded separately)
    amount_usd               integer     not null,
    currency                 text        not null default 'usd',
    status                   text        not null default 'pending',     -- pending | paid | failed | refunded
    stripe_payment_intent_id text        unique,                         -- dedupe key for webhook upserts
    created_at               timestamptz not null default now(),
    updated_at               timestamptz not null default now()
);

create index if not exists bookings_user_id_idx    on public.bookings (user_id);
create index if not exists bookings_retreat_id_idx  on public.bookings (retreat_id);

alter table public.bookings enable row level security;

-- Read-only for the owner. There are intentionally NO insert/update/delete
-- policies: the webhook writes with the service role (which bypasses RLS), and
-- the client must never be able to forge a booking.
create policy "Bookings are viewable by their owner"
    on public.bookings for select
    using (auth.uid() = user_id);

-- Reuse the generic updated_at bumper defined in 0001_profiles.sql.
drop trigger if exists bookings_set_updated_at on public.bookings;
create trigger bookings_set_updated_at
    before update on public.bookings
    for each row execute function public.handle_profile_updated_at();
