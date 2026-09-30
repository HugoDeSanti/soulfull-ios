-- Placeholder practice media, so testers can use the three media tracks
-- (Somatic / Breathwork / Meditation) before the real sessions are recorded.
--
-- ⚠️ REMOVE BEFORE APP REVIEW (Guideline 2.1(a): placeholder content) —
--    run remove.sql and delete the three objects. See README.md.
--
-- Upload first, to the private `practice-media` bucket, at exactly these paths:
--     somatic/placeholder-rise-and-soften.mp4
--     breathwork/placeholder-four-in-six-out.m4a
--     meditation/placeholder-arriving.m4a
--
-- Then run this in the SQL editor. Safe to re-run: a row whose storage_path is
-- already there is skipped.
--
-- Deliberately credited to a house name, not a person, and linked to no
-- instructor: plays still land in practice_plays (the payout ledger) with
-- creator = 'Soulfull Studio', which is how to leave them out of a payout.
-- `duration_seconds` is each file's exact length — the server caps
-- seconds_played at it, and the audio scrubber draws against it.

insert into public.practice_sessions
    (category, title, lead, media_kind, storage_path, duration_seconds, image_url, blurb)
select v.category, v.title, v.lead, v.media_kind, v.storage_path, v.duration_seconds, v.image_url, v.blurb
from (values
    ('somatic', 'Rise & Soften', 'Soulfull Studio', 'video',
     'somatic/placeholder-rise-and-soften.mp4', 60, 'practice-somatic',
     'A one-minute standing sequence: reach with the breath, sway, shake out, settle. A placeholder while the real sessions are recorded.'),
    ('breathwork', 'Four In, Six Out', 'Soulfull Studio', 'audio',
     'breathwork/placeholder-four-in-six-out.m4a', 30, 'practice-breathwork',
     'Thirty seconds of slow breathing: in for four, out for six. A placeholder while the real sessions are recorded.'),
    ('meditation', 'Arriving', 'Soulfull Studio', 'audio',
     'meditation/placeholder-arriving.m4a', 128, 'practice-meditation',
     'Two quiet minutes to land where you are, with a few gentle cues. A placeholder while the real sessions are recorded.')
) as v(category, title, lead, media_kind, storage_path, duration_seconds, image_url, blurb)
where not exists (
    select 1 from public.practice_sessions s where s.storage_path = v.storage_path
);

select id, category, title, media_kind, storage_path, duration_seconds, program_only
from public.practice_sessions
where storage_path like '%/placeholder-%'
order by id;
