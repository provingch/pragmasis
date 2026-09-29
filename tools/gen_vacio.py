# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy"]
# ///
"""VACÍO's music, synthesized -> tools/music_src/vacio.mp3 (then loop it):

    uv run tools/gen_vacio.py && uv run tools/loop_music.py vacio

Almost silence: a room tone and a sub-bass hum you feel more than hear, a
faint tinnitus whine that swells and fades over tens of seconds, rare
distant rumbles, now and then a far-off click in a huge space. Fixed seed:
re-running rewrites the same file. Fades in and out, as loop_music.py
expects of a source track (it cuts the loop from the body).
"""
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal

SR = 48000
DUR = 160.0
FADE = 5.0
OUT = Path(__file__).resolve().parent / "music_src/vacio.mp3"
rng = np.random.default_rng(23)
t = np.arange(int(DUR * SR)) / SR
n = len(t)


def db(x: float) -> float:
    return 10 ** (x / 20)


def filt(x: np.ndarray, kind: str, freq, order: int = 4) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, freq, kind, fs=SR, output="sos"), x, axis=0)


def slow(period: float, phase: float = 0.0) -> np.ndarray:
    """0..1, a smooth swell every `period` seconds."""
    return 0.5 - 0.5 * np.cos(2 * np.pi * t / period + phase)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x**2)))


def reverb(dry: np.ndarray, seconds: float, lowpass: float) -> np.ndarray:
    """A big empty room: decaying noise as the impulse response, per channel."""
    k = int(seconds * SR)
    decay = np.exp(-np.arange(k) / SR * 6.9 / seconds)
    ir = filt(rng.standard_normal((k, 2)), "lowpass", lowpass) * decay[:, None]
    return np.stack([signal.fftconvolve(dry[:, c], ir[:, c])[:n] for c in range(2)], axis=1) / np.sqrt(k)


# Room tone: brown-ish noise, low-passed, breathing a little. Each channel
# its own noise, so it's wide.
tone = filt(np.cumsum(rng.standard_normal((n, 2)), axis=0), "highpass", 25)
tone = filt(tone, "lowpass", 260)
tone *= db(-44) / rms(tone) * (0.8 + 0.2 * slow(37.0))[:, None]

# Hum: two sub tones a hair apart per side, beating slowly.
hum = np.stack([np.sin(2 * np.pi * 41.0 * t) + 0.5 * np.sin(2 * np.pi * 55.2 * t),
                np.sin(2 * np.pi * 41.13 * t) + 0.5 * np.sin(2 * np.pi * 55.0 * t)], axis=1)
hum *= db(-38) / rms(hum) * (0.6 + 0.4 * slow(53.0, 1.0))[:, None]

# Tinnitus: a thin whine near 7.9 kHz, drifting a few Hz, two partials a
# little apart so it shimmers; swells up and dies away (~41 s, ~67 s).
drift = 7900 + 14 * np.sin(2 * np.pi * t / 29.0)
phase = 2 * np.pi * np.cumsum(drift) / SR
whine = np.sin(phase) + 0.35 * np.sin(phase * 1.0021)
swell = slow(41.0) ** 3 * (0.4 + 0.6 * slow(67.0, 2.0))
whine = np.stack([whine * swell, whine * swell * 0.85], axis=1) * db(-50)

# Rumbles: rare, long, very low bursts far away.
rumble = np.zeros((n, 2))
at = 9.0
while at < DUR - 12:
    length = rng.uniform(3.0, 6.0)
    i0, i1 = int(at * SR), int((at + length) * SR)
    env = np.sin(np.linspace(0, np.pi, i1 - i0)) ** 2
    burst = filt(rng.standard_normal((i1 - i0, 2)), "lowpass", rng.uniform(70, 120), order=6) * env[:, None]
    rumble[i0:i1] += burst / rms(burst) * db(rng.uniform(-36, -30))
    at += rng.uniform(22.0, 40.0)

# Clicks: a far-off tick, panned, mostly heard as its tail.
clicks = np.zeros((n, 2))
at = 4.0
while at < DUR - 6:
    i = int(at * SR)
    k = int(0.002 * SR)
    tick = filt(rng.standard_normal(k), "bandpass", [1200, 5000], order=2) * np.hanning(k)
    pan = rng.uniform(0.15, 0.85)
    level = db(rng.uniform(-40, -32)) / np.abs(tick).max()
    clicks[i:i + k, 0] += tick * level * (1 - pan)
    clicks[i:i + k, 1] += tick * level * pan
    at += rng.uniform(7.0, 23.0)

far = reverb(rumble + clicks, 3.5, 2500)
mix = tone + hum + whine + rumble * 0.4 + clicks * 0.15 + far * 2.5

# Fade in and out (loop_music.py takes the loop from the body between).
fade = np.minimum(1.0, np.minimum(t / FADE, (DUR - t) / FADE))[:, None]
mix = mix * fade
peak = np.abs(mix).max()
if peak > db(-6):
    mix *= db(-6) / peak
print(f"pico {20 * np.log10(np.abs(mix).max()):.1f} dBFS, rms {20 * np.log10(rms(mix)):.1f} dBFS")

OUT.parent.mkdir(exist_ok=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                "-c:a", "libmp3lame", "-q:a", "2", str(OUT)], input=mix.astype(np.float32).tobytes(), check=True)
print(OUT)
