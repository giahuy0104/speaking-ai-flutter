"""Import the three supplied recordings without altering their bytes."""
import array
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
sys.stdout.reconfigure(encoding='utf-8')
from pathlib import Path

root = Path(__file__).resolve().parents[2]
def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def write(path, data):
    eol = '\r\n' if b'\r\n' in path.read_bytes() else '\n'
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + '\n').replace('\n', eol).encode('utf-8'))
def sha(data):
    return hashlib.sha256(data).hexdigest()

rows = [
    ('assistant.topic.choose_10.vi', 'co-10-chu-de-ban-muon-chon-chu-de-so-may.mp3', 'Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?'),
    ('assistant.topic.course_relearn.vi', 'ban-da-hoan-thanh-khoa-hoc-roi-ban-muon-hoc-lai-chu-de-so-may.mp3', 'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy?'),
    ('assistant.topic.invalid_10.vi', 'ban-chon-chu-de-tu-so-1-den-so-10-nhe.mp3', 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.'),
]
spec = importlib.util.spec_from_file_location('loudness', root / 'tool/measure_audio_loudness.py')
loudness_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loudness_module)
manifest_path = root / 'assets/data/assistant_core_audio.json'
manifest = read(manifest_path)
loudness_path = root / 'assets/data/audio_loudness.json'
loudness = read(loudness_path)
receipts = []
for key, filename, text in rows:
    source = Path('C:/Users/DELL/Downloads') / filename
    asset = f'assets/audio/assistant-core/{key}.mp3'
    destination = root / asset
    if destination.exists() and destination.read_bytes() != source.read_bytes():
        raise RuntimeError(f'Refusing to overwrite different audio: {destination}')
    shutil.copyfile(source, destination)
    data = destination.read_bytes()
    duration = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', str(destination)], text=True))
    samples = array.array('h')
    samples.frombytes(subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(destination), '-f', 's16le', '-ac', '1', '-ar', '16000', '-']))
    gain = round(loudness_module.gain_for(samples), 2)
    loudness['gainDb'][asset] = gain
    entry = {'key': key, 'enabled': True, 'locale': 'vi-VN', 'text': text,
             'asset': asset, 'durationSeconds': duration, 'sha256': sha(data),
             'sizeBytes': len(data), 'textHash': sha(text.encode('utf-8')),
             'source': 'user-provided', 'sourceFilename': filename}
    manifest['prompts'] = [e for e in manifest['prompts'] if e['key'] != key] + [entry]
    receipts.append(dict(entry, gainDb=gain, sourceBytesPreserved=data == source.read_bytes()))
manifest['version'] = 'v3'
write(manifest_path, manifest)
loudness['gainDb'] = dict(sorted(loudness['gainDb'].items()))
write(loudness_path, loudness)
index_path = root / 'assets/data/audio_pack_index.json'
index = read(index_path)
for pack in index['packs']:
    if pack['pack'] == 'assistant-core':
        pack.update(version=manifest['version'], manifestSha256=sha(manifest_path.read_bytes()),
                    audioCount=len(manifest['prompts']), sizeBytes=sum(e['sizeBytes'] for e in manifest['prompts']))
write(index_path, index)
dynamic = root / 'tool/topic_dynamic_audio_prompts.json'
source_text = dynamic.read_bytes().decode('utf-8')
source_text = source_text.replace('Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?', rows[0][2])
source_text = source_text.replace('Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy? Bạn chọn từ số 1 đến số 10.', rows[1][2])
source_text = source_text.replace('Nhóm tuổi này có 10 Chủ đề. Bạn chọn lại nhé.', rows[2][2])
dynamic.write_bytes(source_text.encode('utf-8'))
for rel in ['test/features/voice_navigation/main_voice_assistant_flow_test.dart', 'test/features/voice_navigation/voice_navigation_controller_test.dart']:
    path = root / rel
    text = path.read_bytes().decode('utf-8')
    text = text.replace('Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?', rows[0][2])
    text = text.replace('Nhóm tuổi này có 10 Chủ đề. Bạn chọn lại nhé.', rows[2][2])
    text = text.replace('Bạn chọn Chủ đề 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 nhé.', rows[2][2])
    path.write_bytes(text.encode('utf-8'))
path = root / 'test/features/listening/topic_listening_screen_test.dart'
text = path.read_bytes().decode('utf-8').replace("contains('Bạn chọn Chủ đề số mấy?')", "contains('Bạn chọn Chủ đề số mấy?')")
path.write_bytes(text.encode('utf-8'))
(Path(__file__).parent / 'import-receipts.json').write_text(json.dumps(receipts, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipts, ensure_ascii=False, indent=2))
