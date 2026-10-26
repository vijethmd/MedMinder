"""Synthesize MedMinder's notification chime.

A soft bell playing a rising G-C-E-G motif, twice. Kept in a mid/low
pitch range (392-784 Hz) because high frequencies are the first to fade
with age-related hearing loss.

Usage: python3 tool/make_chime.py android/app/src/main/res/raw/medminder_chime.wav
"""
import math
import struct
import sys
import wave

RATE = 44100

# (start time s, frequency Hz, loudness)
NOTES = []
for repeat_start in (0.0, 1.45):
    for i, freq in enumerate([392.00, 523.25, 659.25, 783.99]):  # G4 C5 E5 G5
        NOTES.append((repeat_start + i * 0.17, freq, 0.85 if i < 3 else 1.0))

# Bell-like partials (multiple of the note, relative loudness)
PARTIALS = [(1.0, 1.0), (2.0, 0.42), (3.0, 0.18), (4.16, 0.10), (5.43, 0.05)]
LENGTH = 3.2  # seconds


def sample(t: float) -> float:
    value = 0.0
    for start, freq, gain in NOTES:
        dt = t - start
        if dt < 0 or dt > 1.6:
            continue
        attack = min(dt / 0.006, 1.0)  # 6 ms click-free attack
        for mult, amp in PARTIALS:
            # Higher partials die away faster, like a real bell
            decay = math.exp(-dt / (0.55 / mult ** 0.6))
            value += gain * amp * attack * decay * math.sin(2 * math.pi * freq * mult * dt)
    return value


def main(path: str) -> None:
    samples = [sample(n / RATE) for n in range(int(LENGTH * RATE))]
    peak = max(abs(s) for s in samples)
    scale = 0.89 / peak  # normalise to about -1 dBFS

    # Short fade-out at the very end
    fade = int(0.05 * RATE)
    for i in range(fade):
        samples[-1 - i] *= i / fade

    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))


if __name__ == "__main__":
    main(sys.argv[1])
