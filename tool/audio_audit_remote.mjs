// Read-only production asset probe. No speech generation or uploads.
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
const out = 'deliverables/audio-runtime-audit-2026-09-17';
mkdirSync(out, {recursive: true});
const manifests = ['main_assistant_audio', 'curriculum_audio'].map(name =>
  JSON.parse(readFileSync(`assets/data/${name}.json`, 'utf8')));
const targets = new Map();
for (const p of manifests.flatMap(m => m.prompts)) {
  if (!p.url) continue;
  targets.set(p.url, {url: p.url, id: p.id, text: p.text, locale: p.locale,
    expectedSha256: p.sha256});
}
const cloud = JSON.parse(readFileSync('assets/data/cloudinary_audio_manifest.json', 'utf8'));
for (const [asset, p] of Object.entries(cloud.assets)) {
  if (!p.secureUrl || targets.has(p.secureUrl)) continue;
  targets.set(p.secureUrl, {url: p.secureUrl, asset, expectedSha256: p.sha256});
}
const queue = [...targets.values()];
const results = [];
let index = 0;
async function worker() {
  while (index < queue.length) {
    const target = queue[index++];
    const begin = Date.now();
    try {
      const response = await fetch(target.url, {signal: AbortSignal.timeout(15000)});
      const bytes = Buffer.from(await response.arrayBuffer());
      const actualSha256 = createHash('sha256').update(bytes).digest('hex');
      results.push({...target, status: response.status, elapsedMs: Date.now()-begin,
        bytes: bytes.length, contentType: response.headers.get('content-type'),
        actualSha256, checksumMatches: target.expectedSha256
          ? actualSha256 === target.expectedSha256 : null});
    } catch (error) {
      results.push({...target, elapsedMs: Date.now()-begin,
        error: error.message, cause: error.cause?.code});
    }
    if (results.length % 200 === 0) {
      console.log(`Checked ${results.length}/${queue.length}; failures=${results.filter(r => r.status !== 200 || r.checksumMatches === false).length}`);
    }
  }
}
await Promise.all(Array.from({length: 6}, worker));
results.sort((a,b) => a.url.localeCompare(b.url));
const summary = {at: new Date().toISOString(), environment: 'Windows host network; phone network may differ',
  requests: results.length, http200: results.filter(r=>r.status===200).length,
  checksumVerified: results.filter(r=>r.checksumMatches===true).length,
  overRuntime8Seconds: results.filter(r=>r.elapsedMs>8000).length,
  failures: results.filter(r=>r.status!==200 || r.checksumMatches===false)};
writeFileSync(`${out}/remote-audio-results.json`, JSON.stringify({summary,results},null,2));
console.log(JSON.stringify(summary,null,2));
if(summary.failures.length) process.exitCode=1;
