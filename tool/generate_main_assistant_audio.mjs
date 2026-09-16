// Offline, one-prompt-at-a-time production. Never ship the API key in Flutter.
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = resolve(root, 'assets/data/main_assistant_audio.json');
const args = process.argv.slice(2);
const option = (name) => {
  const index = args.indexOf(name);
  return index < 0 ? undefined : args[index + 1];
};
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
let secret = '';

function underRoot(path) {
  const absolute = resolve(root, path);
  const rel = relative(root, absolute);
  if (rel.startsWith('..') || isAbsolute(rel)) throw new Error('Output escapes workspace.');
  return absolute;
}

function duration(path) {
  const seconds = Number(execFileSync('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', path,
  ], { encoding: 'utf8' }).trim());
  if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('Invalid audio duration.');
  return seconds;
}

async function exists(path) {
  try { await access(path); return true; } catch { return false; }
}

async function main() {
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  const id = option('--id');
  if (!id) throw new Error('Specify one prompt: --id AI-001 (dry-run by default).');
  const prompt = manifest.prompts.find((entry) => entry.id === id);
  if (!prompt) throw new Error('Unknown prompt ID. Add and review its text first.');
  const language = prompt.voiceLanguage ?? prompt.locale.split('-')[0];
  const profile = manifest.profiles[language];
  if (!profile || manifest.modelId !== 'eleven_v3') throw new Error('Unsupported generation profile.');
  if (!(profile.speed >= 0.5 && profile.speed <= 2)) throw new Error('Invalid speed.');
  if (/[{}]/u.test(prompt.text)) throw new Error('Render dynamic placeholders before generation.');
  if (!/^[A-Z][A-Z0-9_-]{1,60}$/u.test(id)) throw new Error('Unsafe prompt ID.');
  const target = underRoot(prompt.asset);
  if (!prompt.asset.startsWith('assets/audio/MAIN/') || !target.endsWith('.mp3')) {
    throw new Error('Expected a MAIN MP3 asset.');
  }
  const settings = {
    text: prompt.text,
    model_id: manifest.modelId,
    language_code: language,
    seed: 164109,
    voice_settings: { stability: 0.5, similarity_boost: 0.75,
      // Opt-in so old verified source signatures remain reusable. New batches
      // can explicitly neutralize provider speed before one offline atempo pass.
      ...(args.includes('--neutral-source-speed') || prompt.batch === 'homi-runtime-gap28-2026-09-16'
        ? { speed: 1.0 } : {}),
    },
  };
  const signature = sha256(JSON.stringify({ settings, profile, version: prompt.version }));
  const sourceDir = underRoot('deliverables/main_assistant_audio_sources');
  const source = resolve(sourceDir, `${id}.${language}.v${prompt.version}.${signature.slice(0, 12)}.source.mp3`);
  const receiptPath = `${source}.json`;
  console.log(JSON.stringify({ id, text: prompt.text, model: manifest.modelId,
    voiceId: profile.voiceId, speed: profile.speed,
    speedMethod: 'ffmpeg atempo, pitch-preserving; applied exactly once',
    characters: [...prompt.text].length, target: prompt.asset,
    mode: args.includes('--generate') ? 'generate' : 'dry-run' }, null, 2));
  if (!args.includes('--generate')) return;

  // Check tools before any billable request.
  execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' });
  execFileSync('ffprobe', ['-version'], { stdio: 'ignore' });
  if (await exists(target)) throw new Error('Target exists. Use a new version; never overwrite active audio.');

  let receipt;
  if (await exists(source)) {
    receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
    if (receipt.signature !== signature || receipt.sourceSha256 !== sha256(await readFile(source))) {
      throw new Error('Cached source failed verification.');
    }
    console.log('Reusing the verified source; no new ElevenLabs charge.');
  } else {
    const keyPath = option('--api-key-file');
    if (!keyPath) throw new Error('Provide --api-key-file outside the project.');
    const absoluteKeyPath = resolve(keyPath);
    const relKeyPath = relative(root, absoluteKeyPath);
    if (!relKeyPath.startsWith('..') && !isAbsolute(relKeyPath)) {
      throw new Error('Keep the API key file outside the project.');
    }
    const keyFile = (await readFile(absoluteKeyPath, 'utf8')).trim().replace(/^\uFEFF/u, '');
    const candidates = [...keyFile.matchAll(/\bsk_[a-zA-Z0-9_\-]+\b/gu)].map((m) => m[0]);
    secret = candidates.length === 1 ? candidates[0] : keyFile;
    if (!secret || /\s/u.test(secret)) throw new Error('Expected a single API key in the key file.');
    // A single paid request; do not automatically retry uncertain network failures.
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${profile.voiceId}?output_format=mp3_44100_128`, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(120_000),
      headers: { 'xi-api-key': secret, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
      body: JSON.stringify(settings),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(`ElevenLabs HTTP ${response.status}: ${JSON.stringify(body.detail ?? 'request rejected')}`);
    }
    if (!response.headers.get('content-type')?.includes('audio/')) throw new Error('Expected audio response.');
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length < 1000) throw new Error('Audio response is unexpectedly short.');
    await mkdir(sourceDir, { recursive: true });
    await writeFile(source, bytes, { flag: 'wx' });
    receipt = {
      id, signature, provider: 'elevenlabs', voiceId: profile.voiceId,
      request: settings, createdAt: new Date().toISOString(),
      requestId: response.headers.get('request-id'),
      characterCost: response.headers.get('character-cost'),
      sourceSha256: sha256(bytes),
    };
    await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { flag: 'wx' });
    secret = '';
  }
  await mkdir(dirname(target), { recursive: true });
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-n', '-i', source,
    '-af', `atempo=${profile.speed}`, '-map_metadata', '-1', '-c:a', 'libmp3lame',
    '-b:a', '128k', '-ar', '44100', '-ac', '1', target], { stdio: 'pipe' });
  const sourceDuration = duration(source);
  const outputDuration = duration(target);
  if (Math.abs(outputDuration - sourceDuration / profile.speed) > 0.25) {
    throw new Error('Output duration does not match the requested speed. Keep disabled.');
  }
  const file = await readFile(target);
  receipt = { ...receipt, asset: prompt.asset, finalSha256: sha256(file),
    sourceDurationSeconds: sourceDuration, durationSeconds: outputDuration,
    speed: profile.speed, speedMethod: 'ffmpeg-atempo', bytes: file.length };
  await writeFile(`${target}.json`, `${JSON.stringify(receipt, null, 2)}\n`, { flag: 'wx' });
  console.log(JSON.stringify({ status: 'GENERATED_NOT_ACTIVATED', id,
    asset: prompt.asset, sha256: receipt.finalSha256, durationSeconds: outputDuration,
    sourceDurationSeconds: sourceDuration, speed: profile.speed, bytes: file.length }, null, 2));
}

main().catch((error) => {
  const message = String(error.message ?? error);
  console.error(secret ? message.replaceAll(secret, '[REDACTED]') : message);
  process.exitCode = 1;
});
