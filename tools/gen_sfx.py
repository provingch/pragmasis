# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy"]
# ///
"""Procedural SFX for pragmasis -> audio/sfx/*.wav (48 kHz, 16-bit mono).

    uv run tools/gen_sfx.py

Fixed seed: re-running rewrites byte-identical files. The portal hum is a
seamless loop (every partial completes whole cycles, the noise is circular)
and carries a WAV 'smpl' loop chunk, which Godot's importer picks up on its
default "Detect from WAV" loop mode.
"""
import struct
from pathlib import Path

import numpy as np
from scipy import signal

SR = 48000
OUT = Path(__file__).resolve().parent.parent / "audio/sfx"
rng = np.random.default_rng(4)


# --- building blocks ------------------------------------------------------------

def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def noise(dur: float) -> np.ndarray:
    return rng.standard_normal(int(dur * SR))


def filt(x: np.ndarray, kind: str, freq, order: int = 4) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, freq, kind, fs=SR, output="sos"), x)


def env(t: np.ndarray, attack: float, decay: float, start: float = 0.0) -> np.ndarray:
    """Linear attack, exponential decay (time constant `decay`), from `start`."""
    u = t - start
    return np.where(u < 0, 0.0, np.where(u < attack, u / attack, np.exp(-(u - attack) / decay)))


def sweep_band(x: np.ndarray, f_start: float, f_end: float, octaves: float) -> np.ndarray:
    """Band-pass whose centre glides exponentially from f_start to f_end."""
    f, tt, z = signal.stft(x, SR, nperseg=1024)
    centre = f_start * (f_end / f_start) ** (tt / tt[-1])
    dist = np.log2(np.maximum(f[:, None], 1.0) / centre[None, :])
    z *= np.exp(-0.5 * (dist / (octaves / 2)) ** 2)
    return signal.istft(z, SR, nperseg=1024)[1][: len(x)]


def closing_lowpass(x: np.ndarray, f_start: float, f_end: float) -> np.ndarray:
    f, tt, z = signal.stft(x, SR, nperseg=1024)
    cut = f_start * (f_end / f_start) ** (tt / tt[-1])
    z *= 1.0 / (1.0 + (f[:, None] / cut[None, :]) ** 4)
    return signal.istft(z, SR, nperseg=1024)[1][: len(x)]


def osc(freq, t: np.ndarray, shape: str = "sine") -> np.ndarray:
    """freq may be an array (glides): phase is its running integral."""
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(freq, t.shape)) / SR
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    return np.sin(ph)


def crush(x: np.ndarray, bits: int, hold: int) -> np.ndarray:
    """Bit depth reduction + sample-and-hold: the digital-corruption sound."""
    held = np.repeat(x[::hold], hold)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(held * q) / q


def fade_edges(x: np.ndarray, ms: float = 3.0) -> np.ndarray:
    n = int(ms * SR / 1000)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def norm(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x / np.abs(x).max() * 10 ** (peak_db / 20)


def write(name: str, x: np.ndarray, loop: bool = False) -> None:
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        # smpl: header (9 x u32) + one forward loop over the whole file.
        smpl = struct.pack("<9I", 0, 0, 10**9 // SR, 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, len(x) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    (OUT / f"{name}.wav").write_bytes(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


# --- sounds ---------------------------------------------------------------------

def footstep(run: bool) -> np.ndarray:
    """Muffled shoe on concrete: low thud, a body thump, a gritty scuff; a
    walk adds a softer toe tap after the heel, a run is one tighter, brighter hit."""
    dur = 0.2 if run else 0.3
    t = t_axis(dur)
    cutoff = rng.uniform(650, 950) if run else rng.uniform(280, 440)
    tau = rng.uniform(0.02, 0.028) if run else rng.uniform(0.035, 0.05)
    x = filt(noise(dur), "lowpass", cutoff) * env(t, 0.002, tau)
    body_f = rng.uniform(62, 82) * (1 + 0.4 * np.exp(-t / 0.02))
    x += 0.3 * osc(body_f, t) * env(t, 0.003, tau * 0.7)
    scuff_at = rng.uniform(0.008, 0.02)
    x += (0.22 if run else 0.12) * filt(noise(dur), "bandpass", [1500, 4200], 2) * env(t, 0.003, 0.01, scuff_at)
    if run:
        x += 0.5 * filt(noise(dur), "highpass", 2500, 2) * env(t, 0.0005, 0.003)
    else:
        toe_at = rng.uniform(0.05, 0.075)
        x += 0.35 * filt(noise(dur), "lowpass", cutoff * 1.3) * env(t, 0.002, tau * 0.7, toe_at)
    return fade_edges(norm(x, -3 if run else -6))


def monster_stinger() -> np.ndarray:
    """The tesseract unfolding: a sub drop under stuttering bit-crushed tones
    tuned to 4D diagonals (1, sqrt2, 2, 2*sqrt2) and an FM screech falling away."""
    dur = 1.4
    t = t_axis(dur)
    x = 0.9 * np.tanh(2.5 * osc(48 * (1 + 0.6 * np.exp(-t / 0.05)), t)) * env(t, 0.004, 0.45)
    tones = 110 * np.array([1, np.sqrt(2), 2, 2 * np.sqrt(2), 4])
    glitch = np.zeros_like(t)
    pos = 0.0
    while pos < 0.95:
        g = rng.uniform(0.018, 0.06)
        tg = t_axis(g)
        grain = crush(osc(rng.choice(tones) * rng.choice([1, 2]), tg, rng.choice(["square", "saw"])), int(rng.integers(3, 6)), int(rng.integers(4, 18)))
        grain = fade_edges(grain, 1.0) * (1 - pos) ** 1.5
        for _ in range(int(rng.integers(1, 4))):  # stutter: retrigger the same grain
            i = int(pos * SR)
            n = min(len(grain), len(t) - i)
            if n <= 0 or rng.random() < 0.2:
                break
            glitch[i:i + n] += grain[:n]
            pos += g * rng.uniform(0.9, 1.3)
        pos += rng.uniform(0.0, 0.04)
    x += 0.55 * glitch
    carrier = 1400 * np.exp(-t / 0.35) + 180
    screech = osc(carrier + 900 * np.exp(-t / 0.25) * osc(carrier * np.sqrt(2), t), t)
    x += 0.3 * screech * env(t, 0.01, 0.3)
    return fade_edges(norm(np.tanh(1.4 * x), -1), 20)


def game_over() -> np.ndarray:
    """Caught: a distorted dissonant cluster that dives like a tape stop while
    a low-pass closes over it, on top of a hard impact."""
    dur = 1.9
    t = t_axis(dur)
    dive = 0.08 + 0.92 * np.exp(-np.maximum(t - 0.12, 0) / 0.45)
    cluster = sum(osc(f * dive, t, "saw") for f in [55, 82.4, 110, 116.5, 164.8])
    x = np.tanh(5.0 * cluster / 5)
    x += 1.2 * filt(noise(dur), "lowpass", 3500) * env(t, 0.001, 0.09)
    x += 1.0 * osc(40 * dive, t) * env(t, 0.002, 0.6)
    x = closing_lowpass(np.tanh(2.0 * x), 7000, 180)
    x *= np.clip((dur - t) / 0.7, 0, 1)
    return fade_edges(norm(x, -1), 5)


def whoosh(up: bool) -> np.ndarray:
    """Phase jump: band-passed noise sweeping over ~4.5 octaves plus a thin
    tonal glide, rising for +w and falling for -w."""
    dur = 0.9
    t = t_axis(dur)
    lo, hi = 160.0, 3800.0
    a, b = (lo, hi) if up else (hi, lo)
    x = sweep_band(noise(dur), a, b, 0.8)
    x += 0.08 * osc(a / 2 * (b / a) ** (t / dur), t) / np.abs(x).max()
    peak = 0.62 if up else 0.38
    shape = np.where(t < peak * dur, np.sin(np.pi / 2 * t / (peak * dur)) ** 2, np.cos(np.pi / 2 * (t - peak * dur) / ((1 - peak) * dur)) ** 2)
    return fade_edges(norm(x * shape, -3))


def portal_hum() -> np.ndarray:
    """4 s seamless loop: every partial is a multiple of 0.25 Hz (whole cycles
    per loop) and the shimmer noise is shaped in the frequency domain of the
    full loop, so it's circular."""
    dur = 4.0
    t = t_axis(dur)
    x = 0.5 * osc(55, t) + 0.35 * osc(110, t) + 0.35 * osc(110.5, t) + 0.12 * osc(165, t)
    x += 0.05 * (osc(880, t) + osc(880.75, t))
    spec = np.fft.rfft(rng.standard_normal(len(t)))
    f = np.fft.rfftfreq(len(t), 1 / SR)
    spec *= np.exp(-0.5 * (np.log2(np.maximum(f, 1) / 1100) / 0.6) ** 2)
    shimmer = np.fft.irfft(spec, len(t))
    x += 0.25 * shimmer / np.abs(shimmer).max() * (0.6 + 0.4 * osc(0.5, t))
    return norm(np.tanh(1.5 * x), -6)


def blip(freqs: list[float], each: float, gap: float, shape: str = "square", peak_db: float = -9) -> np.ndarray:
    """Terminal beeps in sequence, low-passed so the squares don't rasp."""
    dur = len(freqs) * (each + gap) + 0.02
    t = t_axis(dur)
    x = np.zeros_like(t)
    for i, fr in enumerate(freqs):
        start = i * (each + gap)
        gate = ((t >= start) & (t < start + each)).astype(float)
        x += osc(fr, t, shape) * gate * env(t, 0.001, each * 0.8, start)
    return fade_edges(norm(filt(x, "lowpass", 5000, 4), peak_db), 2)


def ui_hover() -> np.ndarray:
    t = t_axis(0.06)
    x = osc(2400, t) + 0.3 * osc(3600, t)
    return fade_edges(norm(np.tanh(2 * x) * env(t, 0.001, 0.012), -12), 2)


def scanner(opening: bool) -> np.ndarray:
    """CRT terminal: power-on chirp then rising beeps; power-off is falling
    beeps then the picture collapsing (chirp down + pop)."""
    if opening:
        t = t_axis(0.05)
        chirp = osc(300 * (8 ** (t / 0.05)), t) * np.linspace(0.3, 1, len(t))
        return np.concatenate([norm(chirp, -14), blip([1000, 1500, 2000], 0.04, 0.015, peak_db=-9)])
    beeps = blip([1600, 900], 0.04, 0.015, peak_db=-9)
    t = t_axis(0.09)
    off = osc(2000 * (0.075 ** (t / 0.09)), t) * np.linspace(1, 0, len(t))
    off += 0.6 * filt(noise(0.09), "lowpass", 2000) * env(t, 0.0005, 0.006, 0.08)
    return np.concatenate([beeps, fade_edges(norm(off, -12), 2)])


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        write(f"step_walk_{i + 1}", footstep(run=False))
        write(f"step_run_{i + 1}", footstep(run=True))
    write("monster_stinger", monster_stinger())
    write("game_over", game_over())
    write("whoosh_up", whoosh(up=True))
    write("whoosh_down", whoosh(up=False))
    write("portal_hum", portal_hum(), loop=True)
    write("ui_hover", ui_hover())
    write("ui_select", blip([1400, 2100], 0.035, 0.01, peak_db=-10))
    write("scanner_open", scanner(opening=True))
    write("scanner_close", scanner(opening=False))
    for p in sorted(OUT.glob("*.wav")):
        print(f"{p.name:22s} {p.stat().st_size / 1024:6.1f} KB")
