// Local diagnostic: reads runtime/domain evidence and verifies existing assets.
// Run the companion Flutter diagnostic first, then: node tool/audit_homi_audio.mjs
// Writes ONLY deliverables/homi-*.json/csv. Never generates speech or edits app.
import {readFileSync, writeFileSync, readdirSync, existsSync} from 'node:fs';
import {resolve, dirname, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = path => readFileSync(resolve(root, path), 'utf8');
const json = path => JSON.parse(read(path));
const domainPath = process.env.HOMI_AUDIT_DOMAIN || 'deliverables/homi-runtime-domain-audit.json';
const outputDir = process.env.HOMI_AUDIT_OUTPUT_DIR || 'deliverables';
const domain = json(domainPath);
const content = json('assets/data/listening_lessons.json');
const manifests = ['assets/data/main_assistant_audio.json', 'assets/data/curriculum_audio.json',
  ...(process.env.HOMI_AUDIT_EXTRA_MANIFESTS || '').split(',').filter(Boolean)]
  .map(path => ({path, ...json(path)}));
const prompts = manifests.flatMap(m => m.prompts.map(p => ({...p, manifest: m.path, manifestEnabled: m.enabled})));
const entries = new Map();
const lineOf = (source, text) => {
  const s = read(source), at = s.indexOf(text);
  return at < 0 ? null : s.slice(0, at).split('\n').length;
};
function add(text, family, source, options = {}) {
  if (typeof text !== 'string' || !text.trim()) return;
  const {scope = 'current', locale = 'vi-VN', route = 'asset_first_then_device_tts', ...rest} = options;
  const key = `${locale}|${text.trim()}`;
  const row = entries.get(key) ?? {text: text.trim(), locale, occurrences: []};
  const occurrence = {scope, family, source, route, ...rest};
  if (!row.occurrences.some(x => JSON.stringify(x) === JSON.stringify(occurrence))) row.occurrences.push(occurrence);
  entries.set(key, row);
}
for (const row of domain.rows) {
  const {text, family, source, ...rest} = row;
  add(text, family, source, rest);
}
const masterNavigationPath = 'lib/features/voice_navigation/domain/master_navigation_contract.dart';
const masterNavigationSource = read(masterNavigationPath).split('static const allowedStates')[0];
for (const match of masterNavigationSource.matchAll(/static const(?: String)?\s+(\w+)\s*=\s*'([^']+)'/gu)) {
  if (match[1] === 'version') continue;
  add(match[2], 'master_navigation_contract', masterNavigationPath, {
    line: lineOf(masterNavigationPath, match[2]),
    evidence: 'source_traced',
  });
}
const base = 'lib/features/listening/presentation/';
const practice = `${base}lesson_practice_screen.dart`;
const intro = `${base}lesson_intro_screen.dart`;
const topicScreen = `${base}topic_listening_screen.dart`;
add('Mình tiếp tục câu thử thách nhé.', 'challenge_resume_shadowed_by_uri', intro,
  {scope:'conditional', route:'only_if_intro_uri_absent_or_relearn_forces_text'});
let coreOccurrences = 0, challengeOccurrences = 0, recognitionVariants = 0;
const directLinks = [];
function linked(text, locale, uri, family, context, source) {
  add(text, family, source, {locale, context, uri, route: uri ? 'direct_audio_uri' : 'asset_first_then_device_tts'});
  if (uri) directLinks.push({text, locale, uri, family, context});
}
for (const group of content.groups) {
  for (const topic of group.topics) {
    add(`Mình học tiếp Chủ đề ${topic.number} nhé.`, 'topic_resume', topicScreen,
      {line: lineOf(topicScreen, "'Mình học tiếp Chủ đề")});
    add(`Chủ đề ${topic.number} bạn đã học xong rồi. Bạn muốn học chủ đề khác hay học lại?`,
      'topic_replay', topicScreen, {line: lineOf(topicScreen, "'Chủ đề $topicNumber bạn")});
    for (const lesson of topic.lessons) {
      linked(lesson.intro, 'vi-VN', lesson.introAudioUrl, 'lesson_intro_clip', lesson.id, intro);
      add(lesson.outro, 'lesson_outro', 'assets/data/listening_lessons.json', {scope: 'catalog_only'});
      for (const sentence of lesson.sentences) {
        linked(sentence.english, 'en-US', sentence.audioUrl, 'core_en', sentence.id, practice);
        linked(sentence.vietnamese, 'vi-VN', sentence.vietnameseAudioUrl, 'core_vi', sentence.id, practice);
        coreOccurrences += 2;
        recognitionVariants += (sentence.recognitionVariants ?? []).length;
      }
      for (const question of lesson.challengeBank ?? []) {
        add(question.prompt, 'challenge_question', `${base}lesson_challenge_screen.dart`, {context: question.id});
        add(question.correctAnswer, 'challenge_answer_en', `${base}lesson_challenge_screen.dart`, {locale:'en-US', context: question.id});
        // Current parent passes no onNeedsPractice callback; review persistence
        // stores the corresponding CORE, not this alternate Vietnamese answer.
        add(question.correctVietnamese, 'challenge_answer_vi', 'assets/data/listening_lessons.json', {scope: 'catalog_only', context: question.id});
        challengeOccurrences++;
      }
      const introLead = `${lesson.number === 1 ? `Chủ đề ${topic.number}. Bài đầu tiên là` : 'Bài này là'} ${lesson.titleEn}. ${lesson.entry?.text ?? ''} Bắt đầu nhé.`.replace(/\s+/g,' ').trim();
      add(introLead, 'intro_display_shadowed_by_uri', intro, {scope:'conditional', route:'only_if_intro_uri_absent', context:lesson.id});
      add(`Mình học tiếp bài ${lesson.titleEn} nhé.`, 'resume_display_shadowed_by_uri', intro,
        {scope:'conditional', route:'only_if_intro_uri_absent', context:lesson.id});
      add(`Mình học lại bài ${lesson.titleEn} nhé.`, 'lesson_relearn', intro, {context:lesson.id});
      for (let n = 1; n <= lesson.sentences.length; n++) {
        add(`Bài này bạn còn ${n} Ngôi sao chưa chinh phục.${group.startAge <= 10 ? ' Mình cùng thử nhé!' : ''}`, 'remaining_stars', intro);
      }
      add(`Bạn đã hoàn thành Bài ${lesson.number} rồi!`, 'lesson_milestone', practice);
      if (lesson.number < topic.lessons.length) add(`Bạn cần học xong Bài ${lesson.number} trước nhé.`,
        'lesson_locked', `${base}topic_lesson_list_screen.dart`);
      if (lesson.songTitle) {
        add(`Mình nghe lại bài hát ${lesson.songTitle} nhé.`, 'song_resume_shadowed_by_uri', intro,
          {scope:'conditional', route:'only_if_intro_uri_absent'});
      }
      if (lesson.rolePlay) {
        for (const field of ['scenarioVi', 'openingHint']) add(lesson.rolePlay[field], 'roleplay',
          'assets/data/listening_lessons.json', {scope:'catalog_only', context:lesson.id});
        for (const turn of lesson.rolePlay.turns ?? []) {
          add(turn.english, 'roleplay', 'assets/data/listening_lessons.json', {scope:'catalog_only', locale:'en-US', context:lesson.id});
          add(turn.vietnamese, 'roleplay', 'assets/data/listening_lessons.json', {scope:'catalog_only', context:lesson.id});
        }
      }
    }
    add(`Bạn đã hoàn thành Chủ đề ${topic.number} rồi!`, 'topic_milestone', practice);
  }
  for (const level of group.levels ?? []) {
    // No locked Level 4 in the supplied curriculum; "finish Level 3 first"
    // is therefore NOT included as a current utterance.
    if (level.number < group.levels.at(-1).number) {
      add(`Bạn cần hoàn thành Level ${level.number} trước nhé.`, 'level_locked', topicScreen,
        {line: lineOf(topicScreen, "'Bạn cần hoàn thành Level")});
      add(`Bạn đã hoàn thành Level ${level.number} rồi!`, 'level_milestone', practice);
    }
    for (const q of level.missionBank ?? []) {
      add(q.prompt, 'mission', 'assets/data/listening_lessons.json', {scope:'catalog_only', context:q.id});
      add(q.correctAnswer, 'mission', 'assets/data/listening_lessons.json', {scope:'catalog_only', locale:'en-US', context:q.id});
      add(q.correctVietnamese, 'mission', 'assets/data/listening_lessons.json', {scope:'catalog_only', context:q.id});
    }
  }
}

// Supplement actual domain execution with manually traced UI/audio entry points.
// Only literal call arguments and explicit spokenReply/GuidePrompt payloads are
// extracted. This intentionally does not count arbitrary display strings as speech.
function walk(dir) {
  return readdirSync(resolve(root,dir), {withFileTypes:true}).flatMap(e =>
    e.isDirectory() ? walk(`${dir}/${e.name}`) : [`${dir}/${e.name}`]);
}
const sourceFiles = walk('lib').filter(p => p.endsWith('.dart'));
const callsites = [];
const str = String.raw`'(?:[^'\\]|\\.)*'`;
const joined = `(${str}(?:\\s+${str})*)`;
function decodeDart(literals) {
  return [...literals.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map(m => m[1]
    .replace(/\\'/g,"'").replace(/\\n/g,'\n').replace(/\\r/g,'\r').replace(/\\t/g,'\t').replace(/\\\\/g,'\\')).join('');
}
for (const path of sourceFiles) {
  const source = read(path);
  source.split(/\r?\n/).forEach((line,i) => {
    if (/\b(?:speak(?:AndWait\w*)?|speakAssistantPrompt|_speak\w*|_playPrompt|_playGuideCue\w*|playToCompletion)\s*\(/.test(line)) {
      callsites.push({source:path,line:i+1,code:line.trim()});
    }
  });
  if (!path.includes('/presentation/') && !path.startsWith('lib/app/') && !path.startsWith('lib/core/session/')) continue;
  const patterns = [
    ['literal_speech_call', new RegExp(`(?:speakAndWait\\w*|speakAssistantPrompt|_speakPromptAndWait|_speakLessonPrompt|_speakOnSelectedOutput)\\(\\s*${joined}`, 'g')],
    ['module_reply', new RegExp(`spokenReply:\\s*${joined}`, 'g')],
    ['local_guide', new RegExp(`LessonGuidePrompt\\(\\s*audioCode:\\s*${str},\\s*text:\\s*${joined}`, 'g')],
  ];
  for (const [family, regex] of patterns) for (const match of source.matchAll(regex)) {
    const text = decodeDart(match[1]);
    if (!text || text.includes('$')) continue;
    const prior = source.slice(Math.max(0,match.index-140),match.index);
    const handled = family==='module_reply' && /ActiveLearningCommandResult\.handled\(\s*$/.test(prior);
    const legacyReview = /\/(lesson_review_screen|song_karaoke_screen)\.dart$/.test(path);
    add(text, family, path, {scope:handled ? 'not_spoken_handled_reply' : legacyReview ? 'compatibility' : 'current',
      line:source.slice(0,match.index).split('\n').length, evidence:'source_traced'});
  }
}
for (const [text,source,anchor,family] of [
  ['Cô chưa mở được micro để dịch liên tục. Con kiểm tra quyền micro rồi thử lại nhé.', 'lib/app/ai_speaking_app.dart','Cô chưa mở được micro', 'microphone_error'],
  ['Cô chưa nghe thấy bạn nói. Bạn nói lại nhé.', 'lib/features/conversation/presentation/conversation_controller.dart','_unclearSpeechMessage', 'conversation_unclear'],
  ['Bài học chưa có Challenge hợp lệ cho từng Core.', practice, 'Bài học chưa có Challenge', 'invalid_curriculum'],
]) {
  if (!read(source).includes(text)) throw new Error(`Outdated audit literal: ${text}`);
  add(text, family, source, {line:lineOf(source,anchor), evidence:'source_traced'});
}
// AI-069 is resolved by the wake-word controller (not MainVoiceAssistantFlow).
const catalogDart = read('lib/features/voice_navigation/domain/homi_fallback_catalog.dart');
const wake = catalogDart.match(/'AI-069':\s*'([^']+)'/);
if (wake) add(wake[1], 'wake_word', 'lib/features/voice_navigation/application/voice_navigation_controller.dart', {line:560});
// Preserve every recording in the ledger without mistaking it for a reached
// utterance. In particular "Bắt đầu nào." is declared but unused in Vocab V3.
for (const p of prompts) {
  if (!entries.has(`${p.locale}|${p.text.trim()}`)) {
    add(p.text, 'audio_not_traced', p.manifest, {scope:'audio_catalog_only', locale:p.locale, route:'not_established'});
  }
}

const pubspec = read('pubspec.yaml');
const registered = [...pubspec.matchAll(/^\s*-\s+(assets\/[^\r\n]+)\s*$/gm)].map(m=>m[1].trim());
const isBundled = p => registered.includes(p) || registered.some(d => d.endsWith('/') && p.startsWith(d) && !p.slice(d.length).includes('/'));
const assetChecks = new Map();
for (const prompt of prompts) {
  if (assetChecks.has(prompt.asset)) continue;
  const exists = existsSync(resolve(root,prompt.asset));
  const bytes = exists ? readFileSync(resolve(root,prompt.asset)) : null;
  let remoteConfigured = false;
  try {
    const remote = new URL(prompt.url);
    remoteConfigured = remote.protocol === 'https:' && remote.hostname === 'res.cloudinary.com';
  } catch {}
  assetChecks.set(prompt.asset, {asset:prompt.asset, exists, bundled:isBundled(prompt.asset),
    checksumValid:!!bytes && createHash('sha256').update(bytes).digest('hex')===prompt.sha256,
    withinRuntimeLimits:!!bytes && bytes.length<=2*1024*1024 && prompt.durationSeconds>0 && prompt.durationSeconds<=45,
    remoteConfigured, runtimeReachable:isBundled(prompt.asset)||remoteConfigured});
}
const audioMatches = (text,locale) => prompts.filter(p => p.enabled && p.manifestEnabled &&
  (p.text===text.trim() || (p.lookupTexts??[]).includes(text.trim())) &&
  (p.locale===locale || (p.lookupLocales??[]).includes(locale)));
const rows = [...entries.values()].map(row => {
  const matches = audioMatches(row.text,row.locale);
  const audio = matches.length===1 ? matches[0] : null;
  const check = audio ? assetChecks.get(audio.asset) : null;
  return {...row, scopes:[...new Set(row.occurrences.map(o=>o.scope))],
    audioStatus:!matches.length ? 'missing_exact_audio' : matches.length>1 ? 'ambiguous_audio_match' :
      !check.exists || !check.checksumValid || !check.withinRuntimeLimits || !check.runtimeReachable ? 'invalid_audio' : 'ready',
    audio:audio ? {id:audio.id,asset:audio.asset,voiceLanguage:audio.voiceLanguage} : null};
}).sort((a,b)=>a.text.localeCompare(b.text,'vi') || a.locale.localeCompare(b.locale));
const directLinkChecks = directLinks.map(link => {
  const asset = link.uri.startsWith('asset:///') ? decodeURIComponent(link.uri.slice('asset:///'.length)) : null;
  const remoteConfigured = link.uri.startsWith('https://res.cloudinary.com/');
  const match = prompts.find(p=>p.asset===asset || p.url===link.uri);
  return {...link, asset, exists:asset ? existsSync(resolve(root,asset)) : null,
    bundled:asset ? isBundled(asset) : null, remoteConfigured,
    transcriptMatchesManifest:match ? match.text===link.text.trim() && match.locale===link.locale : false};
});
const legacyAssets = walk('assets/audio').filter(p=>/\.(mp3|wav|ogg|m4a|aac)$/i.test(p) && !/\/(MAIN|CURRICULUM)\//.test(p));
const songLinks = content.groups.flatMap(g=>g.topics.flatMap(t=>t.lessons
  .filter(l=>l.songTitle).map(l=>{
    const asset = l.songAudioUrl?.replace(/^asset:\/\/\//,'');
    return {lesson:l.id,title:l.songTitle,uri:l.songAudioUrl,scope:'current_music_not_tts',
      exists:!!asset && existsSync(resolve(root,asset)), bundled:!!asset && isBundled(asset),
      transcriptVerified:false};
  })));
const codeLookupSources = ['lib/features/vocabulary/domain/vocabulary_flow_v3.dart',
  'lib/features/listening/domain/lesson_guide_flow.dart', practice];
const lookupCodes = new Set(codeLookupSources.flatMap(p=>[...read(p).matchAll(/(?:stateId|audioCode):\s*'([^'$]+)'/g)].map(m=>m[1].toLowerCase())));
const legacyCodeOverrides = legacyAssets.filter(p=>lookupCodes.has(basename(p).replace(/\.[^.]+$/,'' ).toLowerCase()));
const summary = {
  date:'2026-09-17', scope:'local working tree; code/catalog audit, not device/acoustic verification',
  groups:content.groups.length, topics:content.groups.reduce((n,g)=>n+g.topics.length,0),
  lessons:content.groups.flatMap(g=>g.topics).reduce((n,t)=>n+t.lessons.length,0),
  coreOccurrences, challengeOccurrences, recognitionVariantsNotCountedAsOutput:recognitionVariants,
  domainScenarios:domain.scenarios, domainTransitions:domain.transitions, reachedStages:domain.reachedStages,
  audioFiles:assetChecks.size, audioIntegrityFailures:[...assetChecks.values()].filter(c=>
    !c.exists||!c.checksumValid||!c.withinRuntimeLimits||!c.runtimeReachable),
  directLinks:directLinks.length, directLinkFailures:directLinkChecks.filter(c=>
    !(c.bundled||c.remoteConfigured)||!c.transcriptMatchesManifest),
  currentUniqueTextLocale:rows.filter(r=>r.scopes.includes('current')).length,
  currentReady:rows.filter(r=>r.scopes.includes('current')&&r.audioStatus==='ready').length,
  currentMissing:rows.filter(r=>r.scopes.includes('current')&&r.audioStatus!=='ready').map(({text,locale,audioStatus,occurrences})=>
    ({text,locale,audioStatus,evidence:occurrences.filter(o=>o.scope==='current')})),
  byScope:Object.fromEntries([...new Set(rows.flatMap(r=>r.scopes))].map(scope=>[scope,{
    unique:rows.filter(r=>r.scopes.includes(scope)).length,
    missing:rows.filter(r=>r.scopes.includes(scope)&&r.audioStatus!=='ready').length,
  }])),
  byCurrentFamily:Object.fromEntries([...new Set(rows.flatMap(r=>r.occurrences.filter(o=>o.scope==='current').map(o=>o.family)))].sort().map(family=>[family,{
    unique:rows.filter(r=>r.occurrences.some(o=>o.scope==='current'&&o.family===family)).length,
    missing:rows.filter(r=>r.occurrences.some(o=>o.scope==='current'&&o.family===family)&&r.audioStatus!=='ready').length,
  }])),
  legacyAudioFiles:legacyAssets.length, legacyCodeOverrides, songLinks,
  limitations:[
    'Branch audit uses concrete domain execution plus manually traced UI templates, not formal exhaustive reachability.',
    'Current text counts deduplicate exact text + requested locale; families/scopes overlap and must not be summed.',
    'No microphone, physical MAIN, BLE, real phone playback or listening/transcription of MP3 contents was performed.',
    'Metadata/checksum verifies file identity, not whether acoustic speech is correct.',
    'User vocabulary, translations and server audio are unbounded; no device store or production backend was read.',
    'Recognition variants and child command corpus are input data, not automatically outgoing speech.',
    'Legacy raw MP3 cue transcripts are not available in the current data; these are listed separately, not invented.',
  ],
};
const save = (name,value) => writeFileSync(resolve(root,`${outputDir}/${name}`),`${JSON.stringify(value,null,2)}\n`);
const dynamicFamilies = [
  {id:'parent_vocabulary', finite:false, text:'VocabularyEntry.word / meaning', locales:['en-US','vi-VN'],
    source:'lib/features/vocabulary/presentation/vocabulary_home_screen.dart:1989',
    route:'dictionary remote TTS + local cache first; callback to authored wrapper then device TTS on failure',
    note:'Applies to parent-origin entries even when displayed in Today, Review or Stars. Local device store not read.'},
  {id:'suggested_parent_sentences', finite:false, text:'I can {word}. / This is my {word}. / It is {color}. / corresponding Vietnamese',
    source:'lib/features/vocabulary/application/local_vocabulary_suggestion_provider.dart',
    route:'Only becomes speakable after user selects/saves; then uses vocabulary entry route'},
  {id:'offline_translation', finite:false, text:'Translated English result', locales:['en-US'],
    source:'lib/features/conversation/presentation/conversation_controller.dart:3714',
    route:'Android styled device TTS bypasses authored lookup; other wrapper calls match assets if exact, otherwise device TTS'},
  {id:'online_translation', finite:false, text:'Backend-generated translation or local rule result',
    source:'lib/features/conversation/presentation/conversation_controller.dart:3624',
    route:'preferredPlaybackUri or result.audioUri played directly; no URI means no playback at this callsite',
    note:'Production synthesis provider/model not verified; cannot label this Eleven v3 merely from frontend manifests.'},
  {id:'history', finite:false, text:'Previously stored translations',
    source:'lib/features/conversation/presentation/conversation_controller.dart:3880',
    route:'Replay stored audioUri; no new fixed authored sentence'},
  {id:'child_recordings', finite:false, isHomiSpeech:false,
    source:'lib/features/vocabulary/presentation/vocabulary_home_screen.dart:1519',
    route:'Stored child voice in Stars/recording history; exclude from HOMI synthesis inventory'},
];
save('homi-speech-audit-summary.json',summary);
save('homi-speech-inventory.json',rows);
save('homi-speech-callsites.json',callsites);
save('homi-speech-assets.json',{assets:[...assetChecks.values()],directLinkChecks,legacyAssets,songLinks});
save('homi-speech-dynamic-families.json',dynamicFamilies);
save('homi-speech-provenance.json', [...sourceFiles, ...manifests.map(m=>m.path),
  'assets/data/listening_lessons.json','pubspec.yaml',domainPath,
  'tool/audit_homi_utterances_test.dart','tool/audit_homi_audio.mjs',
].map(path=>({path,sha256:createHash('sha256').update(read(path)).digest('hex')})));
const csv = value => `"${String(value??'').replaceAll('"','""')}"`;
writeFileSync(resolve(root,`${outputDir}/homi-speech-inventory.csv`),'\uFEFF'+[
  ['text','locale','scopes','audio_status','asset','families','sources'].map(csv).join(','),
  ...rows.map(r=>[r.text,r.locale,r.scopes.join(';'),r.audioStatus,r.audio?.asset,
    [...new Set(r.occurrences.map(o=>o.family))].join(';'),
    [...new Set(r.occurrences.map(o=>o.source+(o.line?`:${o.line}`:'')))].join(';')].map(csv).join(',')),
].join('\r\n')+'\r\n');
console.log(JSON.stringify({...summary,currentMissing:summary.currentMissing.map(x=>x.text)},null,2));
