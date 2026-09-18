// Narrow, repeatable application of the approved four-topic Alphabet/Numbers
// patch. Run after the older curriculum generators, never in their place.
// This script generates metadata only: it does not generate/upload/delete audio.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = new URL('../', import.meta.url);
const read = (path) => JSON.parse(fs.readFileSync(new URL(path, root), 'utf8'));
const save = (path, value) => fs.writeFileSync(new URL(path, root), `${JSON.stringify(value, null, 2)}\n`);
const clone = (value) => structuredClone(value);
const digest = (value) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const catalogPath = 'assets/data/listening_lessons.json';
const patchPath = 'assets/data/listening_topic_patch_v42.json';
const selected = new Set(['c35-l1-t01', 'c35-l1-t02', 'c67-l1-t01', 'c67-l1-t02']);
const catalog = read(catalogPath);
assert.ok(['4.1', '4.2'].includes(catalog.contentVersion), 'Unexpected source content version');
const priorPatch = fs.existsSync(new URL(patchPath, root)) ? read(patchPath) : null;
assert.ok(catalog.contentVersion !== '4.2' || priorPatch, 'Missing immutable migration source snapshot');
const oldTopics = priorPatch?.oldTopics ?? catalog.groups.flatMap((group) => group.topics
  .filter((topic) => selected.has(topic.id))
  .map((topic) => ({ startAge: group.startAge, endAge: group.endAge, topic: clone(topic) })));
assert.equal(oldTopics.length, 4);
const oldLessons = new Map(oldTopics.flatMap(({ topic }) => topic.lessons.map((lesson) => [lesson.code, lesson])));
const oldTargets = new Map(oldTopics.flatMap((group) => group.topic.lessons.flatMap((lesson) => lesson.sentences
  .map((target, sentenceIndex) => [target.id, {
    lessonId: lesson.id, lessonCode: lesson.code, startAge: group.startAge, endAge: group.endAge,
    topicNumber: group.topic.number, lessonNumber: lesson.number, sentenceIndex, targetId: target.id,
  }]))));
const untouchedTopics = catalog.groups.flatMap((group) => group.topics.filter((topic) => !selected.has(topic.id)));
const untouchedHashes = Object.fromEntries(untouchedTopics.map((topic) => [topic.id, digest(topic)]));
if (priorPatch) assert.deepEqual(untouchedHashes, priorPatch.unchangedTopicSha256, 'Unrelated curriculum changed; review source before reapplying');

const part = (code, first, last) => {
  const lesson = oldLessons.get(code);
  assert.ok(lesson, `Unknown source ${code}`);
  return lesson.sentences.slice(first - 1, last).map((sentence) => ({ sentence, lesson }));
};
const alpha = 'Mình cùng học các chữ cái và từ quen thuộc nhé.';
const abc = 'Mình cùng học chữ cái qua những từ quen thuộc nhé.';
const count = 'Mình cùng học cách đếm số nhé.';
const numbers = 'Mình cùng học các số trong đời sống nhé.';
const definitions = [
  ['c35-l1-t01', [
    ['C35-L1-T01-B01', 'A to E Letters', 'Các chữ cái từ A đến E', alpha, part('C35-L1-T01-B01', 1, 5)],
    ['C35-L1-T01-B02', 'F to J Letters', 'Các chữ cái từ F đến J', alpha, [...part('C35-L1-T01-B01', 6, 9), ...part('C35-L1-T01-B02', 1, 1)]],
  ]],
  ['c35-l1-t02', [
    ['C35-L1-T02-B01', 'One to Five', 'Số từ một đến năm', count, part('C35-L1-T02-B01', 1, 5)],
    ['C35-L1-T02-B02', 'Six to Ten', 'Số từ sáu đến mười', count, part('C35-L1-T02-B01', 6, 10)],
    ['C35-L1-T02-B03', 'Count With Me', 'Cùng mình đếm số', null, part('C35-L1-T02-B02', 1, 5)],
  ]],
  ['c67-l1-t01', [
    ['C67-L1-T01-B01', 'K to O Letters', 'Các chữ cái từ K đến O', abc, part('C35-L1-T01-B02', 2, 6)],
    ['C67-L1-T01-B02', 'P to T Letters', 'Các chữ cái từ P đến T', abc, [...part('C35-L1-T01-B02', 7, 9), ...part('C35-L1-T01-B03', 1, 2)]],
    ['C67-L1-T01-B03', 'U to Z Letters', 'Các chữ cái từ U đến Z', abc, part('C35-L1-T01-B03', 3, 8)],
  ]],
  ['c67-l1-t02', [
    ['C67-L1-T02-B01', 'Numbers 11-15', 'Số từ 11 đến 15', numbers, part('C67-L1-T02-B02', 1, 5)],
    ['C67-L1-T02-B02', 'Numbers 16-20', 'Số từ 16 đến 20', numbers, part('C67-L1-T02-B02', 6, 10)],
    ['C67-L1-T02-B03', 'Numbers in Life', 'Những con số quanh mình', null, part('C67-L1-T02-B03', 1, 5)],
  ]],
];

const newTopics = definitions.map(([topicId, lessons]) => {
  const source = oldTopics.find((group) => group.topic.id === topicId);
  const topic = clone(source.topic);
  topic.lessons = lessons.map(([code, titleEn, titleVi, objective, parts], index) => {
    const base = parts[0].lesson;
    const lesson = clone(base);
    lesson.id = code.toLowerCase();
    lesson.code = code;
    lesson.number = index + 1;
    lesson.titleEn = titleEn;
    lesson.titleVi = titleVi;
    lesson.sentences = parts.map(({ sentence }, i) => ({ ...clone(sentence), number: i + 1 }));
    lesson.challengeBank = parts.map(({ lesson: owner, sentence }) => {
      const matches = owner.challengeBank.filter((question) => question.targetId === sentence.id);
      assert.equal(matches.length, 1, `Exactly one approved challenge for ${sentence.id}`);
      return clone(matches[0]);
    });
    if (objective !== null) {
      lesson.intro = objective;
      lesson.entry = { kind: 'microObjective', text: objective };
      // Only retain the isolated intro when its actual source text is unchanged.
      // Full-lesson/overview recordings cannot represent a new subset of targets.
      if (base.intro !== objective) lesson.introAudioUrl = [...oldLessons.values()]
        .find((candidate) => candidate.intro === objective && candidate.introAudioUrl)?.introAudioUrl ?? null;
      lesson.fullAudioId = null;
      lesson.fullAudioUrl = null;
      delete lesson.karaokeLines;
      delete lesson.dialogueTransitionAudioId;
      delete lesson.dialogueTransitionAudioUrl;
      delete lesson.rolePlay;
      delete lesson.songAudioId;
      delete lesson.songAudioUrl;
      lesson.songTitle = null;
    }
    return lesson;
  });
  return { startAge: source.startAge, endAge: source.endAge, topic };
});
const placements = newTopics.flatMap((group) => group.topic.lessons.flatMap((lesson) => lesson.sentences
  .map((target, sentenceIndex) => ({ source: clone(oldTargets.get(target.id)), destination: {
    lessonId: lesson.id, lessonCode: lesson.code, startAge: group.startAge, endAge: group.endAge,
    topicNumber: group.topic.number, lessonNumber: lesson.number, sentenceIndex, targetId: target.id,
  } }))));
const remaining = new Set(placements.map((entry) => entry.source.targetId));
const removedTargetIds = [...oldTargets.keys()].filter((id) => !remaining.has(id));
assert.equal(placements.length, 56);
assert.equal(removedTargetIds.length, 36);
for (const group of catalog.groups) group.topics = group.topics.map((topic) =>
  newTopics.find((replacement) => replacement.topic.id === topic.id)?.topic ?? topic);
assert.deepEqual(Object.fromEntries(catalog.groups.flatMap((group) => group.topics
  .filter((topic) => !selected.has(topic.id)).map((topic) => [topic.id, digest(topic)]))), untouchedHashes);
const allLessons = catalog.groups.flatMap((group) => group.topics.flatMap((topic) => topic.lessons));
const allTargets = allLessons.flatMap((lesson) => lesson.sentences);
assert.equal(allLessons.length, 109);
assert.equal(allTargets.length, 565);
assert.equal(new Set(allTargets.map((target) => target.id)).size, 565);
catalog.contentVersion = '4.2';
catalog.contentPatch = 'alphabet-numbers-v42';

const patch = {
  schemaVersion: 1, version: 42, patchId: 'alphabet-numbers-v42',
  fromContentVersion: '4.1', toContentVersion: '4.2',
  source: 'AIV0_HOMI_PATCH_Thay_doi_4_Topic_Alphabet_Numbers_gui_IT (1).docx',
  oldTopics, newTopics, placements, removedTargetIds,
  unchangedTopicSha256: untouchedHashes,
};

// Update only metadata owned by the four topics. Existing audio files, URLs,
// content-hash manifests, unrelated lessons and inactive recordings stay intact.
const belongsToPatch = (entry) => ['3-5', '6-7'].includes(entry.course)
  && [1, 2].includes(entry.topic ?? entry.topicNumber);
// Positions count only untouched entries and come from the approved 4.1
// exports. Keep them fixed across repeat runs so the unrelated rows never move
// to a different relative order just because the four topic sizes changed.
const exportInsertionOffsets = {
  audio: { '3-5:1': 16, '3-5:2': 29, '6-7:1': 331, '6-7:2': 331 },
  lexicon: { '3-5:1': 0, '3-5:2': 0, '6-7:1': 78, '6-7:2': 78 },
};
const mergeOwnedEntries = (kind, original, replacement) => {
  const untouched = original.filter((entry) => !belongsToPatch(entry)
    && !removedTargetIds.includes(entry.targetId));
  const hashKey = kind === 'audio' ? 'unchangedAudioEntriesSha256' : 'unchangedLexiconEntriesSha256';
  const expectedHash = priorPatch?.[hashKey];
  if (expectedHash) assert.equal(digest(untouched), expectedHash, `Unrelated ${kind} metadata changed`);
  patch[hashKey] = digest(untouched);
  const result = [];
  let cursor = 0;
  for (const [key, offset] of Object.entries(exportInsertionOffsets[kind])) {
    assert.ok(offset >= cursor && offset <= untouched.length);
    result.push(...untouched.slice(cursor, offset), ...replacement.filter((entry) =>
      `${entry.course}:${entry.topic ?? entry.topicNumber}` === key));
    cursor = offset;
  }
  result.push(...untouched.slice(cursor));
  return result;
};
const audioPath = 'assets/data/listening_audio_manifest_v4.json';
const audio = read(audioPath);
const originalAudio = new Map(audio.entries.map((entry) => [entry.audioId, entry]));
const replacementAudio = [];
for (const group of newTopics) for (const lesson of group.topic.lessons) {
  const scope = { course: `${group.startAge}-${group.endAge}`, level: 'L1', topic: group.topic.number, lessonCode: lesson.code };
  const append = (audioId, kind, locale, sourceText, extra = {}) => {
    const existing = originalAudio.get(audioId);
    const matching = existing?.sourceText === sourceText && existing?.locale === locale;
    replacementAudio.push({ ...(matching ? existing : {}), audioId, kind, locale, sourceText,
      qaStatus: matching ? existing.qaStatus : 'PENDING_TTS', ...extra, ...scope });
  };
  append(`${lesson.code}_ENTRY`, lesson.entry.kind, 'vi-VN', lesson.entry.text);
  for (const target of lesson.sentences) {
    append(target.englishAudioId, 'coreEnglish', 'en-US', target.english, { targetId: target.id });
    append(target.vietnameseAudioId, 'coreVietnamese', 'vi-VN', target.vietnamese, { targetId: target.id });
  }
  for (const challenge of lesson.challengeBank) append(`${challenge.id}_PROMPT`, 'challengePrompt', 'vi-VN',
    challenge.prompt, { questionId: challenge.id, targetId: challenge.targetId });
  if (lesson.songAudioId) append(lesson.songAudioId, 'songReference', 'en-US', lesson.songTitle,
    { sourceAudioUrl: lesson.songAudioUrl, qaStatus: 'READY_SOURCE_AUDIO' });
}
audio.entries = mergeOwnedEntries('audio', audio.entries, replacementAudio);
audio.contentVersion = '4.2';
audio.contentPatch = patch.patchId;
assert.equal(new Set(audio.entries.map((entry) => entry.audioId)).size, audio.entries.length);

const lexiconPath = 'assets/data/listening_ai_lexicon_v4.json';
const lexicon = read(lexiconPath);
const originalLexicon = new Map(lexicon.entries.map((entry) => [entry.id, entry]));
const replacementLexicon = newTopics.flatMap((group) => group.topic.lessons.flatMap((lesson) => lesson.sentences.map((target) => ({
  ...originalLexicon.get(target.id), id: target.id, kind: 'coreTarget', lessonCode: lesson.code,
  topicNumber: group.topic.number, course: `${group.startAge}-${group.endAge}`,
  english: target.english, vietnamese: target.vietnamese,
  acceptedVariants: target.recognitionVariants, requiresAllExpectedTokens: target.requiresAllExpectedTokens,
}))));
lexicon.entries = mergeOwnedEntries('lexicon', lexicon.entries, replacementLexicon);
const activeLexiconIds = new Set(lexicon.entries.map((entry) => entry.id));
lexicon.terms = lexicon.terms.map((entry) => ({ ...entry, entryIds: entry.entryIds.filter((id) => activeLexiconIds.has(id)) }))
  .filter((entry) => entry.entryIds.length > 0);
lexicon.contentVersion = '4.2';
lexicon.contentPatch = patch.patchId;

save(patchPath, patch);
save(catalogPath, catalog);
save(audioPath, audio);
save(lexiconPath, lexicon);
console.log(JSON.stringify({ patchPath: fileURLToPath(new URL(patchPath, root)), lessons: allLessons.length,
  targets: allTargets.length, unchangedTopics: untouchedTopics.length, migratedTargets: placements.length,
  removedTargets: removedTargetIds.length }, null, 2));
