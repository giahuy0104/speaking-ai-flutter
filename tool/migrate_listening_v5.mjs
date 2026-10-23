import fs from 'node:fs';

const catalogPath = new URL('../assets/data/listening_lessons.json', import.meta.url);
const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const allowedFormats = new Set(['VI_TO_EN', 'CONTEXT', 'UNDERSTANDING']);

const additions = new Map(
  [
    ['C35-L1-T01-B01-Q09', 'C35-L1-T01-B01-T05', 'Quả trứng: Egg hay Fish?', 'Egg.', 'Fish.', 'VI_TO_EN'],
    ['C35-L1-T01-B02-Q09', 'C35-L1-T01-B02-T05', 'Cái mũi: Nose hay Orange?', 'Nose.', 'Orange.', 'VI_TO_EN'],
    ['C35-L1-T02-B01-Q09', 'C35-L1-T02-B01-T03', 'Ba: Three hay Four?', 'Three.', 'Four.', 'VI_TO_EN'],
    ['C35-L1-T02-B01-Q10', 'C35-L1-T02-B01-T08', 'Tám: Eight hay Seven?', 'Eight.', 'Seven.', 'VI_TO_EN'],
    ['C35-L1-T02-B01-Q11', 'C35-L1-T02-B01-T09', 'Chín: Nine hay Ten?', 'Nine.', 'Ten.', 'VI_TO_EN'],
    ['C35-L1-T02-B01-Q12', 'C35-L1-T02-B01-T10', 'Mười: Ten hay Nine?', 'Ten.', 'Nine.', 'VI_TO_EN'],
    ['C35-L1-T03-B02-Q09', 'C35-L1-T03-B02-T03', "Nó màu vàng: It's yellow hay It's green?", "It's yellow.", "It's green.", 'VI_TO_EN'],
    ['C67-L1-T01-B01-Q09', 'C67-L1-T01-B01-T05', 'Con voi: Elephant hay Flower?', 'Elephant.', 'Flower.', 'VI_TO_EN'],
    ['C67-L1-T01-B02-Q09', 'C67-L1-T01-B02-T05', 'Quyển vở: Notebook hay Pencil?', 'Notebook.', 'Pencil.', 'VI_TO_EN'],
    ['C67-L1-T02-B01-Q09', 'C67-L1-T02-B01-T03', 'Ba: Three hay Four?', 'Three.', 'Four.', 'VI_TO_EN'],
    ['C67-L1-T02-B01-Q10', 'C67-L1-T02-B01-T08', 'Tám: Eight hay Seven?', 'Eight.', 'Seven.', 'VI_TO_EN'],
    ['C67-L1-T02-B01-Q11', 'C67-L1-T02-B01-T09', 'Chín: Nine hay Ten?', 'Nine.', 'Ten.', 'VI_TO_EN'],
    ['C67-L1-T02-B01-Q12', 'C67-L1-T02-B01-T10', 'Mười: Ten hay Nine?', 'Ten.', 'Nine.', 'VI_TO_EN'],
    ['C67-L1-T02-B02-Q09', 'C67-L1-T02-B02-T03', 'Mười ba: Thirteen hay Fourteen?', 'Thirteen.', 'Fourteen.', 'VI_TO_EN'],
    ['C67-L1-T02-B02-Q10', 'C67-L1-T02-B02-T08', 'Mười tám: Eighteen hay Seventeen?', 'Eighteen.', 'Seventeen.', 'VI_TO_EN'],
    ['C67-L1-T02-B02-Q11', 'C67-L1-T02-B02-T09', 'Mười chín: Nineteen hay Twenty?', 'Nineteen.', 'Twenty.', 'VI_TO_EN'],
    ['C67-L1-T02-B02-Q12', 'C67-L1-T02-B02-T10', 'Hai mươi: Twenty hay Nineteen?', 'Twenty.', 'Nineteen.', 'VI_TO_EN'],
    ['C1315-L1-T01-B02-Q09', 'C1315-L1-T01-B02-T03', 'Bạn muốn nói mình thư giãn vào buổi tối. I relax in the evening hay I read at night?', 'I relax in the evening.', 'I read at night.', 'CONTEXT'],
    ['C1315-L2-T05-B01-Q09', 'C1315-L2-T05-B01-T04', "Bạn không thể tập trung. I can't focus hay I need a break?", "I can't focus.", 'I need a break.', 'CONTEXT'],
    ['C1315-L3-T10-B01-Q09', 'C1315-L3-T10-B01-T03', 'Bạn muốn tham gia câu lạc bộ. I want to join a club hay I want to learn coding?', 'I want to join a club.', 'I want to learn coding.', 'CONTEXT'],
  ].map(([id, targetId, prompt, correctAnswer, wrongAnswer, format]) => [
    targetId,
    { id, format, prompt, choices: [correctAnswer, wrongAnswer], correctAnswer, targetId },
  ]),
);

function formatPriority(startAge, format) {
  const order = startAge <= 5
    ? ['VI_TO_EN', 'UNDERSTANDING', 'CONTEXT']
    : startAge <= 7
      ? ['VI_TO_EN', 'CONTEXT', 'UNDERSTANDING']
      : ['CONTEXT', 'UNDERSTANDING', 'VI_TO_EN'];
  return order.indexOf(format);
}

let coreCount = 0;
let challengeCount = 0;
let addedCount = 0;
let authoredAdditionCount = 0;

for (const group of catalog.groups ?? []) {
  for (const level of group.levels ?? []) delete level.missionBank;
  for (const topic of group.topics ?? []) {
    for (const lesson of topic.lessons ?? []) {
      delete lesson.rolePlay;
      const existing = new Map();
      for (const challenge of lesson.challengeBank ?? []) {
        if (!allowedFormats.has(challenge.format)) continue;
        const list = existing.get(challenge.targetId) ?? [];
        list.push(challenge);
        existing.set(challenge.targetId, list);
      }

      lesson.challengeBank = (lesson.sentences ?? []).map((sentence) => {
        coreCount += 1;
        const candidates = existing.get(sentence.id) ?? [];
        candidates.sort((left, right) => {
          const rank = formatPriority(group.startAge, left.format) -
            formatPriority(group.startAge, right.format);
          return rank || left.id.localeCompare(right.id);
        });
        let selected = candidates[0];
        if (!selected) {
          selected = additions.get(sentence.id);
          if (!selected) throw new Error(`Missing Challenge for ${sentence.id}`);
          selected = {
            ...selected,
            correctVietnamese: sentence.vietnamese ?? '',
          };
          addedCount += 1;
        }
        if (additions.get(sentence.id)?.id === selected.id) {
          authoredAdditionCount += 1;
        }
        if (selected.targetId === 'C1112-L2-T04-B01-T03' &&
            sentence.english.trim() !== 'Taxi.') {
          throw new Error('Taxi TARGET_REF does not match the authored Core');
        }
        challengeCount += 1;
        return selected;
      });
    }
  }
}

if (coreCount !== 601 ||
    challengeCount !== coreCount ||
    authoredAdditionCount !== 20) {
  throw new Error(JSON.stringify({
    coreCount,
    challengeCount,
    addedCount,
    authoredAdditionCount,
  }));
}

fs.writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(JSON.stringify({
  coreCount,
  challengeCount,
  addedCount,
  authoredAdditionCount,
}));
