// Read-only by default. Build an exact-text inventory, reusing compatible v3
// recordings only; original packs and learning content are never rewritten.
import { readFileSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packsRoot = 'D:/Code/HuaMei/App_noi/Tao_audio_15th9';
const read = p => JSON.parse(readFileSync(resolve(root, p), 'utf8'));
const assistant = read('assets/data/main_assistant_audio.json');
const content = read('assets/data/listening_lessons.json');
const sourceManifest = read('assets/data/listening_audio_manifest_v4.json');
const target = resolve(root, 'deliverables/curriculum_audio_plan.json');
const previous = existsSync(target) ? JSON.parse(readFileSync(target, 'utf8')) : { prompts: [] };
const key = (text, language) => `${language}|${text.trim()}`;
const old = new Map(previous.prompts.map(p => [key(p.text, p.voiceLanguage), p]));
const available = new Map();
const templates = [];
function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
}
const packManifests = walk(packsRoot).filter(p => p.endsWith('manifest.json'));
for (const path of packManifests) {
  const pack = JSON.parse(readFileSync(path, 'utf8'));
  const voices = pack.voices ?? pack.configured_voices;
  if (pack.model_id !== 'eleven_v3' || !voices || !['en', 'vi'].every(l =>
    voices[l]?.id === assistant.profiles[l].voiceId && voices[l]?.speed === assistant.profiles[l].speed)) continue;
  if (!/atempo/i.test(pack.speed_method ?? '')) continue;
  for (const item of pack.assets ?? []) {
    if (!item.file || !item.text) continue;
    const file = resolve(dirname(path), 'MP3', item.file);
    if (!file.startsWith(resolve(dirname(path), 'MP3') + '\\') || !existsSync(file)) continue;
    const languages = [...new Set((item.segments ?? []).map(s => s.language).filter(l => ['en', 'vi'].includes(l)))];
    const language = item.language ?? (languages.includes('vi') ? 'vi' : languages.includes('en') ? 'en' : null);
    if (!language) continue;
    for (const text of new Set([item.source_text, item.text].filter(Boolean))) {
      const lookup = key(text, language);
      if (!available.has(lookup)) available.set(lookup, {
        file, packManifest: path, packAudioId: item.id ?? item.generation_key ?? item.file,
        sourceText: text, modelId: pack.model_id, profiles: assistant.profiles,
        speedMethod: pack.speed_method, segments: item.segments ?? [],
        sourceSha256: item.mp3_sha256 ?? null,
      });
    }
  }
}
const assistantByText = new Map(assistant.prompts.map(p => [key(p.text, p.voiceLanguage), p]));
const prompts = new Map();
function add(text, language, alias, kind) {
  if (typeof text !== 'string' || !text.trim()) return;
  text = text.trim();
  if (/[\[\]{}$]/u.test(text)) { templates.push({ alias, kind, text }); return; }
  const lookup = key(text, language);
  let entry = prompts.get(lookup);
  if (!entry) {
    const digest = createHash('sha256').update(lookup).digest('hex').slice(0, 24);
    const reusableAssistant = assistantByText.get(lookup);
    entry = {
      ...(old.get(lookup) ?? { id: `LESSON-${digest.toUpperCase()}`, text,
        locale: language === 'en' ? 'en-US' : 'vi-VN', voiceLanguage: language, version: 1,
        asset: reusableAssistant?.asset ?? `assets/audio/CURRICULUM/${digest}.${language}.v1.mp3`, enabled: false }),
      aliases: [], kinds: [],
      ...(reusableAssistant ? { reusableAssistantId: reusableAssistant.id,
        asset: reusableAssistant.asset, sha256: reusableAssistant.sha256,
        durationSeconds: reusableAssistant.durationSeconds, enabled: true } : {}),
      ...(!reusableAssistant && available.has(lookup) ? { importSource: available.get(lookup) } : {}),
    };
    prompts.set(lookup, entry);
  }
  if (!entry.aliases.includes(alias)) entry.aliases.push(alias);
  if (!entry.kinds.includes(kind)) entry.kinds.push(kind);
}
for (const entry of sourceManifest.entries) {
  if (entry.kind === 'songReference') continue; // Music stays music, not spoken titles.
  add(entry.sourceText, entry.locale.split('-')[0], entry.audioId, entry.kind);
}
for (const group of content.groups) {
  for (const topic of group.topics) for (const lesson of topic.lessons) {
    add(lesson.intro, 'vi', `${lesson.code}_INTRO`, 'lessonIntro');
    add(lesson.outro, 'vi', `${lesson.code}_OUTRO`, 'lessonOutro');
    for (const question of lesson.challengeBank ?? []) {
      // The live catalog can contain reviewed additions absent from the older
      // v4 source manifest; inventory the actual runtime prompts as well.
      add(question.prompt, 'vi', question.id, 'challengePrompt');
      add(question.correctAnswer, 'en', `${question.id}_ANSWER_EN`, 'challengeAnswer');
      add(question.correctVietnamese, 'vi', `${question.id}_ANSWER_VI`, 'challengeAnswer');
    }
    if (lesson.rolePlay) {
      add(lesson.rolePlay.scenarioVi, 'vi', `${lesson.code}_SCENARIO`, 'rolePlayScenario');
      add(lesson.rolePlay.openingHint, 'vi', `${lesson.code}_HINT`, 'rolePlayHint');
      for (const [index, turn] of lesson.rolePlay.turns.entries()) {
        add(turn.english, 'en', `${lesson.code}_TURN_${index}_EN`, 'rolePlay');
        add(turn.vietnamese, 'vi', `${lesson.code}_TURN_${index}_VI`, 'rolePlay');
      }
    }
  }
  for (const level of group.levels ?? []) for (const question of level.missionBank ?? []) {
    add(question.prompt, 'vi', question.id, 'missionPrompt');
    add(question.correctAnswer, 'en', `${question.id}_ANSWER_EN`, 'missionAnswer');
    add(question.correctVietnamese, 'vi', `${question.id}_ANSWER_VI`, 'missionAnswer');
  }
}
// Existing concrete system variants are useful for the dynamic lesson names /
// numbers present in this finite curriculum. Never narrate template syntax.
const systemIds = new Set(sourceManifest.entries.filter(e => e.kind === 'systemPrompt').map(e => e.audioId));
for (const path of packManifests.filter(p => /01_A_CAU_HE_THONG/.test(p))) {
  const pack = JSON.parse(readFileSync(path, 'utf8'));
  for (const item of pack.assets ?? []) if (systemIds.has(item.cue_id)) {
    add(item.text, 'vi', item.id, 'concreteSystemVariant');
  }
}
function assembled(text, alias, parts) {
  add(text, 'vi', alias, 'runtimeLessonPrompt');
  const entry = prompts.get(key(text, 'vi'));
  if (entry && !entry.importSource && !entry.reusableAssistantId) {
    entry.assemblySegments = parts.map(part => ({...part,
      ...(available.has(key(part.text, part.language)) ? {importSource:available.get(key(part.text, part.language))} : {}),
    }));
  }
}
const vi = text => ({text,language:'vi'});
const en = text => ({text,language:'en'});
add('Mình tiếp tục câu thử thách nhé.', 'vi', 'RUNTIME_CHALLENGE_RESUME', 'runtimeLessonPrompt');
for (const group of content.groups) {
  for (const topic of group.topics) for (const lesson of topic.lessons) {
    const lead = lesson.number === 1 ? 'Bài đầu tiên là' : 'Bài này là';
    const lessonLead = `${lead} ${lesson.titleEn}.`;
    // Match the runtime string including the topic lead when it is supplied.
    for (const includeTopic of lesson.number === 1 ? [false,true] : [false]) {
      const topicLead = includeTopic ? `Chủ đề ${topic.number}.` : '';
      const parts = [...(includeTopic ? [vi(topicLead)] : []), vi(lead), en(`${lesson.titleEn}.`),
        vi(lesson.entry?.text ?? ''), vi('Bắt đầu nhé.')].filter(p=>p.text);
      assembled(`${topicLead} ${lessonLead} ${lesson.entry?.text ?? ''} Bắt đầu nhé.`.replace(/\s+/g,' ').trim(),
        `${lesson.code}_RUNTIME_INTRO_${includeTopic}`, parts);
    }
    for (const action of ['tiếp','lại']) {
      assembled(`Mình học ${action} bài ${lesson.titleEn} nhé.`,`${lesson.code}_RUNTIME_${action==='tiếp'?'RESUME':'RELEARN'}`,
        [vi(`Mình học ${action} bài`),en(lesson.titleEn),vi('nhé.')]);
    }
    if (lesson.songTitle) {
      for (const [prefix,suffix,tag] of [
        ['Mình nghe lại bài hát','nhé.','RESUME'],['Bây giờ cùng nghe','nhé.','START'],
        ['Tiếp theo là một câu thử thách. Xong rồi mình nghe bài hát','nhé.','PREALERT'],
      ]) assembled(`${prefix} ${lesson.songTitle} ${suffix}`,`${lesson.code}_SONG_${tag}`,[vi(prefix),en(lesson.songTitle),vi(suffix)]);
    }
    for (let stars=1; stars<=lesson.sentences.length; stars++) {
      const suffix = group.startAge<=10 ? ' Mình cùng thử nhé!' : '';
      add(`Bài này bạn còn ${stars} Ngôi sao chưa chinh phục.${suffix}`,'vi',`REMAINING_STARS_${stars}_${group.startAge<=10}`,'runtimeLessonPrompt');
    }
    add(`Bạn đã hoàn thành Bài ${lesson.number} rồi!`,'vi',`COMPLETE_LESSON_${lesson.number}`,'runtimeLessonPrompt');
    add(`Bạn cần học xong Bài ${lesson.number} trước nhé.`,'vi',`LOCKED_LESSON_${lesson.number}`,'runtimeLessonPrompt');
    const next=topic.lessons.find(l=>l.number===lesson.number+1);
    if (next) add(`Bạn muốn học Bài ${next.number} hay học lại Bài ${lesson.number}?`,'vi',`CHOICE_LESSON_${lesson.number}_${next.number}`,'runtimeLessonPrompt');
  }
  for (const topic of group.topics) {
    add(`Bạn đã hoàn thành Chủ đề ${topic.number} rồi!`,'vi',`COMPLETE_TOPIC_${topic.number}`,'runtimeLessonPrompt');
    add(`Bạn muốn chọn Chủ đề khác hay học lại Chủ đề ${topic.number}?`,'vi',`CHOICE_TOPIC_${topic.number}`,'runtimeLessonPrompt');
  }
  for (const level of group.levels ?? []) {
    const question=`Có ${level.topicNumbers.length} Chủ đề. Bạn muốn học Chủ đề số mấy?`;
    assembled(`Bắt đầu Level ${level.number}. ${question}`,`LEVEL_${level.number}_TOPIC_SELECTION`,[vi(`Bắt đầu Level ${level.number}.`),vi(question)]);
    add(`Bạn đã hoàn thành Level ${level.number} rồi!`,'vi',`COMPLETE_LEVEL_${level.number}`,'runtimeLessonPrompt');
    add(`Bạn muốn bắt đầu Level ${level.number} hay dừng lại?`,'vi',`CHOICE_LEVEL_${level.number}`,'runtimeLessonPrompt');
    add(`Level này có ${level.topicNumbers.length} Chủ đề. Bạn chọn lại nhé.`,'vi',`INVALID_TOPIC_COUNT_${level.topicNumbers.length}`,'runtimeLessonPrompt');
  }
}
const manifest = { schemaVersion: 1, enabled: true, provider: 'elevenlabs', modelId: 'eleven_v3',
  profiles: assistant.profiles, prompts: [...prompts.values()], templates,
  retainedSongs: sourceManifest.entries.filter(e => e.kind === 'songReference') };
const missing = manifest.prompts.filter(p => !p.reusableAssistantId && !p.importSource && !p.enabled);
for (const prompt of missing) {
  // The only uncovered bilingual challenge form in the current corpus.
  // English answer options must use the English voice, not Vietnamese TTS.
  const options = prompt.text.match(/^(.+) hay (.+)\?$/u);
  if (prompt.kinds.includes('challengePrompt') && options &&
      !/[À-ỹĐđ]/u.test(options[1] + options[2])) {
    prompt.synthesisSegments = [
      { text: options[1], language: 'en' }, { text: 'hay', language: 'vi' },
      { text: `${options[2]}?`, language: 'en' },
    ];
  }
}
const summary = { uniqueAudio: prompts.size, reusesAssistant: manifest.prompts.filter(p=>p.reusableAssistantId).length,
  importsFromExistingV3: manifest.prompts.filter(p=>p.importSource).length,
  // Existing output still requires receipt/checksum verification by the builder.
  existingOutputs: manifest.prompts.filter(p=>existsSync(resolve(root,p.asset))).length,
  needsGeneration: missing.filter(p=>!existsSync(resolve(root,p.asset))).length,
  generationCharacters: missing.filter(p=>!existsSync(resolve(root,p.asset))).reduce((s,p)=>s+[...p.text].length,0),
  retainedSongs: manifest.retainedSongs.length, templateDefinitions: templates.length,
  missing: missing.filter(p=>!existsSync(resolve(root,p.asset))).map(p=>({id:p.id,language:p.voiceLanguage,text:p.text,kinds:p.kinds})) };
if (process.argv.includes('--write')) writeFileSync(target, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(JSON.stringify(summary, null, 2));
