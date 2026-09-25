import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/challenge_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    'Challenge completion serializes duplicate lifecycle commits exactly once',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);
      await fixture.store.saveCurrentChallengeIndex('lesson-challenge', 2);
      const result = ChallengeCompletionResult(
        operationId: 41,
        challengeId: 'challenge-3',
        challengeIndex: 2,
        targetId: 'target-3',
        outcome: ChallengeCompletionOutcome.correct,
      );

      final commits = await Future.wait<bool>(<Future<bool>>[
        fixture.store.commitChallengeCompletion(
          lessonId: 'lesson-challenge',
          result: result,
          challengeCount: 4,
          nextStage: ListeningResumeStage.song,
        ),
        fixture.store.commitChallengeCompletion(
          lessonId: 'lesson-challenge',
          result: result,
          challengeCount: 4,
          nextStage: ListeningResumeStage.song,
        ),
      ]);

      expect(commits.where((applied) => applied), hasLength(1));
      expect(
        await fixture.store.readChallengeCompletionOutcome(
          'lesson-challenge',
          'challenge-3',
        ),
        ChallengeCompletionOutcome.correct,
      );
      expect(
        await fixture.store.readCurrentChallengeIndex('lesson-challenge'),
        isNull,
      );
      expect(
        await fixture.store.readChallengeRotationMask('lesson-challenge'),
        1 << 2,
      );
      expect(
        await fixture.store.hasProcessedLessonChallenge('lesson-challenge'),
        isTrue,
      );
      expect(
        await fixture.store.readResumeStage('lesson-challenge'),
        ListeningResumeStage.song,
      );
    },
  );

  test(
    'Challenge completion without Song persists completed atomically',
    () async {
      final fixture = await _ProgressFixture.create();
      addTearDown(fixture.dispose);

      expect(
        await fixture.store.commitChallengeCompletion(
          lessonId: 'lesson-without-song',
          result: const ChallengeCompletionResult(
            operationId: 42,
            challengeId: 'challenge-1',
            challengeIndex: 0,
            targetId: 'target-1',
            outcome: ChallengeCompletionOutcome.needsPractice,
          ),
          challengeCount: 1,
          nextStage: ListeningResumeStage.completed,
        ),
        isTrue,
      );

      expect(
        await fixture.store.readResumeStage('lesson-without-song'),
        ListeningResumeStage.completed,
      );
      expect(
        await fixture.store.hasCompletedV4LessonActivity('lesson-without-song'),
        isTrue,
      );
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
