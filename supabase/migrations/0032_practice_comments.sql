-- 0032_practice_comments.sql
-- Comments under a practice: members say how a movement sequence, a recipe or
-- a session went, and read what others said. Four parts:
--
--   1. `practice_comments` — one row per comment. A member writes their own
--      and deletes their own; nobody edits one (a comment that was reported
--      stays what was reported). Journal prompts take none: a reflection is
--      private, a prompt's title says what someone is working through (the
--      feed leaves prompts out for the same reason), and a public box beside
--      the private one invites writing the wrong thing in the wrong place.
--   2. What a comment may say, checked by the server at insert: the practice
--      exists, the text is 1–500 characters once trimmed, no links (spam is
--      the commonest abuse of a comment box, and a practice page has no use
--      for one), no slurs or hard profanity (`is_objectionable_comment()`, a
--      backstop like 0028's name filter — reports are the main defence), and
--      at most 20 comments an hour per member. `created_at` is the server's.
--   3. `practice_comment_thread` — the only way to read other members'
--      comments: members only (a guest can't open a practice anyway), each
--      author through `community_members`, so anyone either side has blocked
--      disappears from the thread both ways, and a comment from the practice's
--      own guide says so (`is_guide`).
--   4. Reports can name a comment: `member_reports.comment_id` and a snapshot
--      of its text, and a reason for it, 'offensive'. `report-member` v3
--      writes both (deploy it AFTER this migration).
--
-- Guideline 1.2: comments are user-generated content, so they get the same
-- four things the feed has — a filter (part 2), Report and Block on every
-- comment (the app's "⋯"), a 24-hour review (docs/MODERATION.md), and the
-- published contact address.
--
-- A deleted account takes its comments with it (on delete cascade). Unlike
-- practice plays, nothing is owed on a comment.
--
-- How to apply: Management API (one transaction with its schema_migrations
-- row) or `supabase db push`. Safe to re-run.
--
-- APPLIED to the live project 2026-10-12 through the Management API, in one
-- transaction with its schema_migrations row (0032), after a dry run inside an
-- aborted transaction that ran every check below as three test members and a
-- guest. The first dry run caught a newline-only comment going through
-- (`btrim` takes only spaces); the trim became the regexp below, and the
-- second dry run held everywhere: guest insert 42501; journal 23514; missing
-- practice 23503; blank, tabs-and-newlines and 501 characters 23514; https
-- and www → comment_link; "shit" → comment_objectionable; "Scunthorpe, and I
-- assess my breath" accepted, trimmed, created_at the server's; repeated id
-- 23505; update 42501; another member's delete 0 rows; the thread showed each
-- member both comments, is_mine on their own only, the table their own rows
-- only; a guest's thread 0 rows; anon 42501; after a block each saw only
-- their own and a third member both; the linked guide's comment is_guide,
-- a member's not; the 21st comment in an hour refused; a deleted comment's
-- report kept its text with comment_id null. After applying: RLS on with 3
-- policies, the trigger, the two report columns and the widened reason check
-- are in place; grants are authenticated DELETE/INSERT/SELECT on the table
-- and SELECT on the view, nothing for anon (a REST read with the anon key
-- answers 401 / 42501).
--
-- `report-member` v3 is NOT deployed yet: on 2026-10-12 every deploy failed
-- with Supabase's "Function deploy failed due to an internal error" (500),
-- the live v2's own code included, during a declared Edge Function incident.
-- Until v3 is live, a comment reported as "Hateful or offensive" is refused
-- (v2 doesn't know the reason) and the other reasons are filed against the
-- member without the comment.


-- ===========================================================================
-- 1. practice_comments
-- ===========================================================================

create table if not exists public.practice_comments (
    -- The app generates the id, so a post retried after a timeout that had in
    -- fact landed is a duplicate key, not a second comment.
    id           uuid        primary key default gen_random_uuid(),
    user_id      uuid        not null references auth.users (id) on delete cascade,
    content_kind text        not null check (content_kind in ('session', 'exercise', 'recipe')),
    content_id   bigint      not null,
    -- Counted in code points, as the app counts (`CommentDraft.maxLength`).
    -- Checked after the trigger has trimmed it.
    body         text        not null check (char_length(body) between 1 and 500),
    created_at   timestamptz not null default now()
);

comment on table public.practice_comments is
    'Members'' comments under a practice (not journal prompts). Read through practice_comment_thread; a member inserts and deletes their own.';

-- The thread: one practice's comments, newest first.
create index if not exists practice_comments_thread_idx
    on public.practice_comments (content_kind, content_id, created_at desc);
-- The trigger's hourly allowance.
create index if not exists practice_comments_member_recent_idx
    on public.practice_comments (user_id, created_at desc);

alter table public.practice_comments enable row level security;

-- Your own rows only. Everyone else's are read through the thread view, which
-- applies blocks; a direct read of this table would not.
drop policy if exists "Members read their own comments" on public.practice_comments;
create policy "Members read their own comments"
    on public.practice_comments
    for select
    to authenticated
    using (auth.uid() = user_id);

-- A member comments as themselves. A guest can't: a guest is disposable
-- (0023), and the app never shows them a practice page.
drop policy if exists "Members comment" on public.practice_comments;
create policy "Members comment"
    on public.practice_comments
    for insert
    to authenticated
    with check (auth.uid() = user_id and (select public.caller_has_account()));

drop policy if exists "Members delete their own comments" on public.practice_comments;
create policy "Members delete their own comments"
    on public.practice_comments
    for delete
    to authenticated
    using (auth.uid() = user_id);

-- No update policy and no update grant: a comment is posted or deleted.
revoke all on public.practice_comments from anon, authenticated, public;
grant select, insert, delete on public.practice_comments to authenticated;


-- ===========================================================================
-- 2. What a comment may say
-- ===========================================================================
--
-- Whole words, case-insensitive, like `is_objectionable_name()` (0028), so
-- "Scunthorpe" and "assess" pass. Shorter than the name list on purpose: no
-- team names ("loved this soulfull session" is a fine comment), and none of
-- the words a member may need to say about their own life on a wellness app —
-- "rape", "porn", "nazi" are in the name list and not here. Slurs and hard
-- profanity, English and Spanish. A false positive costs a rewrite; a false
-- negative is what Report is for.
create or replace function public.is_objectionable_comment(body text)
returns boolean
language sql
immutable
as $$
    select coalesce(
        lower(body) ~ (
            '\m('
            || 'fuck\w*|\w*fucker|shit|shits|shitty|bullshit|cunts?|twats?|wank\w*|'
            || 'whores?|sluts?|bitch\w*|bastards?|assholes?|motherf\w*|'
            || 'nigg(er|ers|a|as|az)|faggots?|fags?|retards?|retarded|kikes?|spics?|chinks?|kkk|'
            || 'puta|putas|puto|pendej\w*|cabr[oó]n\w*|mierda|maric[oó]n\w*|verga|coño'
            || ')\M'
        ),
        false)
$$;

-- SECURITY DEFINER so the existence check sees the catalog row whatever the
-- caller may read (a program-only session). The client's `created_at` is
-- ignored; refusals are P0001 with a message the app words
-- (`CommentRefusal`).
create or replace function public.enforce_practice_comment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    recent integer;
begin
    -- Whitespace of every kind off both ends, newlines included: `btrim`
    -- alone takes only spaces, and a dry run posted "\n" as a comment.
    new.body       := regexp_replace(new.body, '^[[:space:]]+|[[:space:]]+$', '', 'g');
    new.created_at := now();

    -- Any other kind fails the column's check, with its own message.
    if new.content_kind in ('session', 'exercise', 'recipe') and not (
        case new.content_kind
            when 'session' then
                exists (select 1 from public.practice_sessions s where s.id = new.content_id)
            when 'exercise' then
                exists (select 1 from public.exercises t where t.id = new.content_id and t.published)
            else
                exists (select 1 from public.recipes t where t.id = new.content_id and t.published)
        end
    ) then
        raise exception 'practice_comments: % % is not a practice', new.content_kind, new.content_id
            using errcode = '23503';
    end if;

    if new.body ~* '(https?://|www\.)' then
        raise exception 'comment_link'
            using errcode = 'P0001', hint = 'Comments can''t include links.';
    end if;

    if public.is_objectionable_comment(new.body) then
        raise exception 'comment_objectionable'
            using errcode = 'P0001', hint = 'Comments can''t include that kind of language.';
    end if;

    select count(*) into recent
      from public.practice_comments c
     where c.user_id = new.user_id
       and c.created_at > now() - interval '1 hour';
    if recent >= 20 then
        raise exception 'comment_rate_limit'
            using errcode = 'P0001', hint = 'At most 20 comments an hour.';
    end if;

    return new;
end;
$$;

revoke all on function public.enforce_practice_comment_integrity() from public, anon, authenticated;

drop trigger if exists practice_comments_integrity on public.practice_comments;
create trigger practice_comments_integrity
    before insert on public.practice_comments
    for each row execute function public.enforce_practice_comment_integrity();


-- ===========================================================================
-- 3. practice_comment_thread
-- ===========================================================================
--
-- Owner-rights, like `community_activity`: it reads every member's comments
-- past the table's own-rows RLS, and `auth.uid()` inside it is the caller's
-- (0016). The join to `community_members` is the block filter (0028) and the
-- name ("Hugo D.", or "A member" for an objectionable name). Members only:
-- for a guest the view answers nothing.
--
-- `is_guide`: the author is the guide this practice is credited to, through
-- `instructors.user_id` (0019), which no client may read; only the boolean
-- leaves the database.
create or replace view public.practice_comment_thread as
select
    c.id,
    c.user_id,
    m.display_name,
    m.avatar_url,
    c.content_kind,
    c.content_id,
    c.body,
    c.created_at,
    c.user_id = auth.uid() as is_mine,
    exists (
        select 1 from public.instructors i
        where i.user_id = c.user_id
          and i.id = case c.content_kind
              when 'session'  then (select s.instructor_id from public.practice_sessions s where s.id = c.content_id)
              when 'exercise' then (select t.instructor_id from public.exercises t where t.id = c.content_id)
              when 'recipe'   then (select t.instructor_id from public.recipes t where t.id = c.content_id)
          end
    ) as is_guide
from public.practice_comments c
join public.community_members m on m.id = c.user_id
where (select public.caller_has_account());

-- Supabase grants ALL on a new view to `authenticated`, and an owner-rights
-- view can be written through (0015): the revoke must name it.
revoke all on public.practice_comment_thread from anon, authenticated, public;
grant select on public.practice_comment_thread to authenticated;


-- ===========================================================================
-- 4. Reports can name a comment
-- ===========================================================================

alter table public.member_reports
    add column if not exists comment_id uuid references public.practice_comments (id) on delete set null,
    add column if not exists comment_body text;

comment on column public.member_reports.comment_id is
    'The comment reported, if any. Goes null when the comment is deleted; comment_body keeps what it said.';

-- 0028's inline check, widened by one reason. ('offensive' is for a comment;
-- the others still cover a member.)
alter table public.member_reports drop constraint if exists member_reports_reason_check;
alter table public.member_reports add constraint member_reports_reason_check
    check (reason in ('photo', 'name', 'harassment', 'spam', 'other', 'offensive'));


-- ---------------------------------------------------------------------------
-- Checks (run inside begin … rollback as members A and B, a guest G, and anon;
-- each on its own — the Management API returns only the last statement's rows)
-- ---------------------------------------------------------------------------
--
-- Writes:
--   G inserts a comment                                → 42501 (RLS)
--   A comments on journal 1                            → 23514 (content_kind check)
--   A comments on exercise 9999999                     → 23503
--   A comments '   ' / E'\t\n\r '                     → 23514 (empty once trimmed)
--   A comments 501 characters                          → 23514
--   A comments 'see https://x.io' / 'www.x.io'         → P0001 comment_link
--   A comments 'this is shit'                          → P0001 comment_objectionable
--   A comments 'Scunthorpe, and I assess my breath'    → accepted
--   A's insert with created_at '2026-01-01'            → created_at = now()
--   A's 21st comment within the hour                   → P0001 comment_rate_limit
--   A's insert repeating an existing id                → 23505 (the app treats it as posted)
--   A updates their comment                            → 42501 (no grant)
--   B deletes A's comment                              → 0 rows; A deletes it → 1 row
-- Reads:
--   anon selects practice_comment_thread               → 42501
--   G selects it                                       → 0 rows
--   A selects it                                       → A's and B's, is_mine on A's only
--   A selects practice_comments                        → A's rows only
--   A blocks B                                         → A no longer sees B's comments,
--                                                        B no longer sees A's; a third
--                                                        member still sees both
--   a comment by the account linked to the practice's guide → is_guide = true
-- Reports:
--   insert into member_reports with reason 'offensive' and a comment_id (as
--   the service role) → accepted; deleting the comment nulls comment_id
--
-- Grants:
--   select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type)
--     from information_schema.role_table_grants
--    where table_name in ('practice_comments', 'practice_comment_thread')
--      and grantee in ('anon', 'authenticated') group by 1, 2;
--   -- practice_comments: authenticated DELETE,INSERT,SELECT; the view: SELECT only
