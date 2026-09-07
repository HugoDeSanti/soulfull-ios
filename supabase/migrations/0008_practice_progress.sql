-- 0008_practice_progress.sql
-- What every member has played, and how much of it — the record that content
-- creator payouts are calculated from.
--
-- ONE table (`practice_plays`, an append-mostly ledger) and TWO views over it:
-- `practice_progress` (per-member resume state, read by the app) and
-- `practice_creator_earnings` (per-creator totals, read by the back office).
-- A single source of truth means the payout numbers and the "Continue where you
-- left off" card can never disagree.
--
-- How to apply: Supabase dashboard → SQL Editor, or `supabase db push`.


-- ---------------------------------------------------------------------------
-- practice_plays — one row per playback/reading session
-- ---------------------------------------------------------------------------
--
-- The row is created when a practice is opened and updated as it is consumed,
-- addressed by the client-generated `client_event_id`. Re-opening the same
-- practice tomorrow makes a NEW row, so replays accumulate rather than
-- overwrite — which is what payouts need.
--
-- Creator/title/category are SNAPSHOTS taken at play time, deliberately
-- denormalised. If a session is later retitled or reassigned to a different
-- guide, historical payouts must not move with it.

create table if not exists public.practice_plays (
    id                uuid        primary key default gen_random_uuid(),

    -- NULLABLE, and `on delete set null` rather than `cascade`, on purpose.
    -- When a member deletes their account (App Store 5.1.1(v), see the
    -- `delete-account` Edge Function) the play must survive without them: the
    -- creator still earned that payout. The row becomes anonymous — no user id,
    -- and RLS then hides it from every client, leaving it visible only to the
    -- service role that runs payouts.
    user_id           uuid        references auth.users (id) on delete set null,

    -- Which library the practice came from. 'session' and 'massage' carry a
    -- real named creator; 'journal' / 'exercise' / 'recipe' are house content
    -- today and record a null creator, but are tracked so streaks are honest
    -- and so those libraries can be paid out later without a migration.
    content_kind      text        not null
                                  check (content_kind in ('session','massage','journal','exercise','recipe')),
    -- The id within that library (practice_sessions.id, Massage.id, …).
    content_id        bigint      not null,

    -- Snapshots (see above).
    content_title     text        not null,
    creator           text,
    category          text        check (category is null or category in ('somatic','breathwork','meditation')),

    -- Seconds actually consumed. Accumulated from playback ticks, NOT from the
    -- scrubber position, so seeking to the end doesn't bank the whole track.
    seconds_played    integer     not null default 0 check (seconds_played >= 0),
    -- Where to resume from. Position, not consumption.
    position_seconds  integer     not null default 0 check (position_seconds >= 0),
    -- Length of the practice at play time; bounds `seconds_played` (trigger below).
    duration_seconds  integer     check (duration_seconds is null or duration_seconds > 0),
    completed         boolean     not null default false,

    -- Idempotency key minted by the client for one playback session. Lets the
    -- app retry a heartbeat after a dropped connection without paying a creator
    -- twice for the same listen.
    client_event_id   uuid        not null,

    started_at        timestamptz not null default now(),
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),

    unique (user_id, client_event_id)
);

-- Payout runs scan by creator over a date range.
create index if not exists practice_plays_creator_idx
    on public.practice_plays (creator, created_at)
    where creator is not null;

-- The app reads its own recent activity (continue card, streak).
create index if not exists practice_plays_user_recent_idx
    on public.practice_plays (user_id, updated_at desc);

-- The progress view groups on this.
create index if not exists practice_plays_user_content_idx
    on public.practice_plays (user_id, content_kind, content_id);


-- ---------------------------------------------------------------------------
-- Integrity: the ledger is append-mostly, and monotonic
-- ---------------------------------------------------------------------------
--
-- The client has to be able to update its own in-flight row (that's how a
-- heartbeat works), but an updatable payout ledger is an invitation. This
-- trigger makes the only legal update "more of the same play":
--
--   • identity columns are frozen after insert — a row cannot be re-pointed at
--     another user, another practice, or another creator;
--   • `seconds_played` may only increase — no rewriting history downward;
--   • `seconds_played` is clamped to the practice's own length, so a modified
--     client cannot bill 10 hours against a 12-minute track. Replays legitimately
--     exceed the length, but they arrive as separate rows, so the cap holds.
--   • `completed` latches on.
--
-- This bounds client-side inflation; it does not eliminate it. A member can
-- still leave a track playing to the end without listening, exactly as with any
-- streaming service. If payouts ever need to be defensible against a determined
-- attacker rather than a buggy client, move the write behind an Edge Function
-- that also checks the Storage access log for the signed URL — see the note in
-- supabase/functions/README.md.

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

drop trigger if exists practice_plays_integrity on public.practice_plays;
create trigger practice_plays_integrity
    before insert or update on public.practice_plays
    for each row execute function public.enforce_practice_play_integrity();


-- ---------------------------------------------------------------------------
-- RLS — a member sees and writes only their own plays, and can never delete one
-- ---------------------------------------------------------------------------
--
-- No delete policy is defined, deliberately: deleting a play would erase a
-- creator's earnings. Account deletion is handled by the `on delete set null`
-- above, which anonymises the row instead of removing it.
--
-- `to authenticated` covers anonymous guests too — they carry role
-- `authenticated` with `is_anonymous: true` (the trap documented in
-- 0003_retreats_public_read.sql). In practice every practice is behind the
-- account gate, so these rows belong to permanent accounts.

alter table public.practice_plays enable row level security;

drop policy if exists "Members read their own plays" on public.practice_plays;
create policy "Members read their own plays"
    on public.practice_plays
    for select
    to authenticated
    using (auth.uid() = user_id);

drop policy if exists "Members record their own plays" on public.practice_plays;
create policy "Members record their own plays"
    on public.practice_plays
    for insert
    to authenticated
    with check (auth.uid() = user_id);

drop policy if exists "Members update their own in-flight plays" on public.practice_plays;
create policy "Members update their own in-flight plays"
    on public.practice_plays
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);


-- ---------------------------------------------------------------------------
-- practice_progress — what the app reads
-- ---------------------------------------------------------------------------
--
-- Per member, per practice: where to resume, whether it is finished, how much
-- has been consumed across every replay. Derived rather than stored so it can
-- never drift from the ledger the payouts use.
--
-- ⚠️ `security_invoker = on` is load-bearing. Without it the view executes as
-- its owner and RLS on `practice_plays` is bypassed — every member would read
-- every other member's history through it. This is the single most dangerous
-- line in the file; do not remove it.

create or replace view public.practice_progress
with (security_invoker = on) as
select
    p.user_id,
    p.content_kind,
    p.content_id,
    (array_agg(p.content_title    order by p.updated_at desc))[1] as content_title,
    (array_agg(p.creator          order by p.updated_at desc))[1] as creator,
    (array_agg(p.category         order by p.updated_at desc))[1] as category,
    -- Resume from the most recent play, not the furthest one: if they started
    -- it again this morning, this morning is where they are.
    (array_agg(p.position_seconds order by p.updated_at desc))[1] as position_seconds,
    max(p.duration_seconds)                                       as duration_seconds,
    sum(p.seconds_played)::bigint                                 as total_seconds_played,
    bool_or(p.completed)                                          as completed,
    count(*)::integer                                             as play_count,
    max(p.updated_at)                                             as last_played_at
from public.practice_plays p
where p.user_id is not null
group by p.user_id, p.content_kind, p.content_id;

grant select on public.practice_progress to authenticated;


-- ---------------------------------------------------------------------------
-- practice_creator_earnings — what the back office reads
-- ---------------------------------------------------------------------------
--
-- Consumption per creator per calendar month, the input to a payout run.
-- Includes plays whose member has since deleted their account (user_id null),
-- which is the whole reason for `on delete set null`.
--
-- ⚠️ `security_invoker = off` here (the default) — it must aggregate across ALL
-- members, so it deliberately runs with the owner's rights and bypasses RLS.
-- That makes the GRANTs below the only thing standing between this view and a
-- full history leak: it is revoked from `anon` and `authenticated`, leaving it
-- readable ONLY by the service role. Never grant this to a client role.

create or replace view public.practice_creator_earnings as
select
    p.creator,
    p.content_kind,
    date_trunc('month', p.created_at)          as month,
    count(*)::integer                          as plays,
    count(distinct p.user_id)::integer         as listeners,
    sum(p.seconds_played)::bigint              as seconds_played,
    round(sum(p.seconds_played) / 3600.0, 2)   as hours_played,
    count(*) filter (where p.completed)::integer as completions
from public.practice_plays p
where p.creator is not null
group by p.creator, p.content_kind, date_trunc('month', p.created_at);

revoke all on public.practice_creator_earnings from anon, authenticated;


-- ---------------------------------------------------------------------------
-- Notes for whoever runs the first payout
-- ---------------------------------------------------------------------------
--
--   -- Last month, per creator:
--   select creator, hours_played, completions
--     from public.practice_creator_earnings
--    where month = date_trunc('month', now() - interval '1 month')
--    order by hours_played desc;
--
-- `creator` is a name string snapshotted from practice_sessions.lead. That is
-- enough to total a payout but not to pay one — there is no creators table, no
-- payout rate and no Stripe Connect account behind it yet. When those land,
-- add a `creators` table and backfill a `creator_id` onto this ledger by name
-- BEFORE the names diverge.
--
-- Privacy: these rows record WHICH practice was opened and for how long. They
-- never contain journal reflection text — that stays on the device
-- (LocalUserStore). The privacy policy in website/legal/ describes practice
-- activity as collected data; keep §1 and §2 in step with this table.
