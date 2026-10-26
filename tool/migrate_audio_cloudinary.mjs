// Upload original application audio, verify delivery, then emit public URL maps.
// node tool/migrate_audio_cloudinary.mjs <credentials-file> [--upload] [--apply]
// No credentials, upload signatures or private responses are written to receipts.
import { createHash } from 'node:crypto';
import { readFile, writeFile, readdir, mkdir, rename } from 'node:fs/promises';
import path from 'node:path';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const json = file => readFile(file, 'utf8').then(JSON.parse);
const save = (file, value) => writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
const receiptPath = 'build/cloudinary-all-audio-receipt.json';
const catalogPath = 'assets/data/remote_audio_catalog.json';
const audioRoot = 'assets/audio';

async function listAudio(directory) {
  const files = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    const file = `${directory}/${item.name}`;
    if (item.isDirectory()) files.push(...await listAudio(file));
    else if (/\.(mp3|wav|m4a|aac|ogg|flac|opus)$/i.test(file)) files.push(file);
  }
  return files.sort();
}

function credentialsFrom(text) {
  const result = {};
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(/^\s*(cloud[ _]?name|api[ _]?key|api[ _]?secret)\s*[:=]\s*(.*?)\s*$/i);
    if (!match) continue;
    let value = match[2];
    if (!value) {
      while (++i < lines.length && !lines[i].trim()) {}
      value = lines[i]?.trim() ?? '';
    }
    result[match[1].toLowerCase().replace(/[ _]/g, '')] = value.replace(/^["']|["']$/g, '');
  }
  for (const key of ['cloudname', 'apikey', 'apisecret']) {
    if (!result[key]) throw new Error(`Missing credential: ${key}`);
  }
  if (!/^[a-zA-Z0-9_-]+$/.test(result.cloudname)) throw new Error('Invalid cloud name');
  return result;
}

async function verify(url, source, cloud) {
  const uri = new URL(url);
  if (uri.protocol !== 'https:' || uri.hostname !== 'res.cloudinary.com' ||
      !uri.pathname.startsWith(`/${cloud}/video/upload/`)) throw new Error('Invalid delivery URL');
  const response = await fetch(uri, { signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`Delivery HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length !== source.sizeBytes || digest(bytes) !== source.sha256) {
    throw new Error('Delivery checksum/size mismatch');
  }
}

async function upload(source, credentials) {
  // Keep asset identity and checksum in the public ID. Existing objects are not overwritten.
  const publicId = `homi/audio/${source.asset.slice(`${audioRoot}/`.length).replace(/\.[^.]+$/, '')}-${source.sha256}`;
  if (!/^[a-zA-Z0-9/._-]+$/.test(publicId)) throw new Error('Invalid public ID');
  const params = { overwrite: 'false', public_id: publicId, timestamp: String(Math.floor(Date.now() / 1000)) };
  const signed = Object.entries(params).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join('&');
  const body = new FormData();
  for (const [key, value] of Object.entries(params)) body.set(key, value);
  body.set('api_key', credentials.apikey);
  body.set('signature', createHash('sha1').update(signed + credentials.apisecret).digest('hex'));
  body.set('file', new Blob([await readFile(source.asset)], { type: 'audio/mpeg' }), path.basename(source.asset));
  const response = await fetch(`https://api.cloudinary.com/v1_1/${credentials.cloudname}/video/upload`, {
    method: 'POST', body, signal: AbortSignal.timeout(60000),
  });
  if (!response.ok) throw new Error(`Upload HTTP ${response.status}`);
  const uploaded = await response.json();
  if (uploaded.public_id !== publicId || uploaded.resource_type !== 'video') throw new Error('Upload identity mismatch');
  return uploaded.secure_url;
}

async function applyMapping(sources, receipt) {
  const assets = {};
  for (const source of sources) {
    const item = receipt.assets[source.asset];
    if (!item || item.sha256 !== source.sha256 || item.sizeBytes !== source.sizeBytes || !item.verifiedAt) {
      throw new Error(`Missing verified upload: ${source.asset}`);
    }
    assets[source.asset] = { url: item.url, sha256: source.sha256, sizeBytes: source.sizeBytes };
  }
  // Validate every reference before modifying any runtime manifest.
  const manifests = [];
  for (const filename of (await readdir('assets/data')).filter(f => /audio.*\.json$/.test(f) && f !== 'audio_pack_index.json' && f !== 'remote_audio_catalog.json')) {
    const file = `assets/data/${filename}`;
    const data = await json(file);
    if (!Array.isArray(data.prompts)) continue;
    for (const prompt of data.prompts) {
      const item = assets[prompt.asset];
      if (!item || prompt.sha256 !== item.sha256 || (prompt.sizeBytes != null && prompt.sizeBytes !== item.sizeBytes)) {
        throw new Error(`Manifest/source mismatch: ${file} ${prompt.key ?? prompt.id}`);
      }
      prompt.url = item.url;
      prompt.sizeBytes = item.sizeBytes;
    }
    data.version = 'v5-cloudinary';
    manifests.push([file, data]);
  }
  for (const [file, data] of manifests) await save(file, data);
  const indexPath = 'assets/data/audio_pack_index.json';
  const index = await json(indexPath);
  for (const pack of index.packs) {
    const bytes = await readFile(pack.manifest);
    const data = JSON.parse(bytes);
    pack.manifestSha256 = digest(bytes);
    pack.version = data.version;
    pack.audioCount = data.prompts.length;
    pack.sizeBytes = data.prompts.reduce((sum, p) => sum + (p.sizeBytes ?? 0), 0);
  }
  await save(indexPath, index);
  await save(catalogPath, { schemaVersion: 1, cloudName: receipt.cloudName, assets });
  // The content snapshots also carry legacy song URLs. Point them at the same
  // verified account, including callers without a mapped curriculum song ID.
  const byFilename = new Map(Object.entries(assets).filter(([asset]) => asset.includes('/SONGS/'))
    .map(([asset, entry]) => [path.basename(asset), entry.url]));
  function replaceSongUrls(value) {
    if (Array.isArray(value)) value.forEach(replaceSongUrls);
    else if (value && typeof value === 'object') {
      for (const [key, child] of Object.entries(value)) {
        if (key === 'songAudioUrl' && typeof child === 'string') {
          if ([...byFilename.values()].includes(child)) continue;
          const url = byFilename.get(path.basename(new URL(child).pathname));
          if (!url) throw new Error('Unmapped content song URL');
          value[key] = url;
        } else replaceSongUrls(child);
      }
    }
  }
  for (const file of ['assets/data/listening_lessons.json', 'assets/data/listening_topic_patch_v42.json']) {
    const data = await json(file);
    replaceSongUrls(data);
    await save(file, data);
  }
  console.log(`Updated ${manifests.length} manifests and ${sources.length} catalog URLs.`);
}

async function main() {
  const credentials = credentialsFrom(await readFile(process.argv[2], 'utf8'));
  const sources = [];
  for (const asset of await listAudio(audioRoot)) {
    const bytes = await readFile(asset);
    sources.push({ asset, sha256: digest(bytes), sizeBytes: bytes.length });
  }
  console.log(`Inventory: ${sources.length} files, ${sources.reduce((sum, p) => sum + p.sizeBytes, 0)} bytes. Credentials parsed; secrets not logged.`);
  let receipt = { schemaVersion: 1, cloudName: credentials.cloudname, assets: {} };
  try {
    const previous = await json(receiptPath);
    if (previous.cloudName === credentials.cloudname) receipt = previous;
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (process.argv.includes('--upload')) {
    await mkdir('build', { recursive: true });
    // Reuse already verified catalog URLs in the same account.
    const existing = {};
    for (const filename of (await readdir('assets/data')).filter(f => /audio.*\.json$/.test(f))) {
      const data = await json(`assets/data/${filename}`);
      for (const p of data.prompts ?? []) {
        if (p.url?.startsWith(`https://res.cloudinary.com/${credentials.cloudname}/video/upload/`)) existing[p.asset] = p;
      }
    }
    let cursor = 0;
    let complete = 0;
    let saveQueue = Promise.resolve();
    const failures = [];
    await Promise.all(Array.from({ length: 8 }, async () => {
      while (cursor < sources.length) {
        const source = sources[cursor++];
        const previous = receipt.assets[source.asset];
        let url = previous?.sha256 === source.sha256 ? previous.url : existing[source.asset]?.sha256 === source.sha256 ? existing[source.asset].url : null;
        for (let attempt = 0; attempt < 3; attempt++) {
          try {
            url ??= await upload(source, credentials);
            await verify(url, source, credentials.cloudname);
            receipt.assets[source.asset] = { ...source, url, verifiedAt: new Date().toISOString() };
            // Serialize atomic receipts so a stopped process can resume safely.
            saveQueue = saveQueue.then(async () => {
              await save(`${receiptPath}.part`, receipt);
              await rename(`${receiptPath}.part`, receiptPath);
            });
            await saveQueue;
            complete++;
            if (complete % 50 === 0 || complete === sources.length) console.log(`Verified ${complete}/${sources.length}`);
            break;
          } catch (error) {
            if (attempt === 2) { failures.push(source.asset); console.error(`${source.asset}: ${error.message}`); }
            else await new Promise(resolve => setTimeout(resolve, (attempt + 1) * 1000));
          }
        }
      }
    }));
    if (failures.length) throw new Error(`${failures.length} upload/delivery failures; verified receipts retained for resume.`);
    console.log(`All ${complete} original audio files verified on Cloudinary.`);
  }
  if (process.argv.includes('--apply')) await applyMapping(sources, receipt);
}

main().catch(error => {
  // Never include credential-bearing request objects or HTTP bodies in logs.
  console.error(error.message);
  process.exitCode = 1;
});
