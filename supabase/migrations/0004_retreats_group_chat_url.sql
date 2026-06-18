-- 0004_retreats_group_chat_url.sql
-- Per-retreat external group-chat link (e.g. a WhatsApp cohort invite),
-- surfaced in the post-purchase experience hub. Nullable: no link → no tile.
-- Lives in the DB (not app code) so adding a retreat's chat link is a data
-- change, not an app release. Inherits the existing retreats SELECT policies
-- from 0003 (anon + authenticated); no RLS change needed for an added column.

alter table public.retreats
  add column if not exists group_chat_url text;
