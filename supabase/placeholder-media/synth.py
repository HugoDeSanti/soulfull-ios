"""Placeholder practice audio for Soulfull test builds.

Builds three stereo WAVs from scratch: macOS `say` for the guiding voice,
plus synthesized sound design (drone pad, singing bowl, breath swells).

    v/bin/python synth.py <out_dir>
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = sys.argv[1]
TTS_DIR = os.path.join(OUT, "tts")
os.makedirs(TTS_DIR, exist_ok=True)
VOICE = "Samantha"


# ---------------------------------------------------------------- helpers

def lowpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x, axis=0)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x, axis=0)


def timeline(dur):
    return np.arange(int(round(dur * SR))) / SR


def tts(text, name, rate=150):
    fn = os.path.join(TTS_DIR, f"{name}.wav")
    subprocess.run(["say", "-v", VOICE, "-r", str(rate), "-o", fn,
                    "--file-format=WAVE", "--data-format=LEI16@44100", text],
                   check=True)
    with wave.open(fn) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
        data = data.astype(np.float64) / 32768
        if w.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(1)
    loud = np.where(np.abs(data) > 0.008)[0]
    data = data[max(loud[0] - 300, 0): loud[-1] + 3000]
    # Soften the compact voice: take the edge off the sibilance and the boxy
    # low end, then give it a short room so it sits inside the music.
    data = highpass(lowpass(data, 7500), 90)
    fade = np.linspace(0, 1, 400)
    data[:400] *= fade
    data[-800:] *= np.linspace(1, 0, 800)
    return data


_rng = np.random.default_rng(7)
_ir_t = timeline(1.6)
_IR_L = _rng.standard_normal(_ir_t.size) * np.exp(-_ir_t / 0.38)
_IR_R = _rng.standard_normal(_ir_t.size) * np.exp(-_ir_t / 0.38)
_IR_L, _IR_R = lowpass(_IR_L, 4000), lowpass(_IR_R, 4000)
_IR_L /= np.sqrt((_IR_L ** 2).sum())
_IR_R /= np.sqrt((_IR_R ** 2).sum())


def room(mono, wet=0.22):
    """Mono dry signal -> stereo with a soft, dark plate."""
    l = fftconvolve(mono, _IR_L)[: mono.size]
    r = fftconvolve(mono, _IR_R)[: mono.size]
    return np.stack([mono + wet * l, mono + wet * r], axis=1)


def place(track, clip, at, gain=1.0):
    """Mix a (n,2) or mono clip into a (N,2) track at `at` seconds."""
    if clip.ndim == 1:
        clip = np.stack([clip, clip], axis=1)
    i = int(round(at * SR))
    j = min(track.shape[0], i + clip.shape[0])
    track[i:j] += gain * clip[: j - i]
    return (i + clip.shape[0]) / SR


def pad(dur, freqs, seed=0, lfo=0.06):
    """A warm, slowly breathing drone: detuned sine pairs with a soft octave."""
    t = timeline(dur)
    rng = np.random.default_rng(seed)
    out = np.zeros((t.size, 2))
    for k, f in enumerate(freqs):
        ph = rng.uniform(0, 2 * np.pi, 5)
        swell = 0.55 + 0.45 * np.sin(2 * np.pi * lfo * (1 + 0.37 * k) * t + ph[0])
        det = 0.12 + 0.07 * k
        w = 1 / (1 + 0.45 * k)
        out[:, 0] += w * swell * (np.sin(2 * np.pi * (f - det) * t + ph[1])
                                  + 0.22 * np.sin(2 * np.pi * 2 * f * t + ph[2]))
        out[:, 1] += w * swell * (np.sin(2 * np.pi * (f + det) * t + ph[3])
                                  + 0.22 * np.sin(2 * np.pi * 2 * f * t + ph[4]))
    out = lowpass(out, 1800)
    return out / np.abs(out).max()


def air(dur, seed=1):
    """Very quiet filtered noise so silence never sounds like a dropout."""
    rng = np.random.default_rng(seed)
    n = rng.standard_normal((int(round(dur * SR)), 2))
    n = lowpass(n, 900, order=4)
    return n / np.abs(n).max()


def bowl(f0=220.0, dur=10.0, seed=3):
    """Struck singing bowl: inharmonic partials, each a slowly beating pair."""
    t = timeline(dur)
    rng = np.random.default_rng(seed)
    partials = [(1.0, 1.0, 6.5), (2.71, 0.45, 3.6), (5.15, 0.2, 2.0), (8.5, 0.08, 1.0)]
    out = np.zeros((t.size, 2))
    for ratio, amp, decay in partials:
        f = f0 * ratio
        beat = 0.6 + 0.5 * ratio ** 0.5
        env = amp * np.exp(-t / decay)
        for c, sign in enumerate((-1, 1)):
            ph = rng.uniform(0, 2 * np.pi, 2)
            out[:, c] += env * (np.sin(2 * np.pi * f * t + ph[0])
                                + 0.85 * np.sin(2 * np.pi * (f + sign * beat) * t + ph[1]))
    strike = rng.standard_normal(t.size) * np.exp(-t / 0.012)
    strike = bandpass(strike, 800, 3000) * 0.35
    out += strike[:, None]
    out[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))[:, None]
    return out / np.abs(out).max()


def breath_curve(t, cycles):
    """0..1 lung-fullness: sine-eased rise over each inhale, fall over the exhale."""
    y = np.zeros_like(t)
    for start, inhale, exhale in cycles:
        a = (t >= start) & (t < start + inhale)
        y[a] = np.sin(0.5 * np.pi * (t[a] - start) / inhale) ** 2
        b = (t >= start + inhale) & (t < start + inhale + exhale)
        y[b] = np.cos(0.5 * np.pi * (t[b] - start - inhale) / exhale) ** 2
    return y


def breath_sound(t, fullness, seed=5):
    """Filtered noise that swells on the inhale and sighs out on the exhale."""
    rng = np.random.default_rng(seed)
    n = rng.standard_normal((t.size, 2))
    n = bandpass(n, 350, 1600, order=2)
    n /= np.abs(n).max()
    # Loudest while air is moving, i.e. on the slope of the curve.
    motion = np.abs(np.gradient(fullness)) * SR
    motion = lowpass(motion, 3)
    motion /= max(motion.max(), 1e-9)
    return n * motion[:, None]


def finish(track, name, fade_in=1.2, fade_out=2.5):
    n = track.shape[0]
    track[: int(fade_in * SR)] *= np.linspace(0, 1, int(fade_in * SR))[:, None] ** 2
    track[n - int(fade_out * SR):] *= np.linspace(1, 0, int(fade_out * SR))[:, None] ** 2
    track *= 10 ** (-1.5 / 20) / np.abs(track).max()
    pcm = (np.clip(track, -1, 1) * 32767).astype("<i2")
    fn = os.path.join(OUT, f"{name}.wav")
    with wave.open(fn, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return fn


def voice_track(total, lines, rate, name, gain=1.0):
    """Places each (at, text[, gain]) line; refuses to let two lines overlap."""
    dry = np.zeros(int(round(total * SR)))
    last_end, spans = 0.0, []
    for k, line in enumerate(lines):
        at, text = line[0], line[1]
        g = line[2] if len(line) > 2 else 1.0
        clip = tts(text, f"{name}-{k:02d}", rate=rate)
        end = at + clip.size / SR
        assert at >= last_end + 0.1, f"{name} line {k} overlaps ({at:.2f} < {last_end:.2f}): {text}"
        assert end <= total - 1.5, f"{name} line {k} runs past the end ({end:.2f}): {text}"
        i = int(round(at * SR))
        dry[i: i + clip.size] += g * clip
        last_end = end
        spans.append({"at": at, "end": round(end, 2), "text": text})
    return room(dry) * gain, spans


# ------------------------------------------------------------- breathwork

def breathwork():
    total = 30.0
    t = timeline(total)
    cycles = [(5.0, 4.0, 6.0), (15.0, 4.0, 6.0)]
    full = breath_curve(t, cycles)

    lines = [
        (0.9, "Settle in. We'll breathe in for four, and out for six."),
        (5.0, "Breathe in."), (6.0, "two", 0.8), (7.0, "three", 0.8), (8.0, "four", 0.8),
        (9.0, "And out."), (10.0, "two", 0.8), (11.0, "three", 0.8), (12.0, "four", 0.8),
        (13.0, "five", 0.8), (14.0, "six", 0.8),
        (15.0, "In."),
        (19.0, "And slowly, out."),
        (25.2, "Let your breath find its own rhythm."),
    ]
    voice, spans = voice_track(total, lines, 150, "breathwork")

    # The drone brightens as the lungs fill: a higher chord layer rides the
    # breath curve on top of a steady low bed.
    bed = pad(total, [110.0, 164.81, 220.0], seed=11)
    lift = pad(total, [329.63, 440.0, 554.37], seed=12, lfo=0.1)
    music = 0.13 * bed + 0.09 * lift * (0.15 + 0.85 * full)[:, None]
    music += 0.012 * air(total)
    music += 0.12 * breath_sound(t, full)

    track = voice + music
    place(track, bowl(220.0, 9.0), 0.0, 0.16)
    place(track, bowl(220.0, 6.0, seed=4), 27.4, 0.12)
    return finish(track, "breathwork", fade_out=2.2), spans


# ------------------------------------------------------------- meditation

def meditation():
    total = 128.0
    lines = [
        (3.5, "Welcome. Find a comfortable seat, and let your eyes close, or soften your gaze."),
        (12.0, "Take a slow breath in through your nose. [[slnc 1800]] And let it go."),
        (22.0, "Notice where your body meets the ground. Let it hold you."),
        (32.0, "There is nothing to fix, and nowhere to be. Just this breath."),
        (44.0, "Breathe in. [[slnc 3500]] And breathe out."),
        (58.0, "If your mind wanders, that's all right. Gently come back to the feeling of your breath."),
        (75.0, "Let your shoulders drop. [[slnc 1400]] Let your jaw soften."),
        (89.0, "Rest here, for a few breaths."),
        (107.0, "Slowly, begin to come back. Notice the sounds around you."),
        (116.0, "When you're ready, open your eyes. Thank you for practising."),
    ]
    voice, spans = voice_track(total, lines, 138, "meditation")

    # D major-ish drone with an open fifth underneath; it never resolves, so
    # it can sit under silence for twenty seconds without calling attention.
    music = 0.16 * pad(total, [73.42, 110.0, 146.83], seed=21, lfo=0.04)
    music += 0.07 * pad(total, [220.0, 277.18, 369.99], seed=22, lfo=0.05)
    music += 0.015 * air(total, seed=23)

    track = voice + music
    place(track, bowl(196.0, 12.0, seed=6), 0.2, 0.2)
    place(track, bowl(196.0, 9.0, seed=8), 122.0, 0.17)
    return finish(track, "meditation", fade_in=1.5, fade_out=4.0), spans


# ------------------------------------------------- somatic video soundtrack

def somatic():
    total = 60.0
    lines = [
        (1.0, "Stand tall, with your feet hip-width apart. Let your arms hang loose."),
        (6.0, "Breathe in, and let your arms float up."),
        (10.0, "Breathe out, and let them fall."),
        (14.0, "In, and reach."),
        (18.0, "Out, and soften."),
        (22.0, "Once more. In."),
        (26.0, "And out."),
        (30.2, "Reach up, and sway to one side."),
        (37.0, "And over to the other side."),
        (42.4, "Now bounce gently through your knees. Shake out your arms."),
        (50.3, "Rest one hand on your heart, and one on your belly."),
        (54.8, "Breathe, and notice how you feel."),
    ]
    voice, spans = voice_track(total, lines, 150, "somatic")

    music = 0.13 * pad(total, [98.0, 146.83, 196.0], seed=31, lfo=0.07)
    music += 0.065 * pad(total, [293.66, 369.99, 440.0], seed=32, lfo=0.09)
    music += 0.012 * air(total, seed=33)

    track = voice + music
    place(track, bowl(247.0, 8.0, seed=9), 0.0, 0.13)
    place(track, bowl(247.0, 6.0, seed=10), 57.6, 0.1)
    return finish(track, "somatic-soundtrack", fade_in=0.8, fade_out=2.0), spans


if __name__ == "__main__":
    report = {}
    for fn in (breathwork, meditation, somatic):
        path, spans = fn()
        report[os.path.basename(path)] = spans
    with open(os.path.join(OUT, "voice-spans.json"), "w") as f:
        json.dump(report, f, indent=1)
    for name, spans in report.items():
        print(name)
        for s in spans:
            print(f"  {s['at']:6.1f}–{s['end']:6.2f}  {s['text']}")
