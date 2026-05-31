-- 0001_profiles.sql
-- Phase 1 (Accounts): one profile row per auth user — anonymous or permanent.
--
-- A profile is created automatically by a trigger whenever an auth user is
-- created (including the anonymous guest session the app opens on launch), and
-- is owned by that user through row-level security so each person can only
-- read and write their own row.
--
-- How to apply:
--   • Supabase dashboard → SQL Editor → paste & run, OR
--   • Supabase CLI → `supabase db push` (with this file under supabase/migrations).
--
-- Auth setup that pairs with this migration (dashboard → Authentication):
--   • Providers → Email: enabled.
--   • During development, turn OFF "Confirm email" so the anonymous→permanent
--     upgrade (auth.update with a new email) completes immediately. To keep it
--     on, you must also handle the email-confirmation redirect in-app.
--   • Anonymous sign-ins: already enabled (the app relies on them).

create table if not exists public.profiles (
    id                 uuid        primary key references auth.users (id) on delete cascade,
    email              text,
    full_name          text,
    intentions         text[]      not null default '{}',
    body_state         text,
    frequency          text,
    stripe_customer_id text,                                   -- reserved for Phase 2 (Stripe); written server-side only
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now()
);

-- Row-level security: a user may only ever touch their own profile.
alter table public.profiles enable row level security;

create policy "Profiles are viewable by their owner"
    on public.profiles for select
    using (auth.uid() = id);

create policy "Users can insert their own profile"
    on public.profiles for insert
    with check (auth.uid() = id);

create policy "Users can update their own profile"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- Note: there is intentionally no DELETE policy and no policy granting access to
-- stripe_customer_id writes from the client — that column is managed by the
-- Phase 2 Stripe webhook running with the service role (which bypasses RLS).

-- Keep updated_at fresh on every write.
create or replace function public.handle_profile_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.handle_profile_updated_at();

-- Auto-create a profile whenever an auth user is created. Seeds full_name/email
-- from sign-up metadata when present. SECURITY DEFINER so it runs with the
-- privileges needed to insert into public.profiles from the auth context.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, full_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'full_name', '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
