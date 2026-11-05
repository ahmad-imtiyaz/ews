"""Membuat suara notifikasi EWS, tanpa bahan dari pihak lain.

Jalankan dari akar proyek: python tool/generate_notification_sounds.py

Android menyimpan suara saat channel pertama dibuat. Kalau file ini diubah,
ganti juga id channel di lib/services/notification_service.dart.
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT_DIR = Path("android/app/src/main/res/raw")


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def mix(track, sound, start):
    offset = int(start * RATE)
    needed = offset + len(sound)
    if needed > len(track):
        track.extend([0.0] * (needed - len(track)))
    for index, sample in enumerate(sound):
        track[offset + index] += sample


def chime(frequency, seconds):
    """Nada lonceng: cepat muncul, lalu meredup perlahan."""
    samples = []
    for index in range(int(RATE * seconds)):
        t = index / RATE
        attack = min(t / 0.006, 1)
        decay = math.exp(-3.4 * t)
        tone = (
            math.sin(2 * math.pi * frequency * t)
            + 0.35 * math.sin(2 * math.pi * frequency * 2 * t)
            + 0.12 * math.sin(2 * math.pi * frequency * 3 * t)
        )
        samples.append(attack * decay * tone)
    return samples


def alarm_tone(frequency, seconds):
    """Nada sirene yang tegas, dengan tepi halus supaya tidak berbunyi klik."""
    samples = []
    count = int(RATE * seconds)
    for index in range(count):
        t = index / RATE
        edge = min(t / 0.012, (count - index) / RATE / 0.012, 1)
        tone = (
            math.sin(2 * math.pi * frequency * t)
            + 0.45 * math.sin(2 * math.pi * frequency * 2 * t)
            + 0.2 * math.sin(2 * math.pi * frequency * 3 * t)
        )
        samples.append(edge * tone)
    return samples


def waspada():
    # Tiga nada naik: menarik perhatian tanpa terdengar darurat.
    track = silence(0)
    for start, frequency in [(0.0, 587.33), (0.17, 880.0), (0.34, 739.99)]:
        mix(track, chime(frequency, 1.1), start)
    return track


def awas():
    # Dua nada naik turun bergantian, seperti sirene.
    track = silence(0)
    for cycle in range(4):
        start = cycle * 0.62
        mix(track, alarm_tone(932.33, 0.29), start)
        mix(track, alarm_tone(622.25, 0.29), start + 0.31)
    return track


def write_wav(name, samples, peak):
    highest = max(abs(sample) for sample in samples)
    path = OUT_DIR / f"{name}.wav"
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(
            b"".join(
                struct.pack("<h", int(sample / highest * peak * 32767))
                for sample in samples
            )
        )
    print(f"{path}: {len(samples) / RATE:.1f} detik, {path.stat().st_size} byte")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_wav("ews_waspada", waspada(), peak=0.8)
    write_wav("ews_awas", awas(), peak=0.9)


if __name__ == "__main__":
    main()
