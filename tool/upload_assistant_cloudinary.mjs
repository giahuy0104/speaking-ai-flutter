// Run from the repository root. Credentials are read locally and never logged.
// node tool/upload_assistant_cloudinary.mjs <credentials-file> [--upload]
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const manifestPath = 'assets/data/assistant_core_audio.json';
const receiptPath = 'build/assistant-cloudinary-receipt.json';
async function main() {
  const credentialText = await readFile(process.argv[2], 'utf8');
  const credentials = {};
  const lines = credentialText.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*(cloud[ _]?name|api[ _]?key|api[ _]?secret)\s*[:=]\s*(.*?)\s*$/i);
    if (!match) continue;
    let value = match[2];
    if (!value) {
      while (++i < lines.length && !lines[i].trim()) {}
      value = lines[i]?.trim() ?? '';
    }
    credentials[match[1].toLowerCase().replace(/[ _]/g, '')] = value.replace(/^["']|["']$/g, '');
  }
  for (const name of ['cloudname', 'apikey', 'apisecret']) {
    if (!credentials[name]) throw new Error(`Missing credential: ${name}`);
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(credentials.cloudname)) throw new Error('Invalid cloud name');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  if (manifest.pack !== 'assistant-core') throw new Error('Unexpected pack');
  const prepared = [];
  for (const prompt of manifest.prompts) {
    if (!/^assets\/audio\/assistant-core\/[a-zA-Z0-9._-]+\.mp3$/.test(prompt.asset)) {
      throw new Error(`Unexpected asset for ${prompt.key}`);
    }
    const bytes = await readFile(prompt.asset);
    if (digest(bytes) !== prompt.sha256 || bytes.length !== prompt.sizeBytes) {
      throw new Error(`Local integrity mismatch: ${prompt.key}`);
    }
    prepared.push({ prompt, bytes });
  }
  console.log(`Credentials available; verified ${prepared.length} assistant-core source files.`);
  if (!process.argv.includes('--upload')) return;
  let receipt = { pack: 'assistant-core', assets: {} };
  try { receipt = JSON.parse(await readFile(receiptPath, 'utf8')); } catch {}
  await mkdir('build', { recursive: true });
  for (const { prompt, bytes } of prepared) {
    const publicId = `homi/audio/assistant-core/${prompt.key}-${prompt.sha256}`;
    let item = receipt.assets[prompt.key];
    if (!item || item.sha256 !== prompt.sha256 || !item.url.startsWith(`https://res.cloudinary.com/${credentials.cloudname}/`)) {
      const timestamp = Math.floor(Date.now() / 1000).toString();
      const params = { overwrite: 'false', public_id: publicId, timestamp };
      const signed = Object.entries(params).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('&');
      const signature = createHash('sha1').update(signed + credentials.apisecret).digest('hex');
      const body = new FormData();
      for (const [k, v] of Object.entries(params)) body.set(k, v);
      body.set('api_key', credentials.apikey);
      body.set('signature', signature);
      body.set('file', new Blob([bytes], { type: 'audio/mpeg' }), `${prompt.key}.mp3`);
      const response = await fetch(`https://api.cloudinary.com/v1_1/${credentials.cloudname}/video/upload`, {
        method: 'POST', body, signal: AbortSignal.timeout(60000),
      });
      if (!response.ok) throw new Error(`Upload HTTP ${response.status}: ${prompt.key}`);
      const uploaded = await response.json();
      if (uploaded.public_id !== publicId || uploaded.resource_type !== 'video') throw new Error(`Upload identity mismatch: ${prompt.key}`);
      item = { url: uploaded.secure_url, sha256: prompt.sha256, sizeBytes: bytes.length };
    }
    const url = new URL(item.url);
    if (url.protocol !== 'https:' || url.hostname !== 'res.cloudinary.com' || !url.pathname.startsWith(`/${credentials.cloudname}/video/upload/`)) {
      throw new Error(`Unexpected delivery URL: ${prompt.key}`);
    }
    const delivered = await fetch(url, { signal: AbortSignal.timeout(30000) });
    if (!delivered.ok) throw new Error(`Delivery HTTP ${delivered.status}: ${prompt.key}`);
    const downloaded = Buffer.from(await delivered.arrayBuffer());
    if (digest(downloaded) !== prompt.sha256 || downloaded.length !== bytes.length) throw new Error(`CDN integrity mismatch: ${prompt.key}`);
    receipt.assets[prompt.key] = item;
    await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n');
    console.log(`Verified ${Object.keys(receipt.assets).length}/${prepared.length}: ${prompt.key}`);
  }
  // Emit reviewed patch inputs; publishing never silently edits app configuration.
  console.log(`Complete. Verified URL mapping: ${receiptPath}`);
}
main().catch((error) => {
  // Do not print HTTP bodies or credential-bearing request objects.
  console.error(error instanceof Error ? error.message : 'Upload failed');
  process.exitCode = 1;
});
