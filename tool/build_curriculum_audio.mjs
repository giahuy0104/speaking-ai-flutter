// Explicit --apply imports/generates and activates the reviewed curriculum pack.
// No provider retries, subscription changes, uploads, deployment or key bundling.
import { readFileSync, writeFileSync, existsSync, mkdirSync, copyFileSync, constants } from 'node:fs';
import { rename } from 'node:fs/promises';
import { resolve, dirname, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const plan = JSON.parse(readFileSync(resolve(root, 'deliverables/curriculum_audio_plan.json'), 'utf8'));
const args = process.argv.slice(2);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const manifestPath = resolve(root, 'assets/data/curriculum_audio.json');
const receiptsDir = resolve(root, 'deliverables/curriculum_audio_receipts');
const sourcesDir = resolve(root, 'deliverables/curriculum_audio_sources');
const ready = [];
let secret = '';
let imported = 0, generated = 0, reused = 0;
function safeAsset(asset) {
  if (!/^assets\/audio\/(?:MAIN|CURRICULUM)\/[A-Za-z0-9_.-]+\.mp3$/.test(asset)) throw new Error('Unsafe audio asset');
  return resolve(root, asset);
}
function seconds(path) {
  return Number(execFileSync('ffprobe', ['-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',path], { encoding:'utf8' }).trim());
}
function verify(path) {
  execFileSync('ffmpeg', ['-hide_banner','-v','error','-i',path,'-f','null','-'], { stdio:'pipe' });
  const duration = seconds(path);
  const bytes = readFileSync(path);
  if (!Number.isFinite(duration) || duration <= 0 || duration > 45 || bytes.length > 2*1024*1024) throw new Error('Invalid audio size/duration: '+path);
  return { durationSeconds: duration, sha256: hash(bytes), bytes: bytes.length };
}
async function atomicJson(path, value) {
  const temp = `${path}.tmp`;
  writeFileSync(temp, JSON.stringify(value, null, 2)+'\n');
  for (let retry = 0; ; retry++) {
    try { await rename(temp, path); return; }
    catch (error) {
      if (!['EPERM','EACCES','EBUSY'].includes(error.code) || retry >= 24) throw error;
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
}
async function publish() {
  await atomicJson(manifestPath, { schemaVersion:1, enabled:true, modelId:'eleven_v3', profiles:plan.profiles,
    // The assistant's matching entries are already in the primary manifest.
    prompts:ready.filter(p=>!p.reusableAssistantId).map(p=>({
      id:p.id, text:p.text, locale:p.locale, voiceLanguage:p.voiceLanguage,
      enabled:true, asset:p.asset, sha256:p.sha256, durationSeconds:p.durationSeconds,
      aliases:p.aliases, kinds:p.kinds,
    })) });
}
async function key() {
  if (secret) return secret;
  const index = args.indexOf('--api-key-file');
  if (index < 0 || !args[index+1]) throw new Error('Missing --api-key-file outside project');
  const path = resolve(args[index+1]);
  const rel = relative(root, path);
  if (!rel.startsWith('..') && !isAbsolute(rel)) throw new Error('Key must stay outside project');
  const text = readFileSync(path, 'utf8').trim().replace(/^\uFEFF/u,'');
  const matches = text.match(/\bsk_[a-zA-Z0-9_-]+\b/gu) ?? [];
  secret = matches.length === 1 ? matches[0] : text;
  if (!secret || /\s/u.test(secret)) throw new Error('Expected one API key');
  return secret;
}
async function segment(text, language) {
  const readyEntry = ready.find(p=>p.text===text && p.voiceLanguage===language);
  if (readyEntry) return {file:safeAsset(readyEntry.asset),sourceKind:'verified-pack-clip',text,language,sha256:readyEntry.sha256};
  if (!['en','vi'].includes(language) || /[\[\]{}$]/u.test(text)) throw new Error('Invalid speech segment');
  const profile = plan.profiles[language];
  const request = { text, model_id:'eleven_v3', language_code:language, seed:164109,
    voice_settings:{ stability:0.5, similarity_boost:0.75 } };
  const signature = hash(JSON.stringify({request,profile}));
  const raw = resolve(sourcesDir, `${signature}.source.mp3`);
  const cooked = resolve(sourcesDir, `${signature}.tempo.mp3`);
  const receiptPath = `${raw}.json`;
  let receipt;
  if (existsSync(raw)) {
    if (!existsSync(receiptPath)) throw new Error('Source has no receipt; inspect request history before retrying');
    receipt = JSON.parse(readFileSync(receiptPath,'utf8'));
    if (receipt.signature !== signature || receipt.sha256 !== hash(readFileSync(raw))) throw new Error('Source receipt mismatch');
  } else {
    const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${profile.voiceId}?output_format=mp3_44100_128`, {
      method:'POST', redirect:'error', signal:AbortSignal.timeout(120000),
      headers:{'xi-api-key':await key(),'Content-Type':'application/json',Accept:'audio/mpeg'}, body:JSON.stringify(request),
    });
    if (!response.ok) throw new Error(`ElevenLabs HTTP ${response.status}; stopped without retry`);
    if (!response.headers.get('content-type')?.includes('audio/')) throw new Error('Unexpected provider response');
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length < 1000) throw new Error('Provider response too small');
    writeFileSync(raw, bytes, {flag:'wx'});
    receipt = {signature,request,profile,sha256:hash(bytes),requestId:response.headers.get('request-id'),createdAt:new Date().toISOString()};
    writeFileSync(receiptPath, JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
  }
  if (!existsSync(cooked)) execFileSync('ffmpeg',['-hide_banner','-v','error','-n','-i',raw,
    '-af',`atempo=${profile.speed}`,'-map_metadata','-1','-c:a','libmp3lame','-b:a','128k','-ar','44100','-ac','1',cooked],{stdio:'pipe'});
  if (Math.abs(seconds(cooked)-seconds(raw)/profile.speed)>0.25) throw new Error('Tempo duration verification failed');
  return {file:cooked,...receipt};
}
async function main() {
  if (!args.includes('--apply')) {
    console.log(JSON.stringify({dryRun:true,total:plan.prompts.length,
      existingOutputs:plan.prompts.filter(p=>existsSync(safeAsset(p.asset))).length,
      missing:plan.prompts.filter(p=>!p.reusableAssistantId&&!p.importSource&&!existsSync(safeAsset(p.asset))).length})); return;
  }
  execFileSync('ffmpeg',['-version'],{stdio:'ignore'});
  execFileSync('ffprobe',['-version'],{stdio:'ignore'});
  mkdirSync(resolve(root,'assets/audio/CURRICULUM'),{recursive:true});
  mkdirSync(receiptsDir,{recursive:true}); mkdirSync(sourcesDir,{recursive:true});
  const pubspecPath = resolve(root,'pubspec.yaml');
  let pubspec = readFileSync(pubspecPath,'utf8');
  if (!pubspec.includes('    - assets/data/curriculum_audio.json')) {
    pubspec = pubspec.replace('    - assets/data/main_assistant_audio.json',
      '    - assets/data/main_assistant_audio.json\n    - assets/data/curriculum_audio.json\n    - assets/audio/CURRICULUM/');
    writeFileSync(pubspecPath,pubspec);
  }
  for (const entry of plan.prompts) {
    const output = safeAsset(entry.asset);
    const receiptPath = resolve(receiptsDir,entry.id+'.json');
    let provenance;
    if (entry.reusableAssistantId) {
      const checked = verify(output);
      if (checked.sha256 !== entry.sha256) throw new Error('Assistant checksum changed');
      Object.assign(entry,checked); reused++;
    } else if (existsSync(output)) {
      if (!existsSync(receiptPath)) throw new Error('Existing output missing receipt: '+entry.id);
      provenance = JSON.parse(readFileSync(receiptPath,'utf8'));
      // Identical bytes to a successfully decoded receipt need no second
      // full decode when resuming a large batch.
      const bytes = readFileSync(output);
      const checked = {sha256:hash(bytes),bytes:bytes.length,durationSeconds:provenance.durationSeconds};
      if (provenance.text !== entry.text || provenance.sha256 !== checked.sha256 ||
          JSON.stringify(provenance.profiles) !== JSON.stringify(plan.profiles) ||
          !Number.isFinite(checked.durationSeconds) || checked.durationSeconds<=0 || checked.durationSeconds>45) throw new Error('Existing output mismatch');
      Object.assign(entry,checked); reused++;
    } else {
      if (entry.importSource) {
        const source = entry.importSource;
        if (source.sourceText !== entry.text || source.modelId !== 'eleven_v3') throw new Error('Import content/profile mismatch');
        const checked = verify(source.file);
        if (source.sourceSha256 && checked.sha256 !== source.sourceSha256) throw new Error('Import checksum mismatch');
        copyFileSync(source.file,output,constants.COPYFILE_EXCL);
        provenance = {sourceKind:'existing-eleven-v3',...source}; imported++;
      } else {
        const segments = [];
        for (const s of entry.assemblySegments ?? entry.synthesisSegments ?? [{text:entry.text,language:entry.voiceLanguage}]) {
          if (s.importSource) {
            const checked = verify(s.importSource.file);
            if (s.importSource.sourceSha256 && s.importSource.sourceSha256 !== checked.sha256) throw new Error('Assembly source hash mismatch');
            segments.push({...s.importSource,...checked});
          } else segments.push(await segment(s.text,s.language));
        }
        if (segments.length===1) copyFileSync(segments[0].file,output,constants.COPYFILE_EXCL);
        else {
          const inputs = segments.flatMap(s=>['-i',s.file]);
          const chain = segments.map((_,i)=>`[${i}:a]`).join('')+`concat=n=${segments.length}:v=0:a=1[out]`;
          execFileSync('ffmpeg',['-hide_banner','-v','error','-n',...inputs,'-filter_complex',chain,'-map','[out]',
            '-map_metadata','-1','-c:a','libmp3lame','-b:a','128k','-ar','44100','-ac','1',output],{stdio:'pipe'});
        }
        provenance = {sourceKind:'new-eleven-v3',segments}; generated++;
      }
      Object.assign(entry,verify(output));
      writeFileSync(receiptPath,JSON.stringify({...provenance,id:entry.id,text:entry.text,asset:entry.asset,
        sha256:entry.sha256,durationSeconds:entry.durationSeconds,profiles:plan.profiles},null,2)+'\n',{flag:'wx'});
    }
    ready.push(entry);
    if (ready.length%25===0 || !entry.importSource) {
      await publish();
      console.log(`[${ready.length}/${plan.prompts.length}] verified; imported=${imported} generated=${generated} reused=${reused}`);
    }
  }
  await publish();
  // Only audio URI fields change. IDs, text, sequence and progress keys stay intact.
  const index = new Map(ready.map(p=>[p.voiceLanguage+'|'+p.text,p]));
  const audioUri = (text,language) => {
    const p = index.get(language+'|'+(text??'').trim());
    return p ? 'asset:///'+p.asset : null;
  };
  const catalogPath = resolve(root,'assets/data/listening_lessons.json');
  const catalog = JSON.parse(readFileSync(catalogPath,'utf8'));
  let linked = 0;
  for (const g of catalog.groups) for (const t of g.topics) for (const l of t.lessons) {
    for (const s of l.sentences) {
      const en=audioUri(s.english,'en'), vi=audioUri(s.vietnamese,'vi');
      if (!en || !vi) throw new Error('Missing core sample '+s.id);
      s.audioUrl=en; s.vietnameseAudioUrl=vi; linked+=2;
    }
    const intro=audioUri(l.intro,'vi');
    if (intro) { l.introAudioUrl=intro; linked++; }
    const outro=audioUri(l.outro,'vi');
    if (outro) { l.outroAudioUrl=outro; linked++; }
  }
  catalog.audioProvider='eleven_v3-authored-local';
  await atomicJson(catalogPath,catalog);
  console.log(JSON.stringify({complete:true,total:ready.length,imported,generated,reused,linkedCatalogAudioFields:linked,
    totalBytes:ready.reduce((n,p)=>n+p.bytes,0),totalSeconds:ready.reduce((n,p)=>n+p.durationSeconds,0)}));
}
main().catch(error=>{ console.error(secret ? String(error.message).replaceAll(secret,'[REDACTED]') : error.message); process.exitCode=1; });
