// Sequential generation + atomic per-sentence activation; no uncertain retries.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { rename } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const path = resolve(root, 'assets/data/main_assistant_audio.json');
const manifest = JSON.parse(readFileSync(path, 'utf8'));
const args = process.argv.slice(2);
const keyIndex = args.indexOf('--api-key-file');
const keyPath = keyIndex >= 0 ? args[keyIndex + 1] : null;
const idIndex = args.indexOf('--id');
const selectedId = idIndex >= 0 ? args[idIndex + 1] : null;
const generate = args.includes('--generate');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const selectedEntries = selectedId
  ? manifest.prompts.filter(entry => entry.id === selectedId)
  : manifest.prompts;
if (selectedId && selectedEntries.length !== 1) throw new Error(`Unknown prompt ID: ${selectedId}`);
let completed = 0;
let created = 0;
for (const entry of selectedEntries) {
  const target = resolve(root, entry.asset);
  if (!generate) { console.log(`${entry.id}: ${existsSync(target) ? 'REUSE' : 'GENERATE'}`); continue; }
  if (!existsSync(target)) {
    if (!keyPath) throw new Error('Provide --api-key-file.');
    try {
      const generationArgs = [resolve(root, 'tool/generate_main_assistant_audio.mjs'),
        '--id', entry.id, '--generate', '--api-key-file', keyPath];
      if (entry.batch?.startsWith('homi-runtime-gap')) generationArgs.push('--neutral-source-speed');
      execFileSync(process.execPath, generationArgs, { cwd: root, stdio: 'pipe' });
      created++;
    } catch (error) {
      console.error(`STOPPED at ${entry.id}; completed ${completed}. No automatic retry.`);
      console.error(error.stderr?.toString() ?? 'Generation failed. Check provider history before retrying.');
      process.exitCode = 1;
      break;
    }
  }
  const receipt = JSON.parse(readFileSync(`${target}.json`, 'utf8'));
  const profile = manifest.profiles[entry.voiceLanguage ?? entry.locale.split('-')[0]];
  if (receipt.request.text !== entry.text || receipt.voiceId !== profile.voiceId ||
      receipt.request.model_id !== 'eleven_v3' || receipt.speed !== profile.speed ||
      receipt.finalSha256 !== hash(readFileSync(target)) || receipt.durationSeconds <= 0 || receipt.durationSeconds > 45) {
    throw new Error(`Verification failed: ${entry.id}. Not activating.`);
  }
  // Decode the entire output, not only its MP3 header. Never activate broken data.
  execFileSync('ffmpeg', ['-hide_banner', '-v', 'error', '-i', target, '-f', 'null', '-'], { stdio: 'pipe' });
  Object.assign(entry, { enabled: true, sha256: receipt.finalSha256, durationSeconds: receipt.durationSeconds,
    voiceId: receipt.voiceId, speed: receipt.speed, speedMethod: receipt.speedMethod });
  const temporaryManifest = `${path}.tmp`;
  writeFileSync(temporaryManifest, `${JSON.stringify(manifest, null, 2)}\n`);
  for (let attempt = 0; ; attempt++) {
    try { await rename(temporaryManifest, path); break; }
    catch (error) {
      if (!['EPERM', 'EACCES', 'EBUSY'].includes(error.code) || attempt >= 24) throw error;
      // Windows indexers may hold the manifest briefly. Retrying this LOCAL
      // rename does not repeat an ElevenLabs request or overwrite any audio.
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  const pubspecPath = resolve(root, 'pubspec.yaml');
  const pubspec = readFileSync(pubspecPath, 'utf8');
  const line = `    - ${entry.asset}`;
  if (!pubspec.split(/\r?\n/u).includes(line)) {
    writeFileSync(pubspecPath, pubspec.replace('    - assets/data/main_assistant_audio.json',
      `    - assets/data/main_assistant_audio.json\n${line}`));
  }
  completed++;
  console.log(`[${completed}/${selectedEntries.length}] READY ${entry.id} ${receipt.durationSeconds.toFixed(2)}s ${profile.speed}x`);
}
console.log(JSON.stringify({ completed, created, total: selectedEntries.length, dryRun: !generate }));
