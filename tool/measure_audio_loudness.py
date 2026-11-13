"""Generate assets/data/audio_loudness.json from the bundled prompt audio.

Why this exists
---------------
Android measures every clip before it plays (`AndroidPlaybackLoudness`) and
brings it to a common level. iOS does not, so the authored catalogue reaches the
child exactly as it was rendered — and the catalogue is not level: Vietnamese
clips sit about 4 dB above the English ones, and the whole set spans ~18 dB. A
child hears the Vietnamese lead, then a noticeably quieter English sentence.

Measuring at runtime would fix that, but it means decoding a clip before it can
play, on the same navigation path that is already reported as slow. The bundled
audio never changes between builds, so it is measured here instead and shipped
as a lookup table. Both platforms then apply the same gain with no decode and no
wait, including on a clip's first play.

The policy below is a deliberate port of `PcmPlaybackLevelMeter` in
android/app/src/main/kotlin/com/innotrik/aispeaking/AndroidPlaybackLoudness.kt:
20 ms windows, an absolute -50 dBFS gate plus a -30 dB relative gate, a
-21 dBFS target and a -1 dBFS sample-peak ceiling. Keep the two in step — a
test asserts the constants match.

Usage
-----
    python3 tool/measure_audio_loudness.py           # regenerate the manifest
    python3 tool/measure_audio_loudness.py --check   # check policy, MP3 bytes and gains

Decoding uses afconvert, which ships with macOS; no extra tooling is required.
The check accepts up to 0.6 dB of decoder drift only when every MP3 byte,
manifest key and policy value matches the committed source.
"""

import argparse
import array
import difflib
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import wave

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_ROOT = os.path.join(REPO, "assets", "audio")
MANIFEST = os.path.join(REPO, "assets", "data", "audio_loudness.json")

# Mirrors AndroidPlaybackLoudness / PcmPlaybackLevelMeter.
TARGET_RMS_DBFS = -21.0
SAMPLE_PEAK_CEILING_DBFS = -1.0
MAX_GAIN_DB = 28.0
WINDOW_HZ = 50  # 20 ms windows
ABSOLUTE_GATE_MEAN_SQUARE = 0.00001  # -50 dBFS
RELATIVE_GATE_RATIO = 1000.0  # -30 dB below the strongest window
MAX_DURATION_MS = 30_000
DECODE_RATE = 16_000
# The same MP3 bytes decode slightly differently across macOS afconvert builds.
# The diagnostic Codemagic run observed a maximum 0.58 dB difference.
DECODER_DRIFT_TOLERANCE_DB = 0.6


def decode(path, scratch):
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", f"LEI16@{DECODE_RATE}", "-c", "1",
         path, scratch],
        check=True,
        capture_output=True,
    )
    with wave.open(scratch, "rb") as handle:
        return array.array("h", handle.readframes(handle.getnframes()))


def amplitude_db(value):
    return 20 * math.log10(value) if value > 0 else -120.0


def power_db(value):
    return 10 * math.log10(value) if value > 0 else -120.0


def gain_for(samples):
    """The gain in dB that brings these samples to the shared target."""
    if not samples:
        return None
    if len(samples) * 1000 // DECODE_RATE > MAX_DURATION_MS:
        # Long songs are played as authored, exactly as Android skips them.
        return None
    window = max(1, DECODE_RATE // WINDOW_HZ)
    windows = []
    peak = 0
    energy = 0.0
    count = 0
    for sample in samples:
        value = sample / 32768.0
        peak = max(peak, abs(value))
        energy += value * value
        count += 1
        if count == window:
            windows.append((energy, count))
            energy = 0.0
            count = 0
    if count:
        windows.append((energy, count))
    if not windows:
        return None
    strongest = max(energy for energy, _ in windows) / window
    gate = max(ABSOLUTE_GATE_MEAN_SQUARE, strongest / RELATIVE_GATE_RATIO)
    active = [(e, c) for e, c in windows if e / window >= gate]
    if not active:
        # Below the absolute gate end to end: noise, not a quiet clip. Android
        # leaves these alone too, so the manifest carries no entry for them.
        return None
    measured = power_db(sum(e for e, _ in active) / sum(c for _, c in active))
    headroom = SAMPLE_PEAK_CEILING_DBFS - amplitude_db(peak)
    return min(TARGET_RMS_DBFS - measured, MAX_GAIN_DB, headroom)


def audio_paths():
    paths = []
    for base, _, names in os.walk(AUDIO_ROOT):
        paths += [os.path.join(base, n) for n in sorted(names)
                  if n.endswith(".mp3")]
    paths.sort(key=lambda path: os.path.relpath(path, REPO).replace(os.sep, "/"))
    return paths


def audio_source_sha256(paths):
    digest = hashlib.sha256()
    for path in paths:
        key = os.path.relpath(path, REPO).replace(os.sep, "/")
        digest.update(key.encode("utf-8"))
        digest.update(b"\0")
        with open(path, "rb") as handle:
            while chunk := handle.read(1024 * 1024):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def gain_db_sha256(gains):
    canonical = json.dumps(gains, sort_keys=True, separators=(",", ":"),
                           ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def manifest_matches(current, measured):
    if not isinstance(current, dict):
        return False
    if (current.get("policy") != measured["policy"] or
            current.get("audioSourceSha256") != measured["audioSourceSha256"]):
        return False
    saved_gains = current.get("gainDb")
    measured_gains = measured["gainDb"]
    if not isinstance(saved_gains, dict) or saved_gains.keys() != measured_gains.keys():
        return False
    if current.get("gainDbSha256") != gain_db_sha256(saved_gains):
        return False
    for key, saved in saved_gains.items():
        actual = measured_gains[key]
        if (isinstance(saved, bool) or not isinstance(saved, (int, float)) or
                not math.isfinite(saved) or not math.isfinite(actual) or
                abs(saved - actual) > DECODER_DRIFT_TOLERANCE_DB + 1e-9):
            return False
    return True


def build(paths):
    entries = {}
    scratch = os.path.join(tempfile.mkdtemp(), "decode.wav")
    for index, path in enumerate(paths, 1):
        key = os.path.relpath(path, REPO).replace(os.sep, "/")
        try:
            gain = gain_for(decode(path, scratch))
        except subprocess.CalledProcessError:
            gain = None
        if gain is not None:
            entries[key] = round(gain, 2)
        if index % 200 == 0:
            print(f"  {index}/{len(paths)}", file=sys.stderr, flush=True)
    return entries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    options = parser.parse_args()

    paths = audio_paths()
    entries = build(paths)
    payload = {
        "policy": {
            "targetRmsDbfs": TARGET_RMS_DBFS,
            "samplePeakCeilingDbfs": SAMPLE_PEAK_CEILING_DBFS,
            "maxGainDb": MAX_GAIN_DB,
            # Published so the drift test can compare the whole policy, not
            # only the three numbers it used to see. A window size or a gate
            # that drifted apart would change every gain in the table while
            # the three headline constants still matched.
            "windowHz": WINDOW_HZ,
            "absoluteGateMeanSquare": ABSOLUTE_GATE_MEAN_SQUARE,
            "relativeGateRatio": RELATIVE_GATE_RATIO,
            "maxDurationMs": MAX_DURATION_MS,
            "decodeRate": DECODE_RATE,
            "measurement": "gated-rms-dbfs",
        },
        "audioSourceSha256": audio_source_sha256(paths),
        "gainDbSha256": gain_db_sha256(entries),
        "gainDb": dict(sorted(entries.items())),
    }
    serialized = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"

    if options.check:
        current = open(MANIFEST, encoding="utf-8").read() if os.path.exists(MANIFEST) else ""
        try:
            saved = json.loads(current)
        except json.JSONDecodeError:
            saved = None
        if not manifest_matches(saved, payload):
            print("assets/data/audio_loudness.json is stale; regenerate it.",
                  file=sys.stderr)
            diff = difflib.unified_diff(
                current.splitlines(), serialized.splitlines(),
                fromfile="committed manifest", tofile="measured audio", lineterm="", n=0,
            )
            for line in diff:
                print(line, file=sys.stderr)
            return 1
        return 0

    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write(serialized)
    values = sorted(entries.values())
    print(f"measured {len(entries)} clips")
    if values:
        print(f"  gain range {values[0]:+.1f} .. {values[-1]:+.1f} dB")
        print(f"  median     {values[len(values) // 2]:+.1f} dB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
