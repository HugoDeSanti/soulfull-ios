-- Takes the placeholder practice media back out (run before App Review, or once
-- real sessions exist). Then delete the three objects in Storage →
-- practice-media: SQL can't (Supabase's protect_delete trigger).
--
-- A track with no rows left goes back to "SOON" by itself, within the app's
-- 5-minute catalog cache — no release needed.
--
-- Test plays of these sessions stay in practice_plays (there is deliberately
-- no delete path: it's the payout ledger). They carry creator =
-- 'Soulfull Studio', so leave that creator out of any payout.

delete from public.practice_sessions
where storage_path in (
    'somatic/placeholder-rise-and-soften.mp4',
    'breathwork/placeholder-four-in-six-out.m4a',
    'meditation/placeholder-arriving.m4a'
);
