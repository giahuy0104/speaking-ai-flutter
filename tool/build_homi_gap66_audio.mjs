// Standalone production tool. Never imported by Flutter. Default: dry-run.
// prepare -> generate [--group NAME] -> verify -> install --group NAME.
// Paid requests are sequential; uncertain attempts are never retried automatically.
import {readFileSync,writeFileSync,existsSync,mkdirSync,readdirSync,copyFileSync,renameSync,unlinkSync} from 'node:fs';
import {resolve,dirname,relative,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2), mode=args[0]??'dry-run';
const option=n=>args.includes(n)?args[args.indexOf(n)+1]:undefined;
const out='deliverables/homi-gap66-2026-09-17';
const audit='deliverables/audio-runtime-audit-2026-09-17/missing-audio.json';
const manifestPath='assets/data/homi_gap66_audio.json';
const profiles={en:{voiceId:'Nhs7eitvQWFTQBsf0yiT',speed:0.75},vi:{voiceId:'5CVDNcIPiOYgRUQuxXd7',speed:0.9}};
const hash=b=>createHash('sha256').update(b).digest('hex');
const read=p=>readFileSync(resolve(root,p));
const json=p=>JSON.parse(read(p).toString('utf8'));
const check=(condition,message)=>{if(!condition)throw Error(message);};
const save=(p,v)=>{
  const target=resolve(root,p),tmp=`${target}.gap66.tmp`;
  mkdirSync(dirname(target),{recursive:true});
  writeFileSync(tmp,JSON.stringify(v,null,2)+'\n',{flag:'wx'});
  renameSync(tmp,target);
};
const walk=p=>readdirSync(resolve(root,p),{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(`${p}/${e.name}`):[`${p}/${e.name}`]);
const probe=p=>Number(execFileSync('ffprobe',['-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',resolve(root,p)],{encoding:'utf8'}).trim());
function key() {
  const input=option('--api-key-file');
  check(input,'Provide --api-key-file outside workspace.');
  const absolute=resolve(input),rel=relative(root,absolute);
  check(rel.startsWith('..')||isAbsolute(rel),'Credential file must remain outside workspace.');
  const content=readFileSync(absolute,'utf8').replace(/^\uFEFF/,'').trim();
  const matches=[...content.matchAll(/\bsk_[a-zA-Z0-9_-]+\b/g)].map(m=>m[0]);
  const value=matches.length===1?matches[0]:content;
  check(value.length>=20&&!/\s/.test(value),'Expected exactly one API key.');
  return value;
}
function group(text,completion) {
  if(/Có [34] Chủ đề/.test(text))return 'level-selection';
  if(/Chủ đề \d+ bạn đã học xong rồi/.test(text))return text.startsWith('Mình chưa hiểu.')?'topic-replay-recovery':'topic-replay';
  if(!text.startsWith('Mình chưa hiểu.'))return 'active-screen';
  if(completion.has(text.slice('Mình chưa hiểu. '.length)))return 'completion-recovery';
  if(/Ba mẹ|Ngôi sao|Luyện lại|nội dung khác|nghe câu trước/.test(text))return 'vocabulary-recovery';
  return 'navigation-recovery';
}
function protectedUnchanged(plan) {
  for(const p of plan.protectedFiles)check(hash(read(p.path))===p.sha256,`Protected learning/data source changed: ${p.path}`);
}
function validate(plan) {
  check(plan.modelId==='eleven_v3'&&JSON.stringify(plan.profiles)===JSON.stringify(profiles),'Incorrect synthesis profile.');
  check(plan.prompts.length===66&&new Set(plan.prompts.map(p=>p.text)).size===66,'Expected 66 reviewed fixed prompts.');
  check(plan.auditSha256===hash(read(audit)),'Frozen audit changed; do not generate from stale plan.');
  for(const p of plan.prompts)check(/^GAP66-\d{3}$/.test(p.id)&&p.asset===`assets/audio/MAIN/GAP66/${p.id}.vi.v1.mp3`&&p.locale==='vi-VN','Unsafe or unexpected entry.');
  protectedUnchanged(plan);
}
function paths(p) {
  return {source:`${out}/sources/${p.id}.mp3`,receipt:`${out}/sources/${p.id}.json`,
    final:`${out}/ready/${p.id}.mp3`,finalReceipt:`${out}/ready/${p.id}.json`,attempt:`${out}/attempts/${p.id}.json`};
}
function settings(p) {
  return {text:p.text,model_id:'eleven_v3',language_code:p.voiceLanguage,seed:164109,
    voice_settings:{stability:0.5,similarity_boost:0.75,speed:1.0}};
}
function verify(p,decode=true) {
  const path=paths(p),receipt=json(path.finalReceipt),bytes=read(path.final);
  check(JSON.stringify(receipt.request)===JSON.stringify(settings(p))&&receipt.voiceId===profiles[p.voiceLanguage].voiceId&&
    receipt.speed===profiles[p.voiceLanguage].speed&&receipt.speedMethod==='ffmpeg-atempo'&&
    receipt.finalSha256===hash(bytes)&&receipt.sourceSha256===hash(read(path.source))&&
    bytes.length>1000&&bytes.length<=2*1024*1024&&receipt.durationSeconds>0&&receipt.durationSeconds<=45&&
    Math.abs(receipt.durationSeconds-receipt.sourceDurationSeconds/receipt.speed)<=0.25,`Invalid audio/receipt: ${p.id}`);
  if(decode)execFileSync('ffmpeg',['-hide_banner','-v','error','-i',resolve(root,path.final),'-f','null','-'],{stdio:'pipe'});
  return receipt;
}
async function generate(p,secret) {
  const path=paths(p),request=settings(p),profile=profiles[p.voiceLanguage];
  if(existsSync(resolve(root,path.finalReceipt)))return verify(p);
  if(!existsSync(resolve(root,path.receipt))) {
    check(!existsSync(resolve(root,path.attempt)),`STOP: prior attempt ${p.id}; inspect provider history, no automatic paid retry.`);
    save(path.attempt,{id:p.id,status:'request-started',at:new Date().toISOString(),request});
    const response=await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${profile.voiceId}?output_format=mp3_44100_128`,{
      method:'POST',redirect:'error',signal:AbortSignal.timeout(120000),
      headers:{'xi-api-key':secret,'Content-Type':'application/json',Accept:'audio/mpeg'},body:JSON.stringify(request)});
    if(!response.ok){
      const body=await response.json().catch(()=>({}));
      const status=typeof body.detail?.status==='string'?body.detail.status.replace(/[^a-zA-Z0-9_-]/g,''):'';
      save(path.attempt,{id:p.id,status:'rejected',httpStatus:response.status,providerStatus:status});
      throw Error(`ElevenLabs HTTP ${response.status} ${status}; stopped before next request.`);
    }
    check(response.headers.get('content-type')?.includes('audio/'),'Provider returned non-audio content.');
    const bytes=Buffer.from(await response.arrayBuffer());
    check(bytes.length>1000,'Provider response too short.');
    mkdirSync(dirname(resolve(root,path.source)),{recursive:true});
    writeFileSync(resolve(root,path.source),bytes,{flag:'wx'});
    save(path.receipt,{id:p.id,provider:'elevenlabs',voiceId:profile.voiceId,request,
      requestId:response.headers.get('request-id'),historyItemId:response.headers.get('history-item-id'),
      characterCost:response.headers.get('character-cost'),createdAt:new Date().toISOString(),sourceSha256:hash(bytes)});
    save(path.attempt,{id:p.id,status:'source-received',at:new Date().toISOString()});
  }
  const receipt=json(path.receipt);
  check(JSON.stringify(receipt.request)===JSON.stringify(request)&&receipt.voiceId===profile.voiceId&&receipt.sourceSha256===hash(read(path.source)),`Cached source mismatch: ${p.id}`);
  mkdirSync(dirname(resolve(root,path.final)),{recursive:true});
  // The neutral provider output is slowed once, preserving pitch. App plays 1x.
  check(!existsSync(resolve(root,path.final)),`Unreceipted staged output exists: ${p.id}; verify manually.`);
  execFileSync('ffmpeg',['-hide_banner','-loglevel','error','-n','-i',resolve(root,path.source),'-af',`atempo=${profile.speed}`,
    '-map_metadata','-1','-c:a','libmp3lame','-b:a','128k','-ar','44100','-ac','1',resolve(root,path.final)],{stdio:'pipe'});
  save(path.finalReceipt,{...receipt,asset:p.asset,finalSha256:hash(read(path.final)),sourceDurationSeconds:probe(path.source),
    durationSeconds:probe(path.final),speed:profile.speed,speedMethod:'ffmpeg-atempo',bytes:read(path.final).length});
  return verify(p);
}
async function main(){
  if(mode==='prepare') {
    check(!existsSync(resolve(root,`${out}/plan.json`)),'Plan already exists.');
    const missing=json(audit).missing;
    check(missing.length===66&&missing.every(p=>p.locale==='vi-VN'),'Audit no longer has 66 Vietnamese gaps.');
    const completion=new Set(json('deliverables/audio-runtime-audit-2026-09-17/fresh-domain-audit.json').rows.filter(r=>r.family==='completion'&&r.scope==='current').map(r=>r.text));
    const old=['assets/data/main_assistant_audio.json','assets/data/curriculum_audio.json'];
    const oldPrompts=old.flatMap(p=>json(p).prompts);
    for(const p of missing)check(!oldPrompts.some(x=>x.enabled&&(x.text===p.text||(x.lookupTexts??[]).includes(p.text))),'A reviewed gap is already covered.');
    const protectedFiles=[...walk('lib').filter(p=>p.endsWith('.dart')&&p!=='lib/core/audio/voice_prompt_service.dart'),...old,'assets/data/listening_lessons.json'];
    const prompts=missing.map((p,i)=>{
      const id=`GAP66-${String(i+1).padStart(3,'0')}`;
      return {id,text:p.text,locale:p.locale,voiceLanguage:'vi',version:1,enabled:false,
        group:`gap66-${group(p.text,completion)}`,asset:`assets/audio/MAIN/GAP66/${id}.vi.v1.mp3`,
        sources:[...new Set(p.evidence.map(e=>e.source))]};
    });
    save(`${out}/plan.json`,{schemaVersion:1,provider:'elevenlabs',modelId:'eleven_v3',profiles,
      auditSha256:hash(read(audit)),characters:prompts.reduce((n,p)=>n+[...p.text].length,0),
      protectedFiles:protectedFiles.map(path=>({path,sha256:hash(read(path))})),prompts});
  }
  if(!existsSync(resolve(root,`${out}/plan.json`))){console.log('Run prepare first. No API calls.');return;}
  const plan=json(`${out}/plan.json`);validate(plan);
  const requested=option('--group');
  const selected=plan.prompts.filter(p=>!requested||p.group===requested);
  check(selected.length>0,'Unknown/empty group.');
  if(mode==='check-account') {
    const response=await fetch('https://api.elevenlabs.io/v1/user/subscription',{headers:{'xi-api-key':key()},redirect:'error',signal:AbortSignal.timeout(20000)});
    const body=await response.json().catch(()=>({}));
    console.log(JSON.stringify({httpStatus:response.status,requiredCharacters:plan.characters,
      remainingCharacters:typeof body.character_limit==='number'?body.character_limit-body.character_count:null}));return;
  }
  if(mode==='generate') {
    execFileSync('ffmpeg',['-version'],{stdio:'ignore'});execFileSync('ffprobe',['-version'],{stdio:'ignore'});
    const secret=key();
    for(const [i,p] of selected.entries()) {
      const receipt=await generate(p,secret);
      console.log(JSON.stringify({ready:i+1,total:selected.length,id:p.id,group:p.group,duration:receipt.durationSeconds,cost:receipt.characterCost}));
    }
  }
  if(['verify','install'].includes(mode)) {
    const receipts=selected.map(p=>({p,receipt:verify(p)}));
    if(mode==='install') {
      check(requested,'Install explicitly one --group at a time.');
      const manifest=existsSync(resolve(root,manifestPath))?json(manifestPath):
        {schemaVersion:1,enabled:true,provider:'elevenlabs',modelId:'eleven_v3',profiles,prompts:plan.prompts.map(p=>({...p}))};
      check(manifest.prompts.length===66,'Unexpected live pack.');
      for(const {p,receipt} of receipts) {
        const live=manifest.prompts.find(x=>x.id===p.id);
        check(live&&live.text===p.text&&live.group===p.group&&live.asset===p.asset,'Live entry changed.');
        mkdirSync(dirname(resolve(root,p.asset)),{recursive:true});
        if(existsSync(resolve(root,p.asset)))check(hash(read(p.asset))===receipt.finalSha256,'Will not overwrite a different installed recording.');
        else copyFileSync(resolve(root,paths(p).final),resolve(root,p.asset));
        Object.assign(live,{enabled:true,sha256:receipt.finalSha256,durationSeconds:receipt.durationSeconds,
          voiceId:receipt.voiceId,speed:receipt.speed,speedMethod:receipt.speedMethod});
      }
      save(manifestPath,manifest);
    }
    save(`${out}/${mode}${requested?'-'+requested:''}-result.json`,{at:new Date().toISOString(),count:receipts.length,
      receipts:receipts.map(({p,receipt})=>({id:p.id,...receipt}))});
  }
  protectedUnchanged(plan);
  console.log(JSON.stringify({mode,characters:plan.characters,total:plan.prompts.length,
    groups:Object.fromEntries([...new Set(plan.prompts.map(p=>p.group))].map(g=>[g,plan.prompts.filter(p=>p.group===g).length])),protectedSourcesUnchanged:true}));
}
const mutating=['prepare','generate','install'].includes(mode);
const lock=resolve(root,`${out}/production.lock`);
let locked=false;
try {
  if(mutating){mkdirSync(dirname(lock),{recursive:true});writeFileSync(lock,String(process.pid),{flag:'wx'});locked=true;}
  await main();
} catch(error) {
  // Never serialize fetch errors, headers, credential contents or provider bodies.
  console.error(error instanceof Error?error.message:'Audio production failed.');process.exitCode=1;
} finally {if(locked)unlinkSync(lock);}
