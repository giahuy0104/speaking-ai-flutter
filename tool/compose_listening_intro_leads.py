"""Compose hook-intro leads offline from the original VI/EN speech cache.

Requires ffmpeg/ffprobe and build/listening-common-tts-cache. Before adding any
assets, reconstructs each full intro and verifies its decoded audio against the
bundled original, so stale or unrelated cache recordings cannot be imported.
No API calls or new speech synthesis. Run from any directory.
"""
import array
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, value):
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def sha(value):
    return hashlib.sha256(value).hexdigest()


def normalize(value):
    return re.sub(r"\s+", " ", value).strip()


def cached(language, text):
    path = ROOT / "build/listening-common-tts-cache" / (
        sha(f"{language}|{normalize(text)}".encode()) + ".mp3")
    if not path.is_file():
        raise RuntimeError(f"Missing original cached segment: {path}")
    return path


def compose(segments, output):
    listing = output.with_suffix(".concat.txt")
    listing.write_text("\n".join(
        "file '" + p.as_posix().replace("'", "'\\''") + "'" for p in segments
    ) + "\n", encoding="utf-8")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0",
                    "-i", str(listing), "-ar", "44100", "-b:a", "128k", str(output)],
                   check=True, capture_output=True)


def pcm(path, rate=44100):
    return subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path),
                                    "-f", "s16le", "-ac", "1", "-ar", str(rate), "-"])


def main():
    manifest_path = ROOT / "assets/data/listening_common_audio.json"
    manifest = read(manifest_path)
    by_key = {entry["key"]: entry for entry in manifest["prompts"]}
    catalog = read(ROOT / "assets/data/listening_lessons.json")
    spec = importlib.util.spec_from_file_location("loudness", ROOT / "tool/measure_audio_loudness.py")
    meter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(meter)
    loudness_path = ROOT / "assets/data/audio_loudness.json"
    loudness = read(loudness_path)
    receipts = []
    pending = []
    with tempfile.TemporaryDirectory(prefix="listening-intro-leads-") as scratch:
        for group in catalog["groups"]:
            for topic in group["topics"]:
                for lesson in topic["lessons"]:
                    prefix = f"listening.lesson.{lesson['id']}"
                    hook = by_key.get(prefix + ".hook.vi")
                    if not hook or not hook.get("enabled", True):
                        continue
                    if lesson.get("entry", {}).get("kind") != "hook":
                        raise RuntimeError(f"Unexpected hook entry: {prefix}")
                    before = (f"Chủ đề {topic['number']}. Bài đầu tiên là"
                              if lesson["number"] == 1 else "Bài này là")
                    title = normalize(lesson["titleEn"])
                    after = normalize(lesson["entry"]["text"] + " Bắt đầu nhé.")
                    segments = [cached("vi", before), cached("en", title), cached("vi", after)]
                    original = by_key[prefix + ".intro.vi"]
                    original_path = ROOT / original["asset"]
                    if sha(original_path.read_bytes()) != original["sha256"]:
                        raise RuntimeError(f"Original intro checksum mismatch: {prefix}")
                    reconstructed = Path(scratch) / (prefix + ".full.mp3")
                    compose(segments, reconstructed)
                    if pcm(reconstructed) != pcm(original_path):
                        raise RuntimeError(f"Cached segments do not reproduce original intro: {prefix}")
                    key = prefix + ".intro_lead.vi"
                    lead = Path(scratch) / (key + ".mp3")
                    compose(segments[:2], lead)
                    data = lead.read_bytes()
                    asset = f"assets/audio/listening-common/{key}.mp3"
                    duration = float(subprocess.check_output([
                        "ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "default=noprint_wrappers=1:nokey=1", str(lead)], text=True))
                    samples = array.array("h")
                    samples.frombytes(pcm(lead, 16000))
                    gain = round(meter.gain_for(samples), 2)
                    text = normalize(before + " " + title)
                    entry = dict(key=key, enabled=True, locale="vi-VN", text=text,
                                 asset=asset, durationSeconds=round(duration, 3),
                                 sha256=sha(data), sizeBytes=len(data), textHash=sha(text.encode()),
                                 composition="vi-en", source="original-intro-segments",
                                 sourceIntroSha256=original["sha256"])
                    pending.append((entry, data, gain))
                    receipts.append(dict(entry, gainDb=gain, originalAudioVerified=True,
                                         segmentSha256=[sha(p.read_bytes()) for p in segments[:2]]))

        if not pending:
            raise RuntimeError("No authored hooks found; nothing to compose.")
        for entry, data, gain in pending:
            (ROOT / entry["asset"]).write_bytes(data)
            loudness["gainDb"][entry["asset"]] = gain
            manifest["prompts"] = [p for p in manifest["prompts"] if p["key"] != entry["key"]]
            manifest["prompts"].append(entry)
    if manifest.get("version") in (None, "v1"):
        manifest["version"] = "v2"
    write(manifest_path, manifest)
    loudness["gainDb"] = dict(sorted(loudness["gainDb"].items()))
    write(loudness_path, loudness)
    index_path = ROOT / "assets/data/audio_pack_index.json"
    index = read(index_path)
    assets = {p["asset"] for p in manifest["prompts"] if p.get("asset")}
    for pack in index["packs"]:
        if pack["pack"] == manifest["pack"]:
            pack.update(version=manifest["version"], manifestSha256=sha(manifest_path.read_bytes()),
                        audioCount=len(manifest["prompts"]),
                        sizeBytes=sum((ROOT / asset).stat().st_size for asset in assets))
    write(index_path, index)
    report = ROOT / "output/intro-audio-fix"
    report.mkdir(parents=True, exist_ok=True)
    write(report / "composition-receipts.json", receipts)
    print(f"Composed {len(receipts)} verified intro leads; updated manifest, index and loudness.")


if __name__ == "__main__":
    main()
