"""Inspect Git objects and simulate text integration without changing the checkout."""
import collections
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
REV = 'deb55732ad886c42aa83d0477f24edbfe15c96a1'
def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)
def obj(path, rev=REV):
    return git('show', f'{rev}:{path}')
def parsed(path, rev=REV):
    return json.loads(obj(path, rev))
def sha(data):
    return hashlib.sha256(data).hexdigest()

changed = [line.split('\t') for line in git('diff-tree', '--no-commit-id', '--name-status', '-r', REV).decode().splitlines()]
mp3 = [p for s, p in changed if s != 'D' and p.endswith('.mp3')]
deleted = [p for s, p in changed if s == 'D']
dirty = set(git('diff', '--name-only', 'HEAD', '--', 'assets', 'lib', 'test', 'tool').decode().splitlines())
overlap = sorted(dirty.intersection(p for s, p in changed))

simulations = []
for label, extra in [('single_commit', [f'--merge-base={REV}^']), ('whole_history', [])]:
    run = subprocess.run(['git', 'merge-tree', '--write-tree', '--name-only', *extra, 'HEAD', REV], cwd=ROOT, capture_output=True)
    text = run.stdout.decode('utf-8', errors='replace')
    (OUT / f'{label}-simulation.txt').write_text(text, encoding='utf-8')
    lines = text.split('\n\n', 1)[0].splitlines()
    simulations.append({'method': label, 'exitCode': run.returncode, 'conflicts': lines[1:]})

working_conflicts = []
for path in overlap:
    with tempfile.TemporaryDirectory(prefix='homi-merge-check-') as tmp:
        ours, base, theirs = [Path(tmp) / x for x in ['ours', 'base', 'theirs']]
        ours.write_bytes((ROOT / path).read_bytes().replace(b'\r\n', b'\n'))
        base.write_bytes(obj(path, f'{REV}^').replace(b'\r\n', b'\n'))
        theirs.write_bytes(obj(path).replace(b'\r\n', b'\n'))
        run = subprocess.run(['git', 'merge-file', '-p', str(ours), str(base), str(theirs)], capture_output=True)
        if run.returncode:
            working_conflicts.append({'path': path, 'conflictHunks': run.returncode})

index = parsed('assets/data/audio_pack_index.json')
manifests = [p['manifest'] for p in index['packs']] + ['assets/data/homi_gap66_audio.json']
entries = []
index_errors = []
for pack in index['packs']:
    raw = obj(pack['manifest'])
    if sha(raw) != pack['manifestSha256']:
        index_errors.append({'pack': pack['pack'], 'error': 'manifestSha256'})
for path in manifests:
    for prompt in parsed(path)['prompts']:
        entries.append(dict(prompt, manifest=path))
assets = sorted({p['asset'] for p in entries if p.get('asset')})
batch = subprocess.Popen(['git', 'cat-file', '--batch'], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
checksums = {}
missing = []
for asset in assets:
    batch.stdin.write(f'{REV}:{asset}\n'.encode())
    batch.stdin.flush()
    header = batch.stdout.readline().decode().strip().split()
    if header[-1] == 'missing':
        missing.append(asset)
        continue
    length = int(header[2])
    raw = batch.stdout.read(length)
    batch.stdout.read(1)
    checksums[asset] = (sha(raw), length)
batch.stdin.close()
batch.wait()
integrity_errors = []
for p in entries:
    actual = checksums.get(p.get('asset'))
    if actual is None or actual[0] != p.get('sha256') or (p.get('sizeBytes') is not None and actual[1] != p['sizeBytes']):
        integrity_errors.append({'key': p.get('key', p.get('id')), 'asset': p.get('asset')})

deleted_runtime_keys = []
for path in manifests:
    local = ROOT / path
    if not local.exists():
        continue
    for p in json.loads(local.read_text(encoding='utf-8-sig'))['prompts']:
        if p.get('asset') in deleted:
            deleted_runtime_keys.append({'key': p.get('key'), 'enabled': p.get('enabled', True), 'asset': p['asset']})
level_active = [{'key': p.get('key', p.get('id')), 'text': p.get('text')} for p in entries if p.get('enabled', True) and ('Level' in p.get('text', '') or '.level.' in p.get('key', ''))]
target_topics = [{k: p.get(k) for k in ['key', 'text', 'asset', 'sha256', 'enabled']} for p in entries if p.get('key') in ['assistant.topic.choose_10.vi', 'assistant.topic.invalid_10.vi', 'assistant.topic.choose_course_relearn.vi', 'assistant.topic.course_relearn.vi']]
gains = json.loads((ROOT / 'assets/data/audio_loudness.json').read_text())['gainDb']
gain_impacted = [p for p in mp3 if p in gains]
result = {
    'revision': REV, 'parent': git('rev-parse', f'{REV}^').decode().strip(),
    'head': git('rev-parse', 'HEAD').decode().strip(),
    'divergenceHeadTarget': git('rev-list', '--left-right', '--count', f'HEAD...{REV}').decode().strip(),
    'changedFiles': len(changed), 'changedAudio': len(mp3), 'deletedAudio': deleted,
    'nonAudioChanged': [p for s, p in changed if not p.endswith('.mp3')],
    'dirtyOverlap': overlap, 'simulations': simulations, 'workingTreeConflicts': working_conflicts,
    'targetIntegrity': {'manifests': len(manifests), 'promptEntries': len(entries), 'uniqueAssetsChecked': len(assets), 'missing': missing, 'indexErrors': index_errors, 'assetErrors': integrity_errors},
    'deletedKeysInWorkingTree': deleted_runtime_keys,
    'enabledLevelKeysInTarget': level_active, 'targetTopicPrompts': target_topics,
    'changedAudioWithExistingLoudnessGain': len(gain_impacted),
    'loudnessManifestUpdatedInCommit': any(p == 'assets/data/audio_loudness.json' for s, p in changed),
    'curriculumSameAsWorkingTree': obj('assets/data/listening_lessons.json').replace(b'\r\n', b'\n') == (ROOT / 'assets/data/listening_lessons.json').read_bytes().replace(b'\r\n', b'\n'),
}
(OUT / 'review.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k: result[k] for k in ['changedFiles', 'changedAudio', 'dirtyOverlap', 'simulations', 'workingTreeConflicts', 'targetIntegrity', 'changedAudioWithExistingLoudnessGain', 'loudnessManifestUpdatedInCommit', 'curriculumSameAsWorkingTree']}, ensure_ascii=True, indent=2))
