# Placeholder practice media

Three generated sessions that light up the Practice tab's media tracks for
TestFlight testers while the real content is recorded. Seeding
`practice_sessions` is what removes the "SOON" badges; the app needs no
release, either way.

| Track | Title | File (in `practice-media`) | Length |
|---|---|---|---|
| Somatic | Rise & Soften | `somatic/placeholder-rise-and-soften.mp4`: 720×1280 H.264 + AAC, ~11 MB | 60s |
| Breathwork | Four In, Six Out | `breathwork/placeholder-four-in-six-out.m4a` | 30s |
| Meditation | Arriving | `meditation/placeholder-arriving.m4a` | 2:08 |

⚠️ **Remove before App Review.** Placeholder content is a Guideline 2.1(a)
rejection. Run `remove.sql`, then delete the three objects in Storage.

## What they are

Everything is made on the Mac, with no stock footage, licensed faces or AI
image service involved:
- **Voice:** macOS `say` (Samantha), placed at fixed times with a short room reverb.
- **Sound:** a synthesized drone pad, a struck singing bowl, and (for the breathwork) a noise swell that rises on each inhale and falls on each exhale.
- **Video:** a faceless flat-illustration figure in the Theme palette, rendered frame by frame with Core Graphics. She does four parts: reach with the breath, side sway, knee-bounce shake-out, and a hand on the heart and belly. Geist captions sit in the lower third, clear of the player's title bar.

`seed.sql` credits each row to "Soulfull Studio" with no instructor. On the
live project they have since been pointed at `alma-guerra` ("Hugo Santi", the
owner's test account) like every other practice, so they show a Guide card and
their test plays in `practice_plays` (the payout ledger) credit that guide.
Leave them out of any payout.

## Seeding

1. Supabase dashboard → Storage → `practice-media`. Upload each file under its
   folder, so the paths match the table above exactly.
2. SQL editor → run `seed.sql`. It's idempotent, and it lists the rows it finds.
3. The tracks light up within the app's 5-minute catalog cache, or on relaunch.

## Regenerating

```bash
python3 -m venv v && v/bin/pip install numpy scipy
v/bin/python synth.py out        # out/{breathwork,meditation,somatic-soundtrack}.wav
swiftc -O -swift-version 5 render.swift -o render
./render render ../../Resources/Fonts out/somatic-silent.mp4
./render frame ../../Resources/Fonts 35 still.png        # check one pose
afconvert -f m4af -d aac -b 160000 out/somatic-soundtrack.wav out/somatic-soundtrack.m4a
./render mux out/somatic-silent.mp4 out/somatic-soundtrack.m4a out/somatic.mp4
for n in breathwork meditation; do
  afconvert -f m4af -d aac -b 160000 out/$n.wav out/$n-raw.m4a
  ./render optimize out/$n-raw.m4a out/$n.m4a    # moov first, so playback starts at once
done
./render probe out/somatic.mp4 out/breathwork.m4a out/meditation.m4a
```

If a length changes, update `duration_seconds` in `seed.sql` to match.
