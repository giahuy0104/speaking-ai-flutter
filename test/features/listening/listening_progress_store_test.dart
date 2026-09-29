import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ListeningProgressStore.debugForgetCachedFiles);
  tearDown(ListeningProgressStore.debugForgetCachedFiles);

  test('resume sentence can move backward without losing completion', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    await fixture.store.saveLesson('lesson-1', 10);
    await fixture.store.saveCurrentSentence('lesson-1', 4);

    expect(await fixture.store.readLesson('lesson-1'), 10);
    expect(await fixture.store.readCurrentSentence('lesson-1'), 4);
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 10});

    await fixture.store.saveCurrentSentence('lesson-1', 0);

    expect(await fixture.store.readCurrentSentence('lesson-1'), 0);
    expect(await fixture.store.readLesson('lesson-1'), 10);
  });

  test('legacy progress remains a valid resume position', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.file.writeAsString(jsonEncode(<String, int>{'legacy': 3}));

    expect(await fixture.store.readCurrentSentence('legacy'), 3);
  });

  test(
    'skipped sentences persist without leaking into lesson totals',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveLesson('lesson-1', 3);
      await fixture.store.saveSkippedSentence('lesson-1', 1);
      await fixture.store.saveSkippedSentence('lesson-1', 4);

      expect(await fixture.store.readSkippedSentences('lesson-1'), <int>{1, 4});
      expect(await fixture.store.readAll(), <String, int>{'lesson-1': 3});

      await fixture.store.clearSkippedSentence('lesson-1', 1);
      expect(await fixture.store.readSkippedSentences('lesson-1'), <int>{4});

      await fixture.store.clearSkippedSentences('lesson-1');
      expect(await fixture.store.readSkippedSentences('lesson-1'), isEmpty);
    },
  );

  test('V2 guide and retry queue metadata do not change totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasOpenedLearningGuide(), isFalse);
    await fixture.store.markLearningGuideOpened();
    await fixture.store.saveNeedsPracticeSentence('lesson-1', 1);
    await fixture.store.saveNeedsPracticeSentence('lesson-1', 4);
    await fixture.store.saveLesson('lesson-1', 2);

    expect(await fixture.store.hasOpenedLearningGuide(), isTrue);
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), <int>{
      1,
      4,
    });
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 2});

    await fixture.store.clearNeedsPracticeSentence('lesson-1', 1);
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), <int>{
      4,
    });
    await fixture.store.clearNeedsPracticeSentences('lesson-1');
    expect(await fixture.store.readNeedsPracticeSentences('lesson-1'), isEmpty);
  });

  test('V4 level mission completion does not inflate lesson totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasPassedLevelMission('C35-L1'), isFalse);
    await fixture.store.markLevelMissionPassed('C35-L1');
    await fixture.store.saveLesson('lesson-1', 2);

    expect(await fixture.store.hasPassedLevelMission('C35-L1'), isTrue);
    expect(await fixture.store.readAll(), <String, int>{'lesson-1': 2});
  });

  test(
    'V4 lesson activity completion stays separate from core progress',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveLesson('v4-lesson', 3);

      expect(
        await fixture.store.hasCompletedV4LessonActivity('v4-lesson'),
        isFalse,
      );
      expect(await fixture.store.readCompletedV4LessonActivities(), isEmpty);

      await fixture.store.markV4LessonActivityCompleted('v4-lesson');

      expect(
        await fixture.store.hasCompletedV4LessonActivity('v4-lesson'),
        isTrue,
      );
      expect(await fixture.store.readCompletedV4LessonActivities(), <String>{
        'v4-lesson',
      });
      expect(await fixture.store.readAll(), <String, int>{'v4-lesson': 3});
    },
  );

  test(
    'legacy stages migrate to Challenge while old data remains readable',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveResumeStage(
        'lesson-last',
        ListeningResumeStage.mission,
      );
      await fixture.store.saveMissionSelection('level-1', <String>[
        'm1',
        'm2',
        'm3',
        'm4',
      ]);
      await fixture.store.saveMissionAnswer('level-1', 'm1', correct: true);
      await fixture.store.saveMissionAnswer('level-1', 'm2', correct: false);
      await fixture.store.saveMissionWeakTargets('level-1', <String>{'t2'});
      await fixture.store.saveMissionAttempt('level-1', 1);

      expect(
        await fixture.store.readResumeStage('lesson-last'),
        ListeningResumeStage.challenge,
      );
      expect(await fixture.store.readMissionSelection('level-1'), <String>[
        'm1',
        'm2',
        'm3',
        'm4',
      ]);
      expect(await fixture.store.readMissionAnswers('level-1'), <String, bool>{
        'm1': true,
        'm2': false,
      });
      expect(await fixture.store.readMissionWeakTargets('level-1'), <String>{
        't2',
      });
      expect(await fixture.store.readMissionAttempt('level-1'), 1);
      expect(await fixture.store.readAll(), isEmpty);

      await fixture.store.clearMissionSession('level-1');
      expect(await fixture.store.readMissionSelection('level-1'), isEmpty);
      expect(await fixture.store.readMissionAnswers('level-1'), isEmpty);
      expect(await fixture.store.readMissionWeakTargets('level-1'), isEmpty);
      expect(await fixture.store.readMissionAttempt('level-1'), 0);
    },
  );

  test(
    'pending completion choice survives interruption and clears atomically',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.savePendingCompletionChoice(
        'lesson-choice',
        ListeningPendingChoiceStage.nextLevel,
      );

      expect(
        await fixture.store.readResumeStage('lesson-choice'),
        ListeningResumeStage.waitingForChoice,
      );
      expect(
        await fixture.store.readPendingCompletionChoice('lesson-choice'),
        ListeningPendingChoiceStage.nextLevel,
      );
      expect(await fixture.store.readAll(), isEmpty);

      await fixture.store.clearPendingCompletionChoice('lesson-choice');

      expect(
        await fixture.store.readResumeStage('lesson-choice'),
        ListeningResumeStage.completed,
      );
      expect(
        await fixture.store.readPendingCompletionChoice('lesson-choice'),
        isNull,
      );
    },
  );

  test('first core sentence start persists without changing totals', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    expect(await fixture.store.hasStartedLessonCore('lesson-first'), isFalse);
    await fixture.store.markLessonCoreStarted('lesson-first');

    expect(await fixture.store.hasStartedLessonCore('lesson-first'), isTrue);
    expect(await fixture.store.readAll(), isEmpty);
  });

  test(
    'session achievement cannot be downgraded by navigation or replay',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveSessionResult(
        'lesson-session',
        0,
        ListeningSessionResult.achieved,
      );
      await fixture.store.saveSessionResult(
        'lesson-session',
        0,
        ListeningSessionResult.skippedPending,
      );

      expect(
        await fixture.store.readSessionResult('lesson-session', 0),
        ListeningSessionResult.achieved,
      );
      expect(await fixture.store.readAll(), isEmpty);
    },
  );

  test(
    'Challenge selection survives interruption and rotates after processing',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveCurrentChallengeIndex('lesson-challenge', 2);
      expect(
        await fixture.store.readCurrentChallengeIndex('lesson-challenge'),
        2,
      );

      await fixture.store.markChallengeUsed(
        'lesson-challenge',
        index: 2,
        challengeCount: 4,
      );
      expect(
        await fixture.store.readCurrentChallengeIndex('lesson-challenge'),
        isNull,
      );
      expect(
        await fixture.store.readChallengeRotationMask('lesson-challenge'),
        4,
      );
      expect(await fixture.store.readAll(), isEmpty);
    },
  );

  test(
    'stars are idempotent and course completion event is one-shot',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      expect(await fixture.store.awardStar('lesson-1', 'core:t1'), isTrue);
      expect(await fixture.store.awardStar('lesson-1', 'core:t1'), isFalse);
      expect(await fixture.store.awardStar('lesson-1', 'challenge:q1'), isTrue);
      expect(await fixture.store.readEarnedStars('lesson-1'), <String>{
        'core:t1',
        'challenge:q1',
      });
      expect(await fixture.store.readTotalEarnedStars(), 2);

      expect(await fixture.store.isCourseCompleted('11-12'), isFalse);
      await fixture.store.markCourseCompleted('11-12');
      expect(await fixture.store.isCourseCompleted('11-12'), isTrue);
      expect(
        await fixture.store.markCourseCompletionEventCreated('11-12'),
        isTrue,
      );
      expect(
        await fixture.store.markCourseCompletionEventCreated('11-12'),
        isFalse,
      );
      expect(
        await fixture.store.hasCourseCompletionEventCreated('11-12'),
        isTrue,
      );
      expect(await fixture.store.readAll(), isEmpty);
    },
  );

  test(
    'topic-selection checkpoint survives interruption but not totals',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      await fixture.store.saveTopicSelectionCheckpoint(
        '3-5',
        levelNumber: 2,
        announceLevel: true,
      );

      final checkpoint = await fixture.store.readTopicSelectionCheckpoint(
        '3-5',
      );
      expect(checkpoint?.levelNumber, 2);
      expect(checkpoint?.announceLevel, isTrue);
      expect(await fixture.store.readAll(), isEmpty);

      await fixture.store.clearTopicSelectionCheckpoint('3-5');
      expect(await fixture.store.readTopicSelectionCheckpoint('3-5'), isNull);
    },
  );

  test('full-topic and full-level relearn preserve earned stars', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    for (final lessonId in <String>['lesson-1', 'lesson-2']) {
      await fixture.store.saveLesson(lessonId, 3);
      await fixture.store.markLessonCoreStarted(lessonId);
      await fixture.store.markV4LessonActivityCompleted(lessonId);
      await fixture.store.saveResumeStage(
        lessonId,
        ListeningResumeStage.completed,
      );
    }
    await fixture.store.awardStar('lesson-1', 'core:t1');
    await fixture.store.markLessonMissionStarSlots('lesson-1');
    await fixture.store.markLevelMissionPassed('level-1');
    await fixture.store.saveMissionSelection('level-1', <String>['m1']);

    await fixture.store.resetLevelForRelearn(
      levelId: 'level-1',
      lessonIds: const <String>['lesson-1', 'lesson-2'],
    );

    expect(await fixture.store.readAll(), <String, int>{
      'lesson-1': 3,
      'lesson-2': 3,
    });
    expect(await fixture.store.readStartedLessonCores(), isEmpty);
    expect(await fixture.store.readCompletedV4LessonActivities(), <String>{
      'lesson-1',
      'lesson-2',
    });
    expect(await fixture.store.hasLessonPendingRelearn('lesson-1'), isTrue);
    expect(await fixture.store.hasLessonPendingRelearn('lesson-2'), isTrue);
    expect(await fixture.store.hasPassedLevelMission('level-1'), isTrue);
    expect(await fixture.store.readMissionSelection('level-1'), isEmpty);
    expect(await fixture.store.readEarnedStars('lesson-1'), <String>{
      'core:t1',
    });
    expect(await fixture.store.hasLessonMissionStarSlots('lesson-1'), isTrue);

    await fixture.store.markLessonCoreStarted('lesson-1');
    expect(await fixture.store.hasLessonPendingRelearn('lesson-1'), isFalse);
    expect(await fixture.store.hasLessonPendingRelearn('lesson-2'), isTrue);
  });

  test('lesson entry snapshot decodes the progress file once', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    await fixture.store.saveLesson('lesson-1', 5);
    await fixture.store.saveCurrentSentence('lesson-1', 2);
    await fixture.store.markLearningGuideOpened();
    await fixture.store.markLessonCoreStarted('lesson-1');
    await fixture.store.saveResumeStage(
      'lesson-1',
      ListeningResumeStage.challenge,
    );

    ListeningProgressStore.debugForgetCachedFiles();
    ListeningProgressStore.debugStorageReadCount = 0;
    final entry = await fixture.store.readLessonEntrySnapshot('lesson-1');

    // Six values used to mean six reads and six JSON decodes of a file holding
    // every lesson the child had ever touched.
    expect(ListeningProgressStore.debugStorageReadCount, 1);
    expect(entry.completedSentences, 5);
    expect(entry.currentSentence, 2);
    expect(entry.hasOpenedLearningGuide, isTrue);
    expect(entry.resumeStage, ListeningResumeStage.challenge);
    expect(entry.hasStartedCore, isTrue);

    // And entering the same lesson again costs nothing at all.
    ListeningProgressStore.debugStorageReadCount = 0;
    await fixture.store.readLessonEntrySnapshot('lesson-1');
    expect(ListeningProgressStore.debugStorageReadCount, 0);
  });

  test('a run of writes never re-reads the file it just wrote', () async {
    // Finishing a lesson performs about ten of these in a row. Each one used to
    // read and re-parse the whole progress file first, so the end of a lesson
    // got slower the more the child had learned.
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.saveLesson('lesson-1', 5);

    ListeningProgressStore.debugStorageReadCount = 0;
    await fixture.store.markLessonCoreStarted('lesson-1');
    await fixture.store.markChallengeUsed(
      'lesson-1',
      index: 0,
      challengeCount: 3,
    );
    await fixture.store.markLessonChallengeProcessed('lesson-1');
    await fixture.store.markV4LessonActivityCompleted('lesson-1');
    await fixture.store.saveResumeStage(
      'lesson-1',
      ListeningResumeStage.completed,
    );

    expect(ListeningProgressStore.debugStorageReadCount, 0);

    // Every write still reached storage: a fresh store reads it all back.
    ListeningProgressStore.debugForgetCachedFiles();
    final reread = ListeningProgressStore(progressFilePath: fixture.file.path);
    expect(await reread.hasStartedLessonCore('lesson-1'), isTrue);
    expect(await reread.hasCompletedV4LessonActivity('lesson-1'), isTrue);
    expect(
      await reread.readResumeStage('lesson-1'),
      ListeningResumeStage.completed,
    );
    expect(await reread.readLesson('lesson-1'), 5);
  });

  test('lesson entry snapshot matches the individual accessors', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);

    await fixture.store.saveLesson('lesson-1', 3);
    await fixture.store.saveCurrentSentence('lesson-1', 1);
    await fixture.store.markV4LessonActivityCompleted('lesson-1');

    final entry = await fixture.store.readLessonEntrySnapshot('lesson-1');

    expect(
      entry.completedSentences,
      await fixture.store.readLesson('lesson-1'),
    );
    expect(
      entry.currentSentence,
      await fixture.store.readCurrentSentence('lesson-1'),
    );
    expect(
      entry.hasOpenedLearningGuide,
      await fixture.store.hasOpenedLearningGuide(),
    );
    expect(entry.resumeStage, await fixture.store.readResumeStage('lesson-1'));
    expect(
      entry.hasCompletedLessonActivity,
      await fixture.store.hasCompletedV4LessonActivity('lesson-1'),
    );
    expect(
      entry.hasStartedCore,
      await fixture.store.hasStartedLessonCore('lesson-1'),
    );
  });

  test('lesson entry snapshot honours overridden accessors', () async {
    // The entry screen is given hand-written fakes that extend the store and
    // replace single accessors. A snapshot that read the file directly would
    // silently ignore them and touch storage they never meant to use.
    final store = _FakeEntryProgressStore();

    ListeningProgressStore.debugStorageReadCount = 0;
    final entry = await store.readLessonEntrySnapshot('lesson-1');

    expect(ListeningProgressStore.debugStorageReadCount, 0);
    expect(entry.completedSentences, 7);
    expect(entry.currentSentence, 4);
    expect(entry.hasOpenedLearningGuide, isTrue);
    expect(entry.resumeStage, ListeningResumeStage.song);
    expect(entry.hasCompletedLessonActivity, isTrue);
    expect(entry.hasStartedCore, isTrue);
  });
  test('a write while a snapshot is open is not overwritten', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.saveLesson('lesson-1', 1);

    final store = _SlowEntryProgressStore(fixture.file.path);
    final snapshot = store.readLessonEntrySnapshot('lesson-1');
    await store.reachedSlowAccessor.future;

    // Another future writes while the snapshot is mid-flight. A cache shared
    // with writers would hand this writer the file as it looked before, and the
    // child would lose the progress written here.
    await fixture.store.markLessonCoreStarted('lesson-1');
    await fixture.store.saveCurrentSentence('lesson-1', 4);

    store.releaseSlowAccessor.complete();
    await snapshot;

    expect(await fixture.store.hasStartedLessonCore('lesson-1'), isTrue);
    expect(await fixture.store.readCurrentSentence('lesson-1'), 4);
    expect(await fixture.store.readLesson('lesson-1'), 1);
  });

  test('a snapshot does not serve stale values to another snapshot', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.saveLesson('lesson-a', 1);

    final store = _SlowEntryProgressStore(fixture.file.path);
    final first = store.readLessonEntrySnapshot('lesson-a');
    await store.reachedSlowAccessor.future;

    await fixture.store.saveLesson('lesson-b', 9);
    final second = await fixture.store.readLessonEntrySnapshot('lesson-b');

    store.releaseSlowAccessor.complete();
    await first;

    expect(second.completedSentences, 9);
  });

  test('a failed read inside a snapshot cannot empty the file', () async {
    final fixture = await _ProgressFixture.create();
    addTearDown(fixture.dispose);
    await fixture.store.saveLesson('lesson-1', 42);
    await fixture.store.saveLesson('lesson-2', 7);
    final saved = await fixture.file.readAsString();

    // The snapshot's first read fails, which the store reports as an empty
    // file. Caching that answer where a writer could see it would let the next
    // write replace real progress with nothing.
    await fixture.file.delete();
    // The cache would otherwise answer from what was written a moment ago; this
    // test is about what happens when storage itself fails.
    ListeningProgressStore.debugForgetCachedFiles();
    final store = _SlowEntryProgressStore(fixture.file.path);
    final snapshot = store.readLessonEntrySnapshot('lesson-1');
    await store.reachedSlowAccessor.future;
    await fixture.file.writeAsString(saved);

    await fixture.store.markLessonCoreStarted('lesson-1');

    store.releaseSlowAccessor.complete();
    await snapshot;

    expect(await fixture.store.readLesson('lesson-1'), 42);
    expect(await fixture.store.readLesson('lesson-2'), 7);
    expect(await fixture.store.hasStartedLessonCore('lesson-1'), isTrue);
  });
}

/// Holds a snapshot open partway through so another future can write.
class _SlowEntryProgressStore extends ListeningProgressStore {
  _SlowEntryProgressStore(String path) : super(progressFilePath: path);

  final Completer<void> reachedSlowAccessor = Completer<void>();
  final Completer<void> releaseSlowAccessor = Completer<void>();

  @override
  Future<bool> hasOpenedLearningGuide() async {
    final opened = await super.hasOpenedLearningGuide();
    if (!reachedSlowAccessor.isCompleted) reachedSlowAccessor.complete();
    await releaseSlowAccessor.future;
    return opened;
  }
}

class _FakeEntryProgressStore extends ListeningProgressStore {
  @override
  Future<int> readLesson(String lessonId) async => 7;

  @override
  Future<int> readCurrentSentence(String lessonId) async => 4;

  @override
  Future<bool> hasOpenedLearningGuide() async => true;

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      ListeningResumeStage.song;

  @override
  Future<bool> hasCompletedV4LessonActivity(String lessonId) async => true;

  @override
  Future<bool> hasStartedLessonCore(String lessonId) async => true;
}

class _ProgressFixture {
  const _ProgressFixture({
    required this.directory,
    required this.file,
    required this.store,
  });

  final Directory directory;
  final File file;
  final ListeningProgressStore store;

  static Future<_ProgressFixture> create() async {
    final directory = await Directory(
      'build/listening-progress-test-${DateTime.now().microsecondsSinceEpoch}',
    ).create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}progress.json',
    );
    return _ProgressFixture(
      directory: directory,
      file: file,
      store: ListeningProgressStore(progressFilePath: file.path),
    );
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
