// Upload original application audio, verify delivery, then emit public URL maps.
// node tool/migrate_audio_cloudinary.mjs [<credentials-file>] [--upload] [--apply]
// Local-only: --apply-catalog updates delivery metadata; --check verifies it.
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

function validateDeliveryUrl(url, source, cloud) {
  const uri = new URL(url);
  if (uri.protocol !== 'https:' || uri.hostname !== 'res.cloudinary.com' ||
      uri.username || uri.password || uri.search || uri.hash ||
      !uri.pathname.startsWith(`/${cloud}/video/upload/`) ||
      !uri.pathname.includes(source.sha256)) {
    throw new Error(`Invalid immutable delivery URL: ${source.asset}`);
  }
}

async function audioManifests() {
  const files = (await readdir('assets/data')).filter(f =>
    /audio.*\.json$/.test(f) && f !== 'audio_pack_index.json' && f !== 'remote_audio_catalog.json');
  const manifests = [];
  for (const filename of files.sort()) {
    const file = `assets/data/${filename}`;
    const data = await json(file);
    if (Array.isArray(data.prompts)) manifests.push([file, data]);
  }
  return manifests;
}

function mappedSongUrls(data, assets, { checkOnly = false } = {}) {
  const byFilename = new Map(Object.entries(assets).filter(([asset]) => asset.includes('/SONGS/'))
    .map(([asset, entry]) => [path.basename(asset), entry.url]));
  const urls = new Set(byFilename.values());
  function visit(value) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') {
      for (const [key, child] of Object.entries(value)) {
        if (key === 'songAudioUrl' && typeof child === 'string') {
          if (urls.has(child)) continue;
          const url = byFilename.get(path.basename(new URL(child).pathname));
          if (checkOnly || !url) throw new Error('Unmapped content song URL');
          value[key] = url;
        } else visit(child);
      }
    }
  }
  visit(data);
}

async function applyMapping(sources, receipt, { fromCatalog = false } = {}) {
  const assets = {};
  for (const source of sources) {
    const item = receipt.assets[source.asset];
    if (!item || item.sha256 !== source.sha256 || item.sizeBytes !== source.sizeBytes ||
        (!fromCatalog && !item.verifiedAt)) {
      throw new Error(`Missing verified mapping: ${source.asset}`);
    }
    validateDeliveryUrl(item.url, source, receipt.cloudName);
    assets[source.asset] = { url: item.url, sha256: source.sha256, sizeBytes: source.sizeBytes };
  }
  if (Object.keys(receipt.assets).length !== sources.length) {
    throw new Error('Delivery mapping does not exactly cover the source inventory.');
  }
  // Prepare and validate every update before writing. Only delivery metadata
  // changes: current dev prompt keys, text, durations and provenance survive.
  const manifests = await audioManifests();
  const pending = new Map();
  for (const [file, data] of manifests) {
    for (const prompt of data.prompts) {
      const item = assets[prompt.asset];
      if (!item || prompt.sha256 !== item.sha256 ||
          (prompt.sizeBytes != null && prompt.sizeBytes !== item.sizeBytes)) {
        throw new Error(`Manifest/source mismatch: ${file} ${prompt.key ?? prompt.id}`);
      }
      prompt.url = item.url;
      prompt.sizeBytes = item.sizeBytes;
    }
    data.version = 'v5-cloudinary';
    pending.set(file, `${JSON.stringify(data, null, 2)}\n`);
  }
  const indexPath = 'assets/data/audio_pack_index.json';
  const index = await json(indexPath);
  for (const pack of index.packs) {
    const manifest = pending.get(pack.manifest);
    if (manifest == null) throw new Error(`Unmapped indexed manifest: ${pack.manifest}`);
    const data = JSON.parse(manifest);
    pack.manifestSha256 = digest(Buffer.from(manifest));
    pack.version = data.version;
    pack.audioCount = data.prompts.length;
    pack.sizeBytes = data.prompts.reduce((sum, p) => sum + (p.sizeBytes ?? 0), 0);
  }
  pending.set(indexPath, `${JSON.stringify(index, null, 2)}\n`);
  pending.set(catalogPath, `${JSON.stringify({ schemaVersion: 1, cloudName: receipt.cloudName, assets }, null, 2)}\n`);
  for (const file of ['assets/data/listening_lessons.json', 'assets/data/listening_topic_patch_v42.json']) {
    const data = await json(file);
    mappedSongUrls(data, assets);
    pending.set(file, `${JSON.stringify(data, null, 2)}\n`);
  }
  for (const [file, content] of pending) await writeFile(file, content);
  console.log(`Updated ${manifests.length} manifests and ${sources.length} catalog URLs; existing prompt metadata preserved.`);
}

async function checkMapping(sources) {
  const catalog = await json(catalogPath);
  if (catalog.schemaVersion !== 1 || Object.keys(catalog.assets).length !== sources.length) {
    throw new Error('Delivery catalog does not exactly cover the source inventory.');
  }
  for (const source of sources) {
    const entry = catalog.assets[source.asset];
    if (!entry || entry.sha256 !== source.sha256 || entry.sizeBytes !== source.sizeBytes) {
      throw new Error(`Catalog/source mismatch: ${source.asset}`);
    }
    validateDeliveryUrl(entry.url, source, catalog.cloudName);
  }
  const manifests = await audioManifests();
  let promptCount = 0;
  for (const [file, data] of manifests) {
    for (const prompt of data.prompts) {
      const entry = catalog.assets[prompt.asset];
      if (!entry || prompt.sha256 !== entry.sha256 || prompt.sizeBytes !== entry.sizeBytes || prompt.url !== entry.url) {
        throw new Error(`Manifest/catalog mismatch: ${file} ${prompt.key ?? prompt.id}`);
      }
      promptCount++;
    }
  }
  const index = await json('assets/data/audio_pack_index.json');
  for (const pack of index.packs) {
    const bytes = await readFile(pack.manifest);
    const data = JSON.parse(bytes);
    if (pack.manifestSha256 !== digest(bytes) || pack.version !== data.version ||
        pack.audioCount !== data.prompts.length ||
        pack.sizeBytes !== data.prompts.reduce((sum, p) => sum + (p.sizeBytes ?? 0), 0)) {
      throw new Error(`Index/manifest mismatch: ${pack.manifest}`);
    }
  }
  for (const file of ['assets/data/listening_lessons.json', 'assets/data/listening_topic_patch_v42.json']) {
    mappedSongUrls(await json(file), catalog.assets, { checkOnly: true });
  }
  console.log(`Local integrity verified: ${sources.length} original files, ${manifests.length} manifests, ${promptCount} prompt references, ${index.packs.length} indexed packs. No network requests or source writes.`);
}

async function main() {
  const args = process.argv.slice(2);
  const flags = args.filter(arg => arg.startsWith('--'));
  const known = new Set(['--upload', '--apply', '--apply-catalog', '--check']);
  if (flags.some(flag => !known.has(flag))) throw new Error('Unknown migration option.');
  const credentialFiles = args.filter(arg => !arg.startsWith('--'));
  if (credentialFiles.length > 1) throw new Error('Expected at most one credentials file.');
  const localOnly = flags.includes('--apply-catalog') || flags.includes('--check');
  if (localOnly && (flags.length !== 1 || credentialFiles.length)) {
    throw new Error('Use --check or --apply-catalog alone; these modes never use credentials or network.');
  }
  const sources = [];
  for (const asset of await listAudio(audioRoot)) {
    const bytes = await readFile(asset);
    sources.push({ asset, sha256: digest(bytes), sizeBytes: bytes.length });
  }
  console.log(`Inventory: ${sources.length} files, ${sources.reduce((sum, p) => sum + p.sizeBytes, 0)} bytes.`);
  if (flags.includes('--check')) return checkMapping(sources);
  if (flags.includes('--apply-catalog')) {
    const catalog = await json(catalogPath);
    if (catalog.schemaVersion !== 1) throw new Error('Unsupported delivery catalog.');
    return applyMapping(sources, catalog, { fromCatalog: true });
  }
  if (!credentialFiles.length) {
    if (flags.length) throw new Error('Upload/receipt application requires a credentials file.');
    return;
  }
  const credentials = credentialsFrom(await readFile(credentialFiles[0], 'utf8'));
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
