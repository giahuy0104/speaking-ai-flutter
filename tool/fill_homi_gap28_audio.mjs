// Only the 28 reviewed gaps from the 2026-09-16 runtime audit.
// --prepare: freeze plan + append disabled manifest rows (no network).
// --generate --api-key-file <outside-workspace>: sequential generation/activation.
// --verify: local receipt/checksum/decode verification (no network or writes).
// Default: dry run. Never regenerate existing audio or retry uncertain requests.
import {readFileSync, writeFileSync, existsSync, mkdirSync, unlinkSync} from 'node:fs';
import {rename} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve, dirname, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = name => args.includes(name) ? args[args.indexOf(name)+1] : undefined;
const hash = value => createHash('sha256').update(value).digest('hex');
const read = path => readFileSync(resolve(root,path),'utf8');
const json = path => JSON.parse(read(path));
const manifestPath = 'assets/data/main_assistant_audio.json';
const planPath = 'deliverables/homi-gap28-audio-plan.json';
const manifest = () => json(manifestPath);
const approvedTexts = [
  ...[1,2].map(n=>`Bạn cần hoàn thành Level ${n} trước nhé.`),
  'Bạn chọn Level 1, 2, 3 nhé.',
  'Bi cô chưa thực hiện được. Con thử lại nhé.',
  'Bi cô có bài học cho các bạn từ 3 đến 15 tuổi. Con mấy tuổi',
  ...Array.from({length:10},(_,i)=>`Chủ đề ${i+1} bạn đã học xong rồi. Bạn muốn học chủ đề khác hay học lại?`),
  ...[3,4].map(n=>`Có ${n} Chủ đề. Bạn muốn học Chủ đề số mấy?`),
  'Cô chưa mở được micro để dịch liên tục. Con kiểm tra quyền micro rồi thử lại nhé.',
  ...Array.from({length:10},(_,i)=>`Mình học tiếp Chủ đề ${i+1} nhé.`),
];
function check(condition,message) { if (!condition) throw new Error(message); }
function profiles(m) {
  check(m.provider==='elevenlabs' && m.modelId==='eleven_v3','Expected ElevenLabs Eleven v3.');
  check(m.profiles.vi.voiceId==='5CVDNcIPiOYgRUQuxXd7' && m.profiles.vi.speed===0.9,'Incorrect Vietnamese profile.');
  check(m.profiles.en.voiceId==='Nhs7eitvQWFTQBsf0yiT' && m.profiles.en.speed===0.75,'Incorrect English profile.');
}
function safeAsset(asset) {
  const path=resolve(root,asset), rel=relative(root,path);
  check(!rel.startsWith('..') && !isAbsolute(rel) && /^assets\/audio\/MAIN\/GAP28-\d{3}\.vi\.v1\.mp3$/.test(asset),'Unsafe batch target.');
  return path;
}
async function atomic(path, value) {
  const destination=resolve(root,path), temporary=`${destination}.gap28.tmp`;
  writeFileSync(temporary,value,{flag:'wx'});
  for (let attempt=0;;attempt++) {
    try { await rename(temporary,destination); return; }
    catch(error) {
      if (!['EPERM','EACCES','EBUSY'].includes(error.code) || attempt>=20) throw error;
      await new Promise(r=>setTimeout(r,200)); // LOCAL rename only; never API retry.
    }
  }
}
function validatePlan(plan) {
  profiles(plan);
  check(plan.prompts.length===28 && new Set(plan.prompts.map(p=>p.text)).size===28,'Expected exactly 28 unique prompts.');
  check(approvedTexts.every(t=>plan.prompts.some(p=>p.text===t && p.locale==='vi-VN')),'Plan differs from reviewed text.');
  for(const p of plan.prompts) safeAsset(p.asset);
}
function verify(entry, decode=true) {
  const target=safeAsset(entry.asset);
  check(existsSync(target) && existsSync(`${target}.json`),`Incomplete output: ${entry.id}`);
  const receipt=JSON.parse(readFileSync(`${target}.json`,'utf8'));
  const bytes=readFileSync(target);
  check(receipt.request.text===entry.text && receipt.request.model_id==='eleven_v3' &&
    receipt.request.language_code==='vi' && receipt.request.voice_settings.speed===1 &&
    receipt.voiceId==='5CVDNcIPiOYgRUQuxXd7' && receipt.speed===0.9 &&
    receipt.speedMethod==='ffmpeg-atempo' && receipt.finalSha256===hash(bytes) &&
    bytes.length<=2*1024*1024 && receipt.durationSeconds>0 && receipt.durationSeconds<45 &&
    Math.abs(receipt.durationSeconds-receipt.sourceDurationSeconds/0.9)<=0.25,
    `Output verification failed: ${entry.id}`);
  if(decode) execFileSync('ffmpeg',['-hide_banner','-v','error','-i',target,'-f','null','-'],{stdio:'pipe'});
  return receipt;
}
function preserved(plan) {
  const current=manifest();
  for(const baseline of plan.baseline.mainPrompts) {
    const p=current.prompts.find(p=>p.id===baseline.id);
    check(p && hash(JSON.stringify(p))===baseline.sha256,`Pre-existing prompt changed: ${baseline.id}`);
  }
  for(const baseline of plan.baseline.files) {
    check(hash(readFileSync(resolve(root,baseline.path)))===baseline.sha256,`Protected source changed: ${baseline.path}`);
  }
}
async function main() {
  profiles(manifest());
  const mutates=args.includes('--prepare') || args.includes('--generate');
  const lock=resolve(root,'deliverables/homi-gap28-audio.lock');
  if(mutates) writeFileSync(lock,`${process.pid}\n`,{flag:'wx'});
  try {
    if(args.includes('--prepare')) {
      check(!existsSync(resolve(root,planPath)),'Plan already frozen; use --generate or --verify.');
      const audit=json('deliverables/homi-speech-audit-summary.json');
      check(audit.currentMissing.length===28,'Audit must still contain the 28 reviewed gaps.');
      const m=manifest(), curriculum=json('assets/data/curriculum_audio.json');
      const prompts=approvedTexts.map((text,i)=>{
        const gap=audit.currentMissing.find(p=>p.text===text && p.locale==='vi-VN');
        check(gap,`Text not in audited gaps: ${text}`);
        const id=`GAP28-${String(i+1).padStart(3,'0')}`;
        check(![...m.prompts,...curriculum.prompts].some(p=>p.text===text || p.id===id),'Prompt already exists.');
        return {id,text,locale:'vi-VN',voiceLanguage:'vi',version:1,enabled:false,
          asset:`assets/audio/MAIN/${id}.vi.v1.mp3`,
          sources:[...new Set(gap.evidence.map(e=>e.source))],
          aliases:[id],batch:'homi-runtime-gap28-2026-09-16'};
      });
      const protectedPaths=json('deliverables/homi-speech-provenance.json').map(p=>p.path)
        .filter(p=>p.startsWith('lib/') || ['assets/data/listening_lessons.json','assets/data/curriculum_audio.json'].includes(p));
      const plan={schemaVersion:1,provider:m.provider,modelId:m.modelId,profiles:m.profiles,
        auditedAt:audit.date,totalCharacters:prompts.reduce((n,p)=>n+[...p.text].length,0),
        baseline:{mainCount:m.prompts.length,curriculumCount:curriculum.prompts.length,
          mainPrompts:m.prompts.map(p=>({id:p.id,sha256:hash(JSON.stringify(p))})),
          files:protectedPaths.map(path=>({path,sha256:hash(readFileSync(resolve(root,path)))}))},prompts};
      validatePlan(plan);
      writeFileSync(resolve(root,planPath),`${JSON.stringify(plan,null,2)}\n`,{flag:'wx'});
      m.prompts.push(...prompts);
      await atomic(manifestPath,`${JSON.stringify(m,null,2)}\n`);
      console.log(`PREPARED: 28 disabled prompts; ${plan.totalCharacters} characters; no API calls.`);
      return;
    }
    if(!existsSync(resolve(root,planPath))) {
      console.log(JSON.stringify({mode:'dry-run',count:approvedTexts.length,
        characters:approvedTexts.reduce((n,t)=>n+[...t].length,0),voice:'5CVDNcIPiOYgRUQuxXd7',model:'eleven_v3',speed:0.9}));
      return;
    }
    const plan=json(planPath);
    validatePlan(plan);
    preserved(plan);
    let created=0, ready=0;
    const receipts=[];
    for(const planned of plan.prompts) {
      const entry=manifest().prompts.find(p=>p.id===planned.id);
      check(entry?.text===planned.text && entry.asset===planned.asset,`Manifest/plan mismatch: ${planned.id}`);
      const target=safeAsset(entry.asset);
      if(!args.includes('--generate') && !args.includes('--verify')) {
        console.log(`${entry.id}: ${existsSync(target)?'EXISTS':'GENERATE'} ${entry.text}`);
        continue;
      }
      if(args.includes('--generate') && !existsSync(target)) {
        const keyPath=option('--api-key-file');
        check(keyPath,'Provide --api-key-file outside workspace.');
        const attempts=resolve(root,'deliverables/homi-gap28-attempts');
        mkdirSync(attempts,{recursive:true});
        const attemptPath=resolve(attempts,`${entry.id}.json`);
        check(!existsSync(attemptPath),`Previous attempt exists for ${entry.id}. Check provider history; no uncertain retry.`);
        writeFileSync(attemptPath,JSON.stringify({id:entry.id,status:'started',at:new Date().toISOString()}),{flag:'wx'});
        try {
          execFileSync(process.execPath,[resolve(root,'tool/generate_main_assistant_audio.mjs'),
            '--id',entry.id,'--generate','--neutral-source-speed','--api-key-file',keyPath],{cwd:root,stdio:'pipe'});
        } catch(error) {
          // The child already sanitizes its stderr. Avoid ever printing the
          // exec error object, request headers, or credential file contents.
          console.error(error.stderr?.toString() ?? 'Generation failed.');
          throw new Error(`STOPPED at ${entry.id}; check provider history before retrying.`);
        }
        created++;
        writeFileSync(attemptPath,JSON.stringify({id:entry.id,status:'generated',at:new Date().toISOString()}));
      }
      const receipt=verify(entry);
      if(args.includes('--generate')) {
        // Add only the newly validated asset. Never mount source/receipt dirs.
        const pubspecPath='pubspec.yaml', pubspec=read(pubspecPath);
        const line=`    - ${entry.asset}`, newline=pubspec.includes('\r\n')?'\r\n':'\n';
        if(!pubspec.split(/\r?\n/).includes(line)) {
          const anchor='    - assets/data/main_assistant_audio.json';
          check(pubspec.split(anchor).length===2,'Missing/ambiguous pubspec anchor.');
          await atomic(pubspecPath,pubspec.replace(anchor,`${anchor}${newline}${line}`));
        }
        const latest=manifest();
        profiles(latest);
        const live=latest.prompts.find(p=>p.id===entry.id);
        check(live.text===entry.text && live.asset===entry.asset,'Concurrent prompt mutation.');
        Object.assign(live,{enabled:true,sha256:receipt.finalSha256,durationSeconds:receipt.durationSeconds,
          voiceId:receipt.voiceId,speed:receipt.speed,speedMethod:receipt.speedMethod});
        await atomic(manifestPath,`${JSON.stringify(latest,null,2)}\n`);
      } else {
        check(entry.enabled && entry.sha256===receipt.finalSha256 && entry.durationSeconds===receipt.durationSeconds,
          `Not correctly activated: ${entry.id}`);
        check(read('pubspec.yaml').includes(`    - ${entry.asset}`),`Not bundled: ${entry.id}`);
      }
      receipts.push({id:entry.id,asset:entry.asset,durationSeconds:receipt.durationSeconds,
        requestId:receipt.requestId,characterCost:receipt.characterCost,sha256:receipt.finalSha256});
      ready++;
      console.log(`[${ready}/28] READY ${entry.id}, ${receipt.durationSeconds.toFixed(2)}s, vi 0.9x`);
    }
    preserved(plan);
    if(args.includes('--generate')) {
      await atomic('deliverables/homi-gap28-generation-result.json',`${JSON.stringify({
        completedAt:new Date().toISOString(),ready,created,modelId:'eleven_v3',
        voiceId:plan.profiles.vi.voiceId,speed:0.9,characters:plan.totalCharacters,receipts,
      },null,2)}\n`);
    }
    console.log(JSON.stringify({ready,created,oldPromptsPreserved:true,applicationCodePreserved:true}));
  } finally { if(mutates) unlinkSync(lock); }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
