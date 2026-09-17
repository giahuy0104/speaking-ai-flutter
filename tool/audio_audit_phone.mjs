// ADB diagnostic helper. Captures UI and audio-source logs only for HOMI.
import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
const adb = 'C:/Users/DELL/AppData/Local/Android/Sdk/platform-tools/adb.exe';
const serial = 'ORH6S4ZT85BMWGSK';
const out = 'deliverables/audio-runtime-audit-2026-09-17';
mkdirSync(out, {recursive:true});
const call=(...args)=>execFileSync(adb,['-s',serial,...args],{encoding:'utf8',maxBuffer:24*1024*1024,windowsHide:true,stdio:['ignore','pipe','pipe']});
const [command='snapshot', label='latest'] = process.argv.slice(2);
if (!/^[a-zA-Z0-9_-]+$/.test(label)) throw Error('Invalid evidence label');
const decode=s=>s.replace(/&#(\d+);/g,(_,n)=>String.fromCharCode(Number(n)))
  .replaceAll('&amp;','&').replaceAll('&quot;','"').replaceAll('&lt;','<').replaceAll('&gt;','>');
if(command==='snapshot') {
  call('shell','uiautomator','dump','/sdcard/homi-audio-audit-ui.xml');
  const xml=call('shell','cat','/sdcard/homi-audio-audit-ui.xml');
  writeFileSync(`${out}/${label}.xml`,xml);
  for(const match of xml.matchAll(/<node\s+([^>]+)/g)){
    const props=Object.fromEntries([...match[1].matchAll(/([\w-]+)="([^"]*)"/g)].map(m=>[m[1],decode(m[2])]));
    if(props.text || props['content-desc']) console.log(JSON.stringify({text:props.text,desc:props['content-desc'],bounds:props.bounds,click:props.clickable==='true'}));
  }
} else if(command==='logs') {
  const log=call('logcat','-d','-v','threadtime','-s','flutter:I');
  const events=[...log.matchAll(/HOMI_AUDIO_AUDIT (\{[^\r\n]+\})/g)].map(m=>{try{return JSON.parse(m[1]);}catch{return null;}}).filter(Boolean);
  writeFileSync(`${out}/${label}-events.json`,JSON.stringify(events,null,2));
  const manifest=['main_assistant_audio','curriculum_audio'].flatMap(n=>JSON.parse(readFileSync(`assets/data/${n}.json`)).prompts);
  const byHash=new Map(manifest.map(p=>[p.sha256,p]));
  const priorPath=`${out}/last-log-count.json`;
  const prior=existsSync(priorPath)?JSON.parse(readFileSync(priorPath)).count:0;
  for(const e of events.slice(Math.min(prior,events.length))) {
    const p=byHash.get(e.sha256);
    if(e.event==='request' || e.error || e.asset) console.log(JSON.stringify({...e,...(p?{id:p.id,text:p.text,locale:p.locale}: {})}));
  }
  writeFileSync(priorPath,JSON.stringify({count:events.length}));
  console.log(JSON.stringify({totalEvents:events.length,tts:events.filter(e=>e.event==='request'&&e.source==='native_tts').length,authored:events.filter(e=>e.event==='request'&&e.source==='authored_mp3').length}));
} else if(command==='screenshot') {
  call('shell','screencap','-p','/sdcard/homi-audio-audit.png');
  console.log(call('pull','/sdcard/homi-audio-audit.png',`${out}/${label}.png`));
} else {throw Error('Unsupported diagnostic command');}
