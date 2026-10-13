"""Build original Jingwei sound assets using only Python's standard library.

Run from any directory; deterministic seeds keep regenerated assets reproducible.
No external recordings, network calls or runtime synthesis are needed.
"""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 44100
TAU = math.tau
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def blank(seconds):
    return [0.0] * round(seconds * RATE)


def add(dst, src, delay=0.0, gain=1.0):
    offset = round(delay * RATE)
    for i in range(min(len(src), len(dst) - offset)):
        dst[i + offset] += src[i] * gain


def resonator(seconds, frequency, decay, ratios=(1, 1.47, 2.09), weights=(1, .3, .16)):
    samples = blank(seconds)
    for i in range(len(samples)):
        t = i / RATE
        attack = 1 - math.exp(-t * 1100)
        samples[i] = attack * sum(
            weight * math.sin(TAU * frequency * ratio * t) * math.exp(-t * decay * (1 + k * .45))
            for k, (ratio, weight) in enumerate(zip(ratios, weights))
        )
    return samples


def noise(seconds, rng, cutoff=1800, decay=12, attack=.002):
    samples = blank(seconds)
    low = 0.0
    alpha = 1 - math.exp(-TAU * cutoff / RATE)
    for i in range(len(samples)):
        t = i / RATE
        low += alpha * (rng.uniform(-1, 1) - low)
        samples[i] = low * (1 - math.exp(-t / attack)) * math.exp(-t * decay)
    return samples


def stone(rng, heavy=False):
    samples = blank(.42 if heavy else .25)
    for delay, strength in [(0, 1), (.033, .36), (.078, .17)]:
        frequency = rng.uniform(380, 620) if heavy else rng.uniform(780, 1100)
        add(samples, resonator(.22, frequency, 38), delay, strength * .24)
        add(samples, noise(.18, rng, 2400, 40), delay, strength * .7)
    add(samples, resonator(.27, 115 if heavy else 230, 26), gain=.22)
    return samples


def splash(rng):
    samples = blank(.72)
    add(samples, resonator(.24, rng.uniform(100, 150), 19, (1, 1.7), (1, .18)), gain=.27)
    add(samples, noise(.68, rng, 3200, 7, .018), gain=1.0)
    for delay, frequency in [(.07, 650), (.14, 940), (.24, 1250), (.34, 810)]:
        droplet = blank(.13)
        for i in range(len(droplet)):
            t = i / RATE
            phase = TAU * frequency * (t + .9 * t * t)
            droplet[i] = math.sin(phase) * (1 - math.exp(-t * 800)) * math.exp(-t * 38)
        add(samples, droplet, delay + rng.uniform(0, .02), .065)
    return samples


def chimes(notes, spacing, seconds):
    samples = blank(seconds)
    for index, frequency in enumerate(notes):
        voice = resonator(seconds - index * spacing, frequency, 3.1, (1, 2, 3.01, 4.18), (1, .22, .06, .025))
        add(samples, voice, index * spacing, .24)
        # Quiet reflected taps make the tone less dry without adding a live reverb bus.
        add(samples, voice, index * spacing + .073, .025)
        add(samples, voice, index * spacing + .137, .012)
    return samples


def write(name, channels, peak=.62):
    length = len(channels[0])
    # Remove DC, then apply short click-free endpoint fades to every asset.
    for channel in channels:
        mean = sum(channel) / len(channel)
        for i in range(length):
            fade = min(1.0, i / (RATE * .003), (length - 1 - i) / (RATE * .045))
            channel[i] = (channel[i] - mean) * max(0, fade)
    highest = max(abs(value) for channel in channels for value in channel)
    gain = peak / max(highest, .00001)
    data = bytearray(length * len(channels) * 2)
    for i in range(length):
        for c, channel in enumerate(channels):
            struct.pack_into("<h", data, (i * len(channels) + c) * 2, round(channel[i] * gain * 32767))
    with wave.open(str(OUT / (name + ".wav")), "wb") as output:
        output.setnchannels(len(channels))
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(data)
    # Playback loop is configured explicitly in soundscape.gd, independent of import defaults.
    print(f"{name}: {length / RATE:.2f}s, {len(channels)} channel(s), peak {peak:.2f}")


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    for variant in range(3):
        rng = random.Random(20261013 + variant)
        write(f"gather_{variant}", [stone(rng)])
        write(f"land_{variant}", [stone(rng, True)])
        write(f"water_{variant}", [splash(rng)])
        whoosh = noise(.26, rng, 1400, 13, .04)
        write(f"throw_{variant}", [whoosh], .45)
    write("fill", [chimes([392, 523.25], .10, .8)], .46)
    write("upgrade", [chimes([392, 493.88, 587.33], .095, 1.05)])
    write("relic", [chimes([523.25, 659.25, 783.99, 1046.5], .16, 2.3)])
    write("unlock", [chimes([261.63, 392, 523.25], .13, 1.2)], .52)
    write("complete", [chimes([261.63, 329.63, 392, 523.25, 659.25, 783.99], .22, 3.2)])
    rng = random.Random(918)
    crumble = blank(1.05)
    for delay, gain in [(0, .8), (.11, .55), (.23, .35), (.38, .2)]:
        add(crumble, stone(rng, True), delay, gain)
    add(crumble, noise(.9, rng, 480, 5, .02), gain=.5)
    write("mined", [crumble], .56)
    # Two independent layers of soft surf, with non-aligned swell peaks.
    channels = []
    for side in range(2):
        rng = random.Random(500 + side)
        channel = blank(12)
        smooth = slow = 0.0
        for i in range(len(channel)):
            t = i / RATE
            smooth += .13 * (rng.uniform(-1, 1) - smooth)
            slow += .008 * (smooth - slow)
            swell = .12 + .62 * (.5 + .5 * math.sin(TAU * t / 6 + side * .4)) ** 2
            swell += .18 * (.5 + .5 * math.sin(TAU * t / 4 + 1.1))
            channel[i] = (smooth * .5 + slow) * swell
        channels.append(channel)
    write("surf", channels, .28)


if __name__ == "__main__":
    build()
