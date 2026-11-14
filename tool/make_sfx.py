"""Synthesises DuckLearn's UI sounds into app/assets/sfx/ (run once; outputs are committed).

Everything is generated here from sine partials and envelopes, so there are no third-party
sound licences. Kept quiet and short: they confirm a tap, they never celebrate loudly.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "sfx"


def note(freq, ms, vol=0.3, attack=4, decay=None, partials=(1.0, 0.25, 0.08), bend=0.0):
    n = int(RATE * ms / 1000)
    decay = decay or ms
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, i / max(1, RATE * attack / 1000)) * math.exp(-t * 1000 / decay * 3)
        f = freq * (1 + bend * t * 1000 / ms)
        s = sum(a * math.sin(2 * math.pi * f * (k + 1) * t) for k, a in enumerate(partials))
        out.append(vol * env * s)
    return out


def seq(*parts, gap=0):
    out = []
    for p in parts:
        out += p + [0.0] * int(RATE * gap / 1000)
    return out


def mix(a, b, offset_ms):
    off = int(RATE * offset_ms / 1000)
    out = a + [0.0] * max(0, off + len(b) - len(a))
    for i, v in enumerate(b):
        out[off + i] += v
    return out


def quack():
    # a soft cartoon "wak": nasal buzz with a falling pitch
    n = int(RATE * 0.16)
    out = []
    for i in range(n):
        t = i / RATE
        f = 520 - 900 * t
        env = min(1.0, i / (RATE * 0.01)) * math.exp(-t * 14)
        s = sum((0.6 / k) * math.sin(2 * math.pi * f * k * t) for k in range(1, 9))
        out.append(0.22 * env * math.tanh(2.5 * s))
    return out


SOUNDS = {
    "tap": note(1320, 45, vol=0.18, decay=30, partials=(1.0, 0.1)),
    "reveal": note(880, 90, vol=0.2, decay=70, bend=0.15),
    "next": seq(note(660, 60, vol=0.2), note(990, 90, vol=0.2), gap=10),
    "save": mix(note(784, 120, vol=0.2), note(1175, 160, vol=0.18), 50),
    "good": seq(note(784, 90, vol=0.22), note(988, 90, vol=0.22), note(1319, 220, vol=0.22), gap=5),
    "try": seq(note(523, 110, vol=0.18), note(440, 170, vol=0.16), gap=10),
    "finish": seq(
        note(523, 110, vol=0.22), note(659, 110, vol=0.22), note(784, 110, vol=0.22),
        note(1047, 380, vol=0.24), gap=10,
    ),
    "quack": quack(),
    "mic": note(1047, 70, vol=0.18, decay=60, bend=0.1),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, samples in SOUNDS.items():
        peak = max(1e-9, max(abs(s) for s in samples))
        scale = min(1.0, 0.9 / peak)
        with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(s * scale * 32767)) for s in samples))
        print(name, len(samples) / RATE)


if __name__ == "__main__":
    main()
