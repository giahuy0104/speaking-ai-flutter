// Create one standalone HOMI Vietnamese MP3. This never modifies Flutter assets.
// Example: node tool/generate_homi_prompt_preview.mjs --name my-prompt --text "..." --generate --api-key-file C:/outside/key.txt
import {readFileSync, writeFileSync, mkdirSync, existsSync} from 'node:fs';
import {resolve, relative, isAbsolute, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
const name = option('--name');
const text = option('--text')?.trim();
const generate = args.includes('--generate');
const voiceId = '5CVDNcIPiOYgRUQuxXd7';
const speed = 0.9;
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const check = (ok, message) => { if (!ok) throw Error(message); };
const output = `deliverables/homi-prompt-previews/${name}`;
const file = path => resolve(root, output, path);
const source = file('source.mp3');
const final = file('homi.vi.mp3');
const receiptPath = file('receipt.json');
const attemptPath = file('request-attempt.json');
const request = {
  text, model_id: 'eleven_v3', language_code: 'vi', seed: 164109,
  voice_settings: {stability: 0.5, similarity_boost: 0.75, speed: 1.0},
};
const duration = path => Number(execFileSync('ffprobe', [
  '-v', 'error', '-show_entries', 'format=duration',
  '-of', 'default=noprint_wrappers=1:nokey=1', path,
], {encoding: 'utf8'}).trim());
const decode = path => execFileSync('ffmpeg', [
  '-hide_banner', '-v', 'error', '-i', path, '-f', 'null', '-',
], {stdio: 'pipe'});

function key() {
  const input = option('--api-key-file');
  check(input, 'Provide --api-key-file outside the workspace.');
  const path = resolve(input);
  const rel = relative(root, path);
  check(rel.startsWith('..') || isAbsolute(rel), 'Key file must be outside the workspace.');
  const contents = readFileSync(path, 'utf8').replace(/^\uFEFF/u, '').trim();
  const matches = [...contents.matchAll(/\bsk_[a-zA-Z0-9_-]+\b/g)].map(match => match[0]);
  const secret = matches.length === 1 ? matches[0] : contents;
  check(secret.length >= 20 && !/\s/u.test(secret), 'Expected one API key.');
  return secret;
}

async function main() {
  check(name && /^[a-z0-9][a-z0-9-]{1,63}$/.test(name), 'Use a lowercase hyphenated --name.');
  check(text && text.length <= 500 && !/[{}]/u.test(text), 'Provide one fixed --text under 500 characters.');
  check(!existsSync(final) && !existsSync(source) && !existsSync(receiptPath) && !existsSync(attemptPath),
    'Preview already exists or a request was attempted; never overwrite or retry automatically.');
  console.log(JSON.stringify({name, text, target: `${output}/homi.vi.mp3`,
    voiceId, modelId: 'eleven_v3', speed, mode: generate ? 'generate' : 'dry-run'}));
  if (!generate) return;
  execFileSync('ffmpeg', ['-version'], {stdio: 'ignore'});
  execFileSync('ffprobe', ['-version'], {stdio: 'ignore'});
  const secret = key();
  mkdirSync(file('.'), {recursive: true});
  writeFileSync(attemptPath, `${JSON.stringify({text, status: 'request-started', at: new Date().toISOString()}, null, 2)}\n`, {flag: 'wx'});
  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(120000),
    headers: {'xi-api-key': secret, 'Content-Type': 'application/json', Accept: 'audio/mpeg'},
    body: JSON.stringify(request),
  });
  check(response.ok, `ElevenLabs HTTP ${response.status}; no automatic retry.`);
  check(response.headers.get('content-type')?.includes('audio/'), 'Provider returned non-audio data.');
  const bytes = Buffer.from(await response.arrayBuffer());
  check(bytes.length > 1000, 'Provider audio is unexpectedly short.');
  writeFileSync(source, bytes, {flag: 'wx'});
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-n', '-i', source,
    '-af', `atempo=${speed}`, '-map_metadata', '-1', '-c:a', 'libmp3lame',
    '-b:a', '128k', '-ar', '44100', '-ac', '1', final,
  ], {stdio: 'pipe'});
  decode(final);
  const outputBytes = readFileSync(final);
  const sourceDurationSeconds = duration(source);
  const durationSeconds = duration(final);
  check(outputBytes.length > 1000 && outputBytes.length <= 2 * 1024 * 1024 &&
    durationSeconds > 0 && durationSeconds <= 45 &&
    Math.abs(durationSeconds - sourceDurationSeconds / speed) <= 0.25,
    'Generated MP3 failed duration or size validation.');
  const receipt = {provider: 'elevenlabs', voiceId, request,
    requestId: response.headers.get('request-id'),
    characterCost: response.headers.get('character-cost'),
    sourceSha256: hash(bytes), finalSha256: hash(outputBytes),
    sourceDurationSeconds, durationSeconds, speed, speedMethod: 'ffmpeg-atempo',
    bytes: outputBytes.length, createdAt: new Date().toISOString()};
  writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  console.log(JSON.stringify({status: 'ready', target: `${output}/homi.vi.mp3`,
    sha256: receipt.finalSha256, durationSeconds, bytes: outputBytes.length,
    characterCost: receipt.characterCost}));
}

main().catch(error => {
  // Never print credentials, provider bodies, or request headers.
  console.error(error instanceof Error ? error.message : 'Audio generation failed.');
  process.exitCode = 1;
});
