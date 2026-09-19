// Fixed MAIN replies only. prepare -> check-account -> generate -> verify -> install.
// No application code or existing audio is changed by this tool.
import {readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, constants} from 'node:fs';
import {resolve, dirname, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const mode = args[0] ?? 'dry-run';
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
const out = 'deliverables/homi-gap19-2026-09-19';
const auditPath = 'deliverables/audio-runtime-audit-2026-09-19/homi-speech-audit-summary.json';
const manifestPath = 'assets/data/homi_gap19_audio.json';
const voiceId = '5CVDNcIPiOYgRUQuxXd7';
const speed = 0.9;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const absolute = path => resolve(root, path);
const read = path => readFileSync(absolute(path));
const json = path => JSON.parse(read(path).toString('utf8'));
const check = (ok, message) => { if (!ok) throw Error(message); };
const create = (path, value) => {
  const target = absolute(path);
  mkdirSync(dirname(target), {recursive: true});
  writeFileSync(target, Buffer.isBuffer(value) || typeof value === 'string'
    ? value : `${JSON.stringify(value, null, 2)}\n`, {flag: 'wx'});
};
const paths = entry => ({
  source: `${out}/sources/${entry.id}.mp3`,
  sourceReceipt: `${out}/sources/${entry.id}.json`,
  attempt: `${out}/attempts/${entry.id}.json`,
  ready: `${out}/ready/${entry.id}.mp3`,
  readyReceipt: `${out}/ready/${entry.id}.json`,
});
const requestFor = entry => ({
  text: entry.text,
  model_id: 'eleven_v3',
  language_code: 'vi',
  seed: 164109,
  voice_settings: {stability: 0.5, similarity_boost: 0.75, speed: 1.0},
});
const duration = path => Number(execFileSync('ffprobe', [
  '-v', 'error', '-show_entries', 'format=duration',
  '-of', 'default=noprint_wrappers=1:nokey=1', absolute(path),
], {encoding: 'utf8'}).trim());
const decode = path => execFileSync('ffmpeg', [
  '-hide_banner', '-v', 'error', '-i', absolute(path), '-f', 'null', '-',
], {stdio: 'pipe'});

function key() {
  const path = option('--api-key-file');
  check(path, 'Provide --api-key-file outside the workspace.');
  const resolved = resolve(path);
  const rel = relative(root, resolved);
  check(rel.startsWith('..') || isAbsolute(rel), 'Keep the API key outside the workspace.');
  const content = readFileSync(resolved, 'utf8').replace(/^\uFEFF/u, '').trim();
  const matches = [...content.matchAll(/\bsk_[a-zA-Z0-9_-]+\b/g)].map(match => match[0]);
  const secret = matches.length === 1 ? matches[0] : content;
  check(secret.length >= 20 && !/\s/u.test(secret), 'Expected one API key.');
  return secret;
}

function plan() {
  const value = json(`${out}/plan.json`);
  check(value.auditSha256 === hash(read(auditPath)), 'Current audit changed; review the batch again.');
  check(value.prompts.length === 19 && new Set(value.prompts.map(p => p.text)).size === 19,
    'Expected exactly 19 unique reviewed replies.');
  for (const item of value.protectedFiles) {
    check(hash(read(item.path)) === item.sha256, `Protected source changed: ${item.path}`);
  }
  return value;
}

function verify(entry) {
  const path = paths(entry);
  const source = read(path.source);
  const final = read(path.ready);
  const sourceReceipt = json(path.sourceReceipt);
  const receipt = json(path.readyReceipt);
  check(JSON.stringify(sourceReceipt.request) === JSON.stringify(requestFor(entry)) &&
    sourceReceipt.voiceId === voiceId && sourceReceipt.sourceSha256 === hash(source) &&
    receipt.finalSha256 === hash(final) && receipt.sourceSha256 === hash(source) &&
    receipt.speed === speed && receipt.speedMethod === 'ffmpeg-atempo' &&
    final.length > 1000 && final.length <= 2 * 1024 * 1024 &&
    receipt.durationSeconds > 0 && receipt.durationSeconds <= 45 &&
    Math.abs(receipt.durationSeconds - receipt.sourceDurationSeconds / speed) <= 0.25,
    `Invalid audio or receipt: ${entry.id}`);
  decode(path.ready);
  return receipt;
}

async function generate(entry, secret) {
  const path = paths(entry);
  if (existsSync(absolute(path.readyReceipt))) return verify(entry);
  const request = requestFor(entry);
  if (!existsSync(absolute(path.sourceReceipt))) {
    check(!existsSync(absolute(path.attempt)), `Uncertain prior request for ${entry.id}; inspect provider history before retrying.`);
    create(path.attempt, {id: entry.id, status: 'request-started', at: new Date().toISOString()});
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(120000),
      headers: {'xi-api-key': secret, 'Content-Type': 'application/json', Accept: 'audio/mpeg'},
      body: JSON.stringify(request),
    });
    check(response.ok, `ElevenLabs HTTP ${response.status} for ${entry.id}; stopped without retry.`);
    check(response.headers.get('content-type')?.includes('audio/'), `Non-audio response for ${entry.id}.`);
    const bytes = Buffer.from(await response.arrayBuffer());
    check(bytes.length > 1000, `Short audio response for ${entry.id}.`);
    create(path.source, bytes);
    create(path.sourceReceipt, {
      id: entry.id, provider: 'elevenlabs', voiceId, request,
      requestId: response.headers.get('request-id'),
      historyItemId: response.headers.get('history-item-id'),
      characterCost: response.headers.get('character-cost'),
      sourceSha256: hash(bytes), createdAt: new Date().toISOString(),
    });
  }
  const sourceReceipt = json(path.sourceReceipt);
  check(JSON.stringify(sourceReceipt.request) === JSON.stringify(request) &&
    sourceReceipt.voiceId === voiceId && sourceReceipt.sourceSha256 === hash(read(path.source)),
    `Cached source mismatch: ${entry.id}`);
  check(!existsSync(absolute(path.ready)), `Unreceipted output exists: ${entry.id}`);
  mkdirSync(dirname(absolute(path.ready)), {recursive: true});
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-n', '-i', absolute(path.source),
    '-af', `atempo=${speed}`, '-map_metadata', '-1', '-c:a', 'libmp3lame',
    '-b:a', '128k', '-ar', '44100', '-ac', '1', absolute(path.ready),
  ], {stdio: 'pipe'});
  create(path.readyReceipt, {
    ...sourceReceipt, asset: entry.asset, finalSha256: hash(read(path.ready)),
    sourceDurationSeconds: duration(path.source), durationSeconds: duration(path.ready),
    speed, speedMethod: 'ffmpeg-atempo', bytes: read(path.ready).length,
  });
  return verify(entry);
}

async function main() {
  if (mode === 'prepare') {
    check(!existsSync(absolute(`${out}/plan.json`)), 'Plan already exists.');
    const audit = json(auditPath);
    check(audit.currentMissing.length === 19 && audit.currentMissing.every(p => p.locale === 'vi-VN'),
      'Expected 19 missing Vietnamese replies.');
    const protectedPaths = [...new Set([
      auditPath,
      'assets/data/main_assistant_audio.json',
      'assets/data/curriculum_audio.json',
      'assets/data/homi_gap66_audio.json',
      ...audit.currentMissing.flatMap(item => item.evidence.map(e => e.source)),
    ])];
    const prompts = audit.currentMissing.map((item, index) => {
      const id = `GAP19-${String(index + 1).padStart(3, '0')}`;
      return {id, text: item.text, locale: 'vi-VN', voiceLanguage: 'vi', version: 1,
        enabled: true, group: 'gap19-fixed', asset: `assets/audio/MAIN/GAP19/${id}.vi.v1.mp3`,
        sources: [...new Set(item.evidence.map(e => e.source))]};
    });
    create(`${out}/plan.json`, {
      schemaVersion: 1, provider: 'elevenlabs', modelId: 'eleven_v3', voiceId, speed,
      auditSha256: hash(read(auditPath)),
      characters: prompts.reduce((count, entry) => count + [...entry.text].length, 0),
      protectedFiles: protectedPaths.map(path => ({path, sha256: hash(read(path))})), prompts,
    });
    console.log(JSON.stringify({mode, prompts: prompts.length, characters: prompts.reduce((n,p) => n + [...p.text].length, 0)}));
    return;
  }
  const batch = plan();
  if (mode === 'check-account') {
    const response = await fetch('https://api.elevenlabs.io/v1/user/subscription', {
      headers: {'xi-api-key': key()}, redirect: 'error', signal: AbortSignal.timeout(20000),
    });
    const body = await response.json().catch(() => ({}));
    console.log(JSON.stringify({httpStatus: response.status, requiredCharacters: batch.characters,
      remainingCharacters: typeof body.character_limit === 'number' && typeof body.character_count === 'number'
        ? body.character_limit - body.character_count : null}));
    return;
  }
  if (mode === 'generate') {
    execFileSync('ffmpeg', ['-version'], {stdio: 'ignore'});
    execFileSync('ffprobe', ['-version'], {stdio: 'ignore'});
    const secret = key();
    for (const [index, entry] of batch.prompts.entries()) {
      const receipt = await generate(entry, secret);
      console.log(JSON.stringify({ready: index + 1, total: batch.prompts.length,
        id: entry.id, durationSeconds: receipt.durationSeconds, characterCost: receipt.characterCost}));
    }
    return;
  }
  if (mode === 'verify' || mode === 'install') {
    const receipts = batch.prompts.map(entry => verify(entry));
    if (mode === 'install') {
      check(!existsSync(absolute(manifestPath)), 'Live GAP19 manifest already exists.');
      for (const [index, entry] of batch.prompts.entries()) {
        const target = absolute(entry.asset);
        mkdirSync(dirname(target), {recursive: true});
        copyFileSync(absolute(paths(entry).ready), target, constants.COPYFILE_EXCL);
        Object.assign(entry, {sha256: receipts[index].finalSha256,
          durationSeconds: receipts[index].durationSeconds, voiceId, speed, speedMethod: 'ffmpeg-atempo'});
      }
      create(manifestPath, {schemaVersion: 1, enabled: true, provider: 'elevenlabs',
        modelId: 'eleven_v3', profiles: {vi: {voiceId, speed}}, prompts: batch.prompts});
    }
    console.log(JSON.stringify({mode, verified: receipts.length,
      totalBytes: receipts.reduce((sum, receipt) => sum + receipt.bytes, 0)}));
    return;
  }
  console.log(JSON.stringify({mode: 'dry-run', prompts: batch.prompts.length, characters: batch.characters}));
}

main().catch(error => {
  // No provider body, headers, or key are included in this error path.
  console.error(error instanceof Error ? error.message : 'Audio production failed.');
  process.exitCode = 1;
});
