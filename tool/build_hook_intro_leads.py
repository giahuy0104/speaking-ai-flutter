"""Compose hook intro leads from existing recordings; never synthesizes speech.

Requires ffmpeg/ffprobe and the original build/listening-common-tts-cache.
The generated MP3s are bundled; the cache is not needed at runtime.
"""
import array
import hashlib
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def save(path, data):
    staged = path.with_suffix('.json.tmp')
    staged.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')
    staged.replace(path)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    manifest_path = ROOT / 'assets/data/listening_common_audio.json'
    manifest = read(manifest_path)
    hooks = {p['key']: p for p in manifest['prompts'] if '.hook.vi' in p['key']}
    hook_hashes = {p['asset']: sha((ROOT / p['asset']).read_bytes()) for p in hooks.values()}
    jobs = []
    for group in read(ROOT / 'assets/data/listening_lessons.json')['groups']:
        for topic in group['topics']:
            for lesson in topic['lessons']:
                if f"listening.lesson.{lesson['id']}.hook.vi" not in hooks:
                    continue
                prefix = (f"Chủ đề {topic['number']}. Bài đầu tiên là"
                          if lesson['number'] == 1 else 'Bài này là')
                title = lesson['titleEn'].strip()
                parts = [ROOT / 'build/listening-common-tts-cache' /
                         (sha(f'{language}|{text}'.encode()) + '.mp3')
                         for language, text in [('vi', prefix), ('en', title)]]
                for part in parts:
                    if not part.is_file():
                        raise FileNotFoundError(part)
                jobs.append((lesson['id'], f'{prefix} {title}', parts))
    assert len(jobs) == 13
    loudness_path = ROOT / 'assets/data/audio_loudness.json'
    loudness = read(loudness_path) if loudness_path.exists() else None
    if loudness is not None:
        from measure_audio_loudness import gain_for
    with tempfile.TemporaryDirectory(prefix='hook-intro-leads-') as scratch:
        for lesson_id, text, parts in jobs:
            key = f'listening.lesson.{lesson_id}.intro_lead.vi'
            asset = f'assets/audio/listening-common/{key}.mp3'
            output = ROOT / asset
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(parts[0]),
                            '-i', str(parts[1]), '-filter_complex',
                            '[0:a][1:a]concat=n=2:v=0:a=1[out]', '-map', '[out]',
                            '-ar', '44100', '-b:a', '128k', str(output)], check=True)
            duration = float(subprocess.check_output([
                'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                '-of', 'default=noprint_wrappers=1:nokey=1', str(output)]))
            data = output.read_bytes()
            entry = dict(key=key, enabled=True, locale='vi-VN', text=text,
                         asset=asset, durationSeconds=round(duration, 6),
                         sha256=sha(data), sizeBytes=len(data), textHash=sha(text.encode()),
                         composition='vi-en',
                         sourceSegments=[dict(sha256=sha(p.read_bytes())) for p in parts])
            manifest['prompts'] = [p for p in manifest['prompts'] if p['key'] != key]
            manifest['prompts'].append(entry)
            if loudness is not None:
                samples = array.array('h')
                samples.frombytes(subprocess.check_output([
                    'ffmpeg', '-v', 'error', '-i', str(output), '-ac', '1', '-ar', '16000',
                    '-f', 's16le', '-']))
                loudness['gainDb'][asset] = round(gain_for(samples), 2)
    save(manifest_path, manifest)
    if loudness is not None:
        loudness['gainDb'] = dict(sorted(loudness['gainDb'].items()))
        save(loudness_path, loudness)
    index_path = ROOT / 'assets/data/audio_pack_index.json'
    index = read(index_path)
    for pack in index['packs']:
        if pack['pack'] == 'listening-common':
            pack['manifestSha256'] = sha(manifest_path.read_bytes())
            pack['audioCount'] = len(manifest['prompts'])
            pack['sizeBytes'] = sum((ROOT / a).stat().st_size for a in
                                    {p['asset'] for p in manifest['prompts']})
    save(index_path, index)
    assert all(sha((ROOT / a).read_bytes()) == h for a, h in hook_hashes.items())
    print(f'Built {len(jobs)} intro leads; all hook files unchanged.')

if __name__ == '__main__':
    main()
