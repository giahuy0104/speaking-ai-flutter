"""Read-only inventory audit; writes evidence only in this folder."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
folder = Path(__file__).resolve().parent
entries = []
for name in ['assistant_core_audio', 'listening_common_audio', 'homi_gap66_audio']:
    manifest = json.loads((root / f'assets/data/{name}.json').read_text(encoding='utf-8-sig'))
    for entry in manifest['prompts']:
        entries.append(dict(entry, manifest=name, packEnabled=manifest.get('enabled', True)))
active = [e for e in entries if e['packEnabled'] and e.get('enabled', True)]
errors = []
for e in active:
    asset = e.get('asset')
    if not asset:
        continue
    path = root / asset
    if not path.is_file():
        errors.append({'key': e.get('key', e.get('id')), 'error': 'missing asset'})
    elif hashlib.sha256(path.read_bytes()).hexdigest() != e['sha256']:
        errors.append({'key': e.get('key', e.get('id')), 'error': 'checksum mismatch'})
level = [e for e in entries if 'level' in str(e.get('key', '')).lower() or 'Level' in str(e.get('text', ''))]
result = {
    'manifests': 3,
    'activeEntries': len(active),
    'assetErrors': errors,
    'levelEntries': [{'key': e.get('key', e.get('id')), 'enabled': e.get('enabled', True), 'text': e.get('text')} for e in level],
    'activeLevelEntries': sum(e.get('enabled', True) and e['packEnabled'] for e in level),
}
domain = folder / 'domain-utterances.json'
if domain.is_file():
    data = json.loads(domain.read_text(encoding='utf-8'))
    result['domainSummary'] = {k: v for k, v in data.items() if k != 'rows'}
    result['currentLevelUtterances'] = [r for r in data['rows'] if r['scope'] == 'current' and 'Level' in r['text']]
(folder / 'inventory.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps({k: v for k, v in result.items() if k != 'levelEntries'}, ensure_ascii=False))
