# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy"]
# ///
"""Seamless loops for the music: tools/music_src/*.mp3 -> audio/music/*.ogg.

    uv run tools/loop_music.py [track ...]   (needs ffmpeg with libvorbis)

With no arguments, every track in TRACKS.

Every track fades in and out, so looping the whole file jumps from a fade
through silence into an intro. For each track this picks a loop start S
(after the intro) and end E (before the outro) whose preceding ~2 s sound
most alike (log-spectrogram, time-aligned, so the beat has to line up too),
favouring long loops (LENGTH_PENALTY), then aligns their phase to the sample. The written file is x[:E] with its
last XFADE seconds crossfaded into x[S-XFADE:S]: at E the audio *is* the
continuation of S, so the jump back to S is sample-contiguous whatever the
match quality. Encoded to Ogg Vorbis (MP3 frames pad the end and can't cut
at an exact sample).

Writes each S into audio/music/<track>.tres (a MusicTrack: the one place
the game reads loop points from), creating the .tres if it's new.
"""
import re
import subprocess
from pathlib import Path

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parent.parent
TRACKS = ["carne", "sedimento", "umbral", "eter", "estatica", "persecucion", "nucleo"]
HOP = 1024
CONTEXT = 2.0     # seconds compared before each candidate point
XFADE = 1.0       # seconds of crossfade baked in before E
SEARCH_S = 30.0   # S searched within this long after the intro
SEARCH_E = 30.0   # E searched within this long before the outro
BODY_DB = 6.0     # intro/outro = where 1 s RMS is this far below the track's median
LENGTH_PENALTY = 0.002  # similarity given up per second of music left out of the loop


def load(path: Path) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).copy()


def body_bounds(mono: np.ndarray) -> tuple[float, float]:
    """First/last second whose RMS is within BODY_DB of the median: skips fade-in and fade-out."""
    sec = mono[: len(mono) // SR * SR].reshape(-1, SR)
    db = 10 * np.log10(np.mean(sec**2, axis=1) + 1e-12)
    loud = np.nonzero(db > np.median(db) - BODY_DB)[0]
    return float(loud[0] + 1), float(loud[-1])


def logspec(mono: np.ndarray) -> np.ndarray:
    frames = np.lib.stride_tricks.sliding_window_view(mono, 4096)[::HOP] * np.hanning(4096)
    mag = np.abs(np.fft.rfft(frames, axis=1))[:, 1:1024]  # up to ~12 kHz
    # ~48 log-spaced bands: timbre and harmony without per-bin noise
    edges = np.unique(np.geomspace(1, mag.shape[1], 49).astype(int))
    bands = np.add.reduceat(mag, edges[:-1], axis=1)
    return np.log1p(bands)


def windows(spec: np.ndarray, ends: np.ndarray, w: int) -> np.ndarray:
    m = np.stack([spec[e - w:e].ravel() for e in ends])
    m -= m.mean(axis=1, keepdims=True)
    return m / (np.linalg.norm(m, axis=1, keepdims=True) + 1e-9)


def best_lag(x: np.ndarray, ref: np.ndarray, max_lag: int) -> int:
    """Shift d (samples) maximising the correlation of x[d:d+len(ref)] with ref."""
    n = len(ref) + 2 * max_lag
    c = np.fft.irfft(np.fft.rfft(x, 2 * n) * np.conj(np.fft.rfft(ref, 2 * n)), 2 * n)[: 2 * max_lag + 1]
    return int(np.argmax(c)) - max_lag


def process(name: str) -> tuple[float, float, float]:
    x = load(ROOT / "tools/music_src" / f"{name}.mp3")
    mono = x.mean(axis=1)
    t0, t1 = body_bounds(mono)
    spec = logspec(mono)
    w = int(CONTEXT * SR / HOP)
    f = lambda t: int(t * SR / HOP)
    s_frames = np.arange(max(f(t0), w), f(t0 + SEARCH_S))
    e_frames = np.arange(f(t1 - SEARCH_E), f(t1))
    sim = windows(spec, e_frames, w) @ windows(spec, s_frames, w).T
    lost = ((s_frames[None, :] - f(t0)) + (f(t1) - e_frames[:, None])) * HOP / SR
    ei, si = np.unravel_index(np.argmax(sim - LENGTH_PENALTY * lost), sim.shape)
    e = e_frames[ei] * HOP
    s = s_frames[si] * HOP
    # Phase: slide S (+-1 hop) so the last 50 ms before it match those before E.
    n = int(0.05 * SR)
    s += best_lag(mono[s - n - HOP:s + HOP], mono[e - n:e], HOP)

    L = int(XFADE * SR)
    a, b = x[e - L:e], x[s - L:s]
    corr = float(np.corrcoef(a.mean(1), b.mean(1))[0, 1])
    # Correlated material sums in amplitude (linear fade keeps level);
    # uncorrelated sums in power (equal-power fade keeps level).
    ramp = np.linspace(0.0, 1.0, L, dtype=np.float32)[:, None]
    fi, fo = (ramp, 1 - ramp) if corr > 0.5 else (np.sin(ramp * np.pi / 2), np.cos(ramp * np.pi / 2))
    y = np.concatenate([x[: e - L], a * fo + b * fi])

    # The junction: last sample of the file -> sample S. Compare that step
    # with the track's own sample-to-sample steps.
    jump = np.abs(y[-1] - x[s]).max()
    typical = np.percentile(np.abs(np.diff(mono)), 99.9)

    out = ROOT / "audio/music" / f"{name}.ogg"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "6", str(out)], input=y.astype(np.float32).tobytes(), check=True)
    # Godot truncates loop_offset * rate to a sample: aim at the sample's middle.
    print(f"{name:12s} loop_offset={(s + 0.5) / SR:.6f} s  fin={e / SR:8.3f} s  bucle={(e - s) / SR:7.2f} s  "
          f"similitud={sim[ei, si]:.3f}  corr_xfade={corr:+.2f}  salto_union={jump:.4f} (p99.9 propio {typical:.4f})")
    write_track(name, (s + 0.5) / SR)
    return (s + 0.5) / SR, e / SR, float(sim[ei, si])


def write_track(name: str, offset: float) -> None:
    """Sets loop_offset in the MusicTrack .tres (keeping the rest of it). A
    placeholder .tres borrowing another track's stream is pointed at its own."""
    path = ROOT / "audio/music" / f"{name}.tres"
    line = f"loop_offset = {offset:.6f}"
    if path.exists():
        # (Godot resolves a uid before the path: drop it.)
        text = re.sub(r'\[ext_resource type="AudioStream"[^\]]*id="([^"]*)"\]',
                      rf'[ext_resource type="AudioStream" path="res://audio/music/{name}.ogg" id="\1"]', path.read_text())
        if "loop_offset = " in text:
            text = re.sub(r"loop_offset = [\d.]+", line, text)
        else:
            text = text.rstrip("\n") + "\n" + line + "\n"
    else:
        text = (
            '[gd_resource type="Resource" script_class="MusicTrack" load_steps=3 format=3]\n\n'
            '[ext_resource type="Script" path="res://scripts/audio/MusicTrack.gd" id="1"]\n'
            f'[ext_resource type="AudioStream" path="res://audio/music/{name}.ogg" id="2"]\n\n'
            '[resource]\nscript = ExtResource("1")\nstream = ExtResource("2")\n' + line + "\n"
        )
    path.write_text(text)


if __name__ == "__main__":
    import sys
    for t in sys.argv[1:] or TRACKS:
        process(t)
