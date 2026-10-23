import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_topic_patch_migration.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ListeningTopicPatchMigration patch;
  late ListeningContentCatalog catalog;
  setUpAll(() async {
    patch = ListeningTopicPatchMigration.fromJson(
      jsonDecode(
            await File(ListeningTopicPatchMigration.assetPath).readAsString(),
          )
          as Map<String, dynamic>,
    );
    catalog = ListeningContentCatalog.fromJson(
      jsonDecode(
            await File('assets/data/listening_lessons.json').readAsString(),
          )
          as Map<String, Object?>,
    );
  });

  test('manifest maps moved stable targets, not reused lesson positions', () {
    final fish = patch.destinationForTarget('C35-L1-T01-B01-T06')!;
    expect(fish.lessonId, 'c35-l1-t01-b02');
    expect(fish.sentenceIndex, 0);
    final lion = patch.destinationForIndex('c35-l1-t01-b02', 2)!;
    expect(lion.lessonId, 'c67-l1-t01-b01');
    expect(lion.sentenceIndex, 1);
    expect(patch.isDeprecatedTarget('C67-L1-T01-B01-T01'), isTrue);
    expect(patch.destinationForTarget('C67-L1-T02-B01-T01'), isNull);
    expect(patch.isAffectedLessonCode('C35-L1-T02-B03'), isTrue);
  });

  test('moves Count With Me whole state without overwriting Six to Ten', () {
    const source = 'c35-l1-t02-b02';
    const destination = 'c35-l1-t02-b03';
    const target = 'C35-L1-T02-B02-T03';
    final original = <String, int>{
      'c35-l1-t02-b01': 8,
      'c35-l1-t02-b01::current-sentence': 7,
      source: 5,
      '$source::current-sentence': 4,
      '$source::core-started': 1,
      '$source::resume-stage': ListeningResumeStage.song.index,
      '$source::challenge-processed-v5': 1,
      '$source::challenge-rotation-mask-v5': 4,
      '$source::earned-star::core:$target': 1,
      '$source::pending-choice-stage-v5': 1,
      '$source::unknown-future-field': 19,
    };
    final migrated = patch.migrateProgress(original);
    expect(migrated[destination], 5);
    for (final entry in original.entries.where(
      (entry) => entry.key.startsWith('$source::'),
    )) {
      expect(
        migrated['$destination${entry.key.substring(source.length)}'],
        entry.value,
      );
    }
    expect(migrated[source], 3);
    expect(migrated['$source::current-sentence'], 2);
    expect(migrated['$source::pending-choice-stage-v5'], isNull);
    expect(migrated['$source::unknown-future-field'], isNull);
    expect(migrated['${ListeningTopicPatchMigration.archivePrefix}$source'], 5);
    expect(patch.migrateProgress(migrated), migrated);
  });

  test(
    'moves positional Core result, retry and stars with stable identity',
    () {
      const source = 'c35-l1-t01-b01';
      const destination = 'c35-l1-t01-b02';
      const target = 'C35-L1-T01-B01-T07';
      final original = <String, int>{
        source: 7,
        '$source::current-sentence': 6,
        '$source::core-started': 1,
        '$source::session-result-v5::5': ListeningSessionResult.achieved.index,
        '$source::session-result-v5::6':
            ListeningSessionResult.skippedPending.index,
        '$source::skipped-sentence::6': 1,
        '$source::needs-practice::6': 1,
        '$source::earned-star::core:$target': 1,
      };
      final migrated = patch.migrateProgress(original);
      expect(migrated[source], 5);
      expect(migrated[destination], 2);
      expect(migrated['$destination::current-sentence'], 1);
      expect(migrated['$destination::session-result-v5::0'], 1);
      expect(migrated['$destination::session-result-v5::1'], 3);
      expect(migrated['$destination::skipped-sentence::1'], 1);
      expect(migrated['$destination::needs-practice::1'], 1);
      expect(migrated['$destination::earned-star::core:$target'], 1);
      expect(migrated['$source::earned-star::core:$target'], isNull);
      expect(
        migrated[ListeningTopicPatchMigration.unlockKeyForLesson(destination)],
        1,
      );
      expect(migrated['$source::lesson-completed-v5'], isNull);
    },
  );

  test('retired old 6-7 progress cannot complete new Kite or Eleven', () {
    const alphabet = 'c67-l1-t01-b01';
    const numbers = 'c67-l1-t02-b01';
    const star = '::earned-star::core:C67-L1-T01-B01-T01';
    final original = <String, int>{
      alphabet: 9,
      '$alphabet::lesson-completed-v5': 1,
      '$alphabet::resume-stage': 5,
      '$alphabet$star': 1,
      numbers: 10,
      '$numbers::lesson-completed-v5': 1,
    };
    final migrated = patch.migrateProgress(original);
    expect(migrated[alphabet], isNull);
    expect(migrated[numbers], isNull);
    expect(migrated['$alphabet::lesson-completed-v5'], isNull);
    expect(migrated['$alphabet$star'], isNull);
    expect(
      migrated['${ListeningTopicPatchMigration.archivedLessonId(alphabet)}$star'],
      1,
    );
    expect(
      migrated[ListeningTopicPatchMigration.unlockKeyForLesson(
        'c67-l1-t01-b02',
      )],
      1,
    );
  });

  test(
    'changed challenge rotation resets without crediting an unrelated question',
    () {
      const source = 'c35-l1-t01-b01';
      const destination = 'c35-l1-t01-b02';
      final oldBank = patch.oldLessons[source]!.challengeBank;
      final fishIndex = oldBank.indexWhere(
        (question) => question.targetId == 'C35-L1-T01-B01-T06',
      );
      final migrated = patch.migrateProgress({
        source: 9,
        '$source::challenge-rotation-mask-v5': 1 << fishIndex,
        '$source::current-challenge-index-v5': fishIndex,
        '$source::challenge-processed-v5': 1,
      });
      expect(migrated['$destination::challenge-rotation-mask-v5'], isNull);
      expect(migrated['$destination::current-challenge-index-v5'], isNull);
      // J was not processed, so completing A-I cannot complete F-J.
      expect(migrated['$destination::lesson-completed-v5'], isNull);
      expect(migrated['$source::challenge-processed-v5'], isNull);
    },
  );

  test(
    'complete matching Core and historical Challenge transfer completion',
    () {
      const source = 'c35-l1-t02-b01';
      final original = <String, int>{
        source: 10,
        '$source::challenge-rotation-mask-v5': 1,
        '$source::lesson-completed-v5': 1,
      };
      final migrated = patch.migrateProgress(original);
      expect(migrated['$source::lesson-completed-v5'], 1);
      expect(migrated['c35-l1-t02-b02'], 5);
      expect(migrated['c35-l1-t02-b02::lesson-completed-v5'], isNull);
      expect(migrated['c35-l1-t02-b02::resume-stage'], 1);
    },
  );

  test('Numbers in Life and unrelated keys remain exactly unchanged', () {
    final original = <String, int>{
      'c67-l1-t02-b03': 2,
      'c67-l1-t02-b03::current-sentence': 1,
      'c67-l1-t02-b03::session-result-v5::1': 1,
      'c810-l1-t01-b01': 4,
      'c810-l1-t01-b01::current-sentence': 3,
      'c1112-l3-t09-b03::earned-star::core:x': 1,
      'C35-L1::level-mission-passed': 1,
      '3-5::topic-selection-level': 2,
      '__listening-learning-guide-opened-v2': 1,
    };
    final migrated = patch.migrateProgress(original, catalog: catalog);
    for (final entry in original.entries) {
      expect(migrated[entry.key], entry.value, reason: entry.key);
    }
  });

  test('previous level access retained without fake new lesson completion', () {
    final original = <String, int>{};
    final group = catalog.groups.firstWhere((group) => group.startAge == 6);
    final level = group.levels.first;
    for (final topic in group.topics.where(
      (topic) => level.topicNumbers.contains(topic.number),
    )) {
      final old = patch.oldLessons.values.where(
        (lesson) => lesson.startAge == 6 && lesson.topicNumber == topic.number,
      );
      if (old.isNotEmpty) {
        for (final lesson in old) {
          original[lesson.id] = lesson.targetIds.length;
          original['${lesson.id}::lesson-completed-v5'] = 1;
        }
      } else {
        for (final lesson in topic.lessons) {
          original[lesson.id] = lesson.sentences.length;
          original['${lesson.id}::lesson-completed-v5'] = 1;
        }
      }
    }
    final migrated = patch.migrateProgress(original, catalog: catalog);
    expect(migrated[ListeningTopicPatchMigration.unlockKeyForGroup(6, 7)], 2);
    expect(migrated['c67-l1-t01-b01::lesson-completed-v5'], isNull);
    original.remove('c67-l1-t01-b03::lesson-completed-v5');
    final partial = patch.migrateProgress(original, catalog: catalog);
    expect(
      partial[ListeningTopicPatchMigration.unlockKeyForGroup(6, 7)],
      isNull,
    );
  });

  test('existing later-level activity preserves its access floor', () {
    final group = catalog.groups.firstWhere((group) => group.startAge == 3);
    final level = group.levels.last;
    final topic = group.topics.firstWhere(
      (topic) => level.topicNumbers.contains(topic.number),
    );
    final original = <String, int>{
      '${topic.lessons.first.id}::core-started': 1,
    };
    final migrated = patch.migrateProgress(original, catalog: catalog);
    expect(
      migrated[ListeningTopicPatchMigration.unlockKeyForGroup(3, 5)],
      level.number,
    );
  });

  test(
    'cursor-only legacy state retains the mapped sentence without start flag',
    () {
      final migrated = patch.migrateProgress({
        'c35-l1-t01-b01::current-sentence': 7,
      });
      expect(migrated['c35-l1-t01-b02::current-sentence'], 2);
      expect(migrated['c35-l1-t01-b02'], 0);
      expect(migrated['c35-l1-t01-b02::core-started'], 1);
      expect(
        migrated['c35-l1-t01-b02${ListeningTopicPatchMigration.retainedRunSuffix}'],
        1,
      );
    },
  );

  test(
    'normal Next keeps a migrated run once, then retains old reset behavior',
    () async {
      final store = await _legacyStore({
        'c35-l1-t01-b01': 7,
        'c35-l1-t01-b01::current-sentence': 6,
        'c35-l1-t01-b01::session-result-v5::6': 1,
      });
      const lesson = 'c35-l1-t01-b02';
      await store.prepareNextLessonRun(lesson);
      expect(await store.readCurrentSentence(lesson), 1);
      expect(
        await store.readSessionResult(lesson, 1),
        ListeningSessionResult.achieved,
      );
      expect(await store.readRetainedProcessedSentences(lesson), {0});
      await store.prepareNextLessonRun(lesson);
      expect(await store.readCurrentSentence(lesson), 0);
      expect(await store.readSessionResults(lesson), isEmpty);
      expect(await store.readRetainedProcessedSentences(lesson), isEmpty);
    },
  );

  test('explicit Relearn resets a retained run on its first entry', () async {
    final store = await _legacyStore({
      'c35-l1-t01-b01': 7,
      'c35-l1-t01-b01::current-sentence': 6,
      'c35-l1-t01-b01::session-result-v5::6': 1,
    });
    const lesson = 'c35-l1-t01-b02';
    await store.prepareNextLessonRun(lesson, relearn: true);
    expect(await store.readCurrentSentence(lesson), 0);
    expect(await store.readSessionResults(lesson), isEmpty);
    expect(await store.readRetainedProcessedSentences(lesson), isEmpty);
    await store.saveCurrentSentence(lesson, 3);
    await store.prepareNextLessonRun(lesson);
    expect(await store.readCurrentSentence(lesson), 0);
  });

  test(
    'processed legacy Core across a new gap is retained without fake outcome',
    () async {
      // J was processed in old B2; F-I were not processed in old B1.
      final store = await _legacyStore({'c35-l1-t01-b02': 1});
      const lesson = 'c35-l1-t01-b02';
      await store.prepareNextLessonRun(lesson);
      expect(await store.readLesson(lesson), 0);
      expect(await store.readRetainedProcessedSentences(lesson), {4});
      expect(await store.readSessionResults(lesson), isEmpty);
      expect(await store.readEarnedStars(lesson), isEmpty);
      expect(await store.hasCompletedV4LessonActivity(lesson), isFalse);
      expect(
        (await store.readAll()).keys.any(
          (key) => key.contains('processed-core'),
        ),
        isFalse,
      );
      await store.saveSessionResult(lesson, 4, ListeningSessionResult.achieved);
      expect(await store.readRetainedProcessedSentences(lesson), isEmpty);
      expect(
        await store.readSessionResult(lesson, 4),
        ListeningSessionResult.achieved,
      );
    },
  );

  test(
    'topic and level Relearn discard retained run flags and Core evidence',
    () async {
      for (final wholeLevel in [false, true]) {
        final store = await _legacyStore({'c35-l1-t01-b02': 1});
        const lesson = 'c35-l1-t01-b02';
        expect(await store.readRetainedProcessedSentences(lesson), {4});
        if (wholeLevel) {
          await store.resetLevelForRelearn(
            levelId: 'C35-L1',
            lessonIds: [lesson],
          );
        } else {
          await store.resetLessonsForRelearn([lesson]);
        }
        expect(await store.readRetainedProcessedSentences(lesson), isEmpty);
        await store.saveCurrentSentence(lesson, 3);
        await store.prepareNextLessonRun(lesson);
        expect(await store.readCurrentSentence(lesson), 0);
      }
    },
  );

  test(
    'store auto-migrates once, archives original cursor, counts stars once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'topic-patch-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/progress.json');
      const movedSource = 'c35-l1-t02-b02';
      const retiredSource = 'c67-l1-t01-b01';
      final original = <String, int>{
        movedSource: 3,
        '$movedSource::current-sentence': 2,
        '$movedSource::core-started': 1,
        '$movedSource::earned-star::core:C35-L1-T02-B02-T01': 1,
        '$retiredSource::earned-star::core:C67-L1-T01-B01-T01': 1,
      };
      await file.writeAsString(jsonEncode(original));
      final store = ListeningProgressStore(progressFilePath: file.path);
      final reads = await Future.wait([store.readAll(), store.readAll()]);
      expect(reads.first, reads.last);
      expect(reads.first['c35-l1-t02-b03'], 3);
      expect(
        reads.first.keys.any((key) => key.startsWith('__topic-patch-v41')),
        isFalse,
      );
      expect(await store.readTotalEarnedStars(), 2);
      expect(await store.readBeforeTopicPatch(), original);
      expect(await store.readStartedLessonCores(), {'c35-l1-t02-b03'});
      final encoded = await file.readAsString();
      await store.readAll();
      expect(await file.readAsString(), encoded);
      await store.saveCurrentSentence('c35-l1-t02-b03', 1);
      expect(await store.readCurrentSentence('c35-l1-t02-b03'), 1);
      expect(await store.readBeforeTopicPatch(), original);
    },
  );
}

Future<ListeningProgressStore> _legacyStore(Map<String, int> original) async {
  final directory = await Directory.systemTemp.createTemp('topic-patch-run-');
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/progress.json');
  await file.writeAsString(jsonEncode(original));
  return ListeningProgressStore(progressFilePath: file.path);
}
