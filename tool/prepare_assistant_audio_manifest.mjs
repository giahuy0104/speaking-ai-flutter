// Mechanically derive a reviewable fixed-prompt inventory from existing source.
// Does not modify conversational text, lesson IDs, progress or speech recognition.
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = resolve(root, 'assets/data/main_assistant_audio.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const previous = new Map(manifest.prompts.map(p => [p.text, p]));
const prompts = new Map();
const excludedDynamic = [];
const read = p => readFileSync(resolve(root, p), 'utf8');
const decode = s => s.replace(/\\'/g, "'").replace(/\\n/g, '\n').replace(/\\"/g, '"');
function add(id, text, source, language = 'vi') {
  text = decode(text).trim();
  if (!text) return;
  if (/[$\[\]{}\r\n]/u.test(text)) {
    excludedDynamic.push({ id, text, source }); return;
  }
  let entry = prompts.get(text);
  if (!entry) {
    entry = { ...(previous.get(text) ?? { id, text, locale: language === 'en' ? 'en-US' : 'vi-VN',
      version: 1, enabled: false, asset: `assets/audio/MAIN/${id}.${language}.v1.mp3` }),
      voiceLanguage: language, sources: [], aliases: [] };
    // Legacy learning prompts currently send English feedback using vi-VN.
    // Route only these explicitly listed English sentences to the English voice.
    if (language === 'en') entry.lookupLocales = ['en-US', 'vi-VN'];
    prompts.set(text, entry);
  }
  if (!entry.sources.includes(source)) entry.sources.push(source);
  if (!entry.aliases.includes(id)) entry.aliases.push(id);
}
const catalogPath = 'lib/features/voice_navigation/domain/homi_fallback_catalog.dart';
const catalog = read(catalogPath);
for (const m of catalog.matchAll(/'(AI-\d{3}|SIL-\d{3})':\s*'((?:\\.|[^'\\])*)'/gu)) add(m[1], m[2], catalogPath);
for (const m of catalog.matchAll(/'(FB-\d{3})': HomiFallbackPolicy\(([\s\S]*?)\n    \),/gu)) {
  for (const part of ['firstPrompt', 'secondPrompt']) {
    const text = m[2].match(new RegExp(`${part}:\\s*'((?:\\\\.|[^'\\\\])*)'`, 'u'))?.[1];
    if (text) add(`${m[1]}-${part === 'firstPrompt' ? '1' : '2'}`, text, catalogPath);
  }
}
let seq = 0;
function sentences(source, path, english = false) {
  // Exclude comments before collecting human-facing, capitalized full strings.
  source = source.replace(/^\s*\/\/.*$/gm, '');
  for (const m of source.matchAll(/'((?:\\.|[^'\\])*)'/gu)) {
    const text = decode(m[1]);
    if (!/^[A-ZÀ-ỸĐ]/u.test(text) || !/[ .!?]/u.test(text) || /[$\[\]{}\r\n]/u.test(text)) continue;
    if (!english && !/[À-ỹĐđ]/u.test(text)) continue;
    const language = /[À-ỹĐđ]/u.test(text) ? 'vi' : 'en';
    add(`RUN-${String(++seq).padStart(3, '0')}`, text, path, language);
  }
}
const flowPath = 'lib/features/voice_navigation/application/main_voice_assistant_flow.dart';
sentences(read(flowPath), flowPath);
add('MAIN-TRANSLATION-INTRO', 'Mình cùng dịch sang tiếng Anh nha. Bạn cứ nói từng câu. Muốn dừng thì nói “dừng lại”.', flowPath);
const vocabPath = 'lib/features/vocabulary/domain/vocabulary_flow_v3.dart';
sentences(read(vocabPath).split('static const List<VocabularyFixedPrompt>')[0], vocabPath);
const guidePath = 'lib/features/listening/domain/lesson_guide_flow.dart';
sentences(read(guidePath).split('static LessonGuidePrompt entry(')[0], guidePath, true);
const completionPath = 'lib/features/listening/domain/v4_completion_flow.dart';
sentences(read(completionPath).split('String v4CompletionActionLabel')[0], completionPath);
const spokenFiles = [
  'lib/features/listening/presentation/lesson_practice_screen.dart',
  'lib/features/listening/presentation/lesson_challenge_screen.dart',
  'lib/features/listening/presentation/topic_listening_screen.dart',
  'lib/features/vocabulary/presentation/vocabulary_home_screen.dart',
  'lib/features/vocabulary/presentation/vocabulary_practice_screen.dart',
];
for (const path of spokenFiles) {
  for (const m of read(path).matchAll(/(?:speakAndWait|_speakPrompt|_speakPromptAndWait|_speakGuide|_speakLessonPrompt)\(\s*'((?:\\.|[^'\\])*)'/gu)) {
    add(`RUN-${String(++seq).padStart(3, '0')}`, m[1], path);
  }
}
// Local guide objects and module replies are spoken by their callers, not by a
// direct string-literal speak() call. Keep them in the same exact-text allowlist.
function dartFiles(directory) {
  return readdirSync(resolve(root, directory), { withFileTypes: true }).flatMap(entry => {
    const path = `${directory}/${entry.name}`;
    return entry.isDirectory() ? dartFiles(path) : path.endsWith('.dart') ? [path] : [];
  });
}
let localSequence = 0;
for (const path of dartFiles('lib/features')) {
  const source = read(path);
  for (const m of source.matchAll(/LessonGuidePrompt\(\s*audioCode:\s*'([^']+)',\s*text:\s*'((?:\\.|[^'\\])*)'/gu)) {
    add(`LOCAL-${m[1]}`, m[2], path);
  }
  for (const m of source.matchAll(/spokenReply:\s*'((?:\\.|[^'\\])*)'/gu)) {
    add(`REPLY-${String(++localSequence).padStart(3, '0')}`, m[1], path);
  }
}
const reviewPath = 'lib/features/listening/presentation/lesson_review_screen.dart';
const reviewAnnouncement = read(reviewPath).split('Future<void> _announceLearnedReview()')[1]?.split('Future<void> _startLearning()')[0];
if (!reviewAnnouncement) throw new Error('Review announcement source boundary changed; inspect inventory.');
sentences(reviewAnnouncement, reviewPath);
add('CONVERSATION-UNCLEAR', 'Cô chưa nghe thấy con nói. Con nói lại nhé.', 'lib/features/conversation/presentation/conversation_controller.dart');
add('LESSON-INVALID-CHALLENGE', 'Bài học chưa có Challenge hợp lệ cho từng Core.', 'lib/features/listening/presentation/lesson_practice_screen.dart');
// These reviewed runtime variants cannot be rediscovered from literal strings
// alone (topic/level numbers, app-layer errors). Never drop their verified
// records when refreshing the older fixed-literal inventory.
for (const entry of previous.values()) {
  if (entry.batch === 'homi-runtime-gap28-2026-09-16') prompts.set(entry.text, entry);
}
manifest.prompts = [...prompts.values()];
if (new Set(manifest.prompts.map(p => p.id)).size !== manifest.prompts.length ||
    new Set(manifest.prompts.map(p => p.asset)).size !== manifest.prompts.length) {
  throw new Error('Generated IDs/assets collide with an existing entry. Assign a new ID before writing.');
}
manifest.scope = 'Fixed assistant, silence/fallback, navigation, vocabulary menu, coaching prompts and reviewed finite runtime variants. Open-ended content retains its existing routes.';
manifest.excludedDynamic = excludedDynamic;
const summary = { uniquePrompts: prompts.size, aliases: manifest.prompts.reduce((s,p)=>s+p.aliases.length,0),
  languages: Object.fromEntries(['vi','en'].map(l=>[l, manifest.prompts.filter(p=>p.voiceLanguage===l).length])),
  characters: manifest.prompts.reduce((s,p)=>s+[...p.text].length,0), dynamicExcluded: excludedDynamic.length };
if (process.argv.includes('--write')) writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify(summary));
for (const p of manifest.prompts) console.log(`${p.id} | ${p.voiceLanguage} | ${p.text}`);
