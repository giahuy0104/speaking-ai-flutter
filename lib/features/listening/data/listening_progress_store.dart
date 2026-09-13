import 'dart:convert';

import 'listening_progress_persistence.dart';

enum ListeningResumeStage {
  core,
  challenge,
  song,
  // Legacy persisted values are retained only so V4 installations migrate
  // safely. The redesigned runtime never writes these stages.
  mission,
  reinforcement,
  completed,
  rolePlay,
}

enum ListeningSessionResult {
  pending,
  achieved,
  notAchievedPending,
  skippedPending,
}

class ListeningTopicSelectionCheckpoint {
  const ListeningTopicSelectionCheckpoint({
    required this.levelNumber,
    required this.announceLevel,
  });

  final int levelNumber;
  final bool announceLevel;
}

class ListeningProgressStore {
  const ListeningProgressStore({this.progressFilePath});

  static const String _resumeSuffix = '::current-sentence';
  static const String _skippedMarker = '::skipped-sentence::';
  static const String _learningGuideOpenedKey =
      '__listening-learning-guide-opened-v2';
  static const String _needsPracticeMarker = '::needs-practice::';
  static const String _levelMissionPassedMarker = '::level-mission-passed';
  static const String _legacyV4LessonActivityPassedMarker =
      '::v4-lesson-activity-passed';
  static const String _lessonCompletedMarker = '::lesson-completed-v5';
  static const String _challengeProcessedMarker = '::challenge-processed-v5';
  static const String _sessionResultMarker = '::session-result-v5::';
  static const String _currentChallengeIndexSuffix =
      '::current-challenge-index-v5';
  static const String _challengeRotationMaskSuffix =
      '::challenge-rotation-mask-v5';
  static const String _levelCompletionEventSuffix =
      '::level-completion-event-created-v5';
  static const String _resumeStageSuffix = '::resume-stage';
  static const String _coreStartedSuffix = '::core-started';
  static const String _missionSelectedMarker = '::mission-selected::';
  static const String _missionAnswerMarker = '::mission-answer::';
  static const String _missionWeakMarker = '::mission-weak::';
  static const String _missionAttemptSuffix = '::mission-attempt';
  static const String _starMarker = '::earned-star::';
  static const String _lessonMissionStarSlotsSuffix =
      '::lesson-mission-star-slots';
  static const String _lessonRelearnPendingSuffix = '::relearn-pending';
  static const String _courseCompletedSuffix = '::course-completed';
  static const String _courseCompletionEventSuffix =
      '::course-completion-event-created';
  static const String _topicSelectionLevelSuffix = '::topic-selection-level';
  static const String _topicSelectionAnnounceSuffix =
      '::topic-selection-announce';

  final String? progressFilePath;
  ListeningProgressPersistence get _persistence =>
      ListeningProgressPersistence(customPath: progressFilePath);

  Future<Map<String, int>> readAll() async {
    final progress = await _readRaw();
    progress.removeWhere(
      (key, _) =>
          key.endsWith(_resumeSuffix) ||
          key == _learningGuideOpenedKey ||
          key.contains(_skippedMarker) ||
          key.contains(_needsPracticeMarker) ||
          key.endsWith(_levelMissionPassedMarker) ||
          key.endsWith(_legacyV4LessonActivityPassedMarker) ||
          key.endsWith(_lessonCompletedMarker) ||
          key.endsWith(_challengeProcessedMarker) ||
          key.contains(_sessionResultMarker) ||
          key.endsWith(_currentChallengeIndexSuffix) ||
          key.endsWith(_challengeRotationMaskSuffix) ||
          key.endsWith(_levelCompletionEventSuffix) ||
          key.endsWith(_resumeStageSuffix) ||
          key.endsWith(_coreStartedSuffix) ||
          key.contains(_missionSelectedMarker) ||
          key.contains(_missionAnswerMarker) ||
          key.contains(_missionWeakMarker) ||
          key.endsWith(_missionAttemptSuffix) ||
          key.contains(_starMarker) ||
          key.endsWith(_lessonMissionStarSlotsSuffix) ||
          key.endsWith(_lessonRelearnPendingSuffix) ||
          key.endsWith(_courseCompletedSuffix) ||
          key.endsWith(_courseCompletionEventSuffix) ||
          key.endsWith(_topicSelectionLevelSuffix) ||
          key.endsWith(_topicSelectionAnnounceSuffix),
    );
    return progress;
  }

  Future<Map<String, int>> _readRaw() async {
    try {
      final raw = await _persistence.read();
      if (raw == null || raw.trim().isEmpty) {
        return <String, int>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return <String, int>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key, value is int ? value : 0),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<int> readLesson(String lessonId) async {
    return (await readAll())[lessonId] ?? 0;
  }

  Future<int> readCurrentSentence(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_resumeSuffix'] ?? progress[lessonId] ?? 0;
  }

  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress['$lessonId$_resumeSuffix'] = sentenceIndex < 0 ? 0 : sentenceIndex;
    await _writeRaw(progress);
  }

  Future<bool> hasOpenedLearningGuide() async {
    final progress = await _readRaw();
    return progress[_learningGuideOpenedKey] == 1;
  }

  Future<void> markLearningGuideOpened() async {
    final progress = await _readRaw();
    progress[_learningGuideOpenedKey] = 1;
    await _writeRaw(progress);
  }

  Future<Set<int>> readSkippedSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_skippedMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => int.tryParse(entry.key.substring(prefix.length)))
        .whereType<int>()
        .where((index) => index >= 0)
        .toSet();
  }

  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress['$lessonId$_skippedMarker$sentenceIndex'] = 1;
    await _writeRaw(progress);
  }

  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_skippedMarker$sentenceIndex');
    await _writeRaw(progress);
  }

  Future<void> clearSkippedSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_skippedMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    await _writeRaw(progress);
  }

  Future<Set<int>> readNeedsPracticeSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_needsPracticeMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => int.tryParse(entry.key.substring(prefix.length)))
        .whereType<int>()
        .where((index) => index >= 0)
        .toSet();
  }

  Future<void> saveNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    final progress = await _readRaw();
    progress['$lessonId$_needsPracticeMarker$sentenceIndex'] = 1;
    await _writeRaw(progress);
  }

  Future<void> clearNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_needsPracticeMarker$sentenceIndex');
    await _writeRaw(progress);
  }

  Future<void> clearNeedsPracticeSentences(String lessonId) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_needsPracticeMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    await _writeRaw(progress);
  }

  /// A level becomes complete only after its authored four-question mission
  /// reaches the V4 pass threshold. This marker is intentionally separate
  /// from per-lesson sentence progress so topic totals remain accurate.
  Future<bool> hasPassedLevelMission(String levelId) async {
    final progress = await _readRaw();
    return progress['$levelId$_levelMissionPassedMarker'] == 1;
  }

  Future<void> markLevelMissionPassed(String levelId) async {
    final progress = await _readRaw();
    progress['$levelId$_levelMissionPassedMarker'] = 1;
    await _writeRaw(progress);
  }

  /// A redesigned lesson is complete only after every Core is processed, its
  /// single Challenge is processed, and the optional Song is played/skipped.
  /// This historical marker is intentionally preserved during Relearn.
  Future<Set<String>> readCompletedV4LessonActivities() async {
    final progress = await _readRaw();
    final completed = progress.entries
        .where(
          (entry) =>
              entry.value == 1 && entry.key.endsWith(_lessonCompletedMarker),
        )
        .map(
          (entry) => entry.key.substring(
            0,
            entry.key.length - _lessonCompletedMarker.length,
          ),
        )
        .where((lessonId) => lessonId.isNotEmpty)
        .toSet();
    // V4 wrote the activity marker after Challenge, then moved Resume to
    // completed only after Song/Mission. Requiring both safely migrates only
    // genuinely completed historical lessons.
    for (final entry in progress.entries) {
      if (entry.value != 1 ||
          !entry.key.endsWith(_legacyV4LessonActivityPassedMarker)) {
        continue;
      }
      final lessonId = entry.key.substring(
        0,
        entry.key.length - _legacyV4LessonActivityPassedMarker.length,
      );
      if (progress['$lessonId$_resumeStageSuffix'] ==
          ListeningResumeStage.completed.index) {
        completed.add(lessonId);
      }
    }
    return completed;
  }

  Future<bool> hasCompletedV4LessonActivity(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_lessonCompletedMarker'] == 1 ||
        (progress['$lessonId$_legacyV4LessonActivityPassedMarker'] == 1 &&
            progress['$lessonId$_resumeStageSuffix'] ==
                ListeningResumeStage.completed.index);
  }

  Future<void> markV4LessonActivityCompleted(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_lessonCompletedMarker'] = 1;
    progress.remove('$lessonId$_currentChallengeIndexSuffix');
    await _writeRaw(progress);
  }

  Future<void> clearV4LessonActivityCompleted(String lessonId) async {
    final progress = await _readRaw();
    progress.remove('$lessonId$_lessonCompletedMarker');
    await _writeRaw(progress);
  }

  Future<bool> hasProcessedLessonChallenge(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_challengeProcessedMarker'] == 1 ||
        progress['$lessonId$_legacyV4LessonActivityPassedMarker'] == 1;
  }

  Future<void> markLessonChallengeProcessed(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_challengeProcessedMarker'] = 1;
    await _writeRaw(progress);
  }

  Future<ListeningSessionResult> readSessionResult(
    String lessonId,
    int sentenceIndex,
  ) async {
    final raw =
        (await _readRaw())['$lessonId$_sessionResultMarker$sentenceIndex'];
    if (raw == null || raw < 0 || raw >= ListeningSessionResult.values.length) {
      return ListeningSessionResult.pending;
    }
    return ListeningSessionResult.values[raw];
  }

  Future<Map<int, ListeningSessionResult>> readSessionResults(
    String lessonId,
  ) async {
    final progress = await _readRaw();
    final prefix = '$lessonId$_sessionResultMarker';
    final results = <int, ListeningSessionResult>{};
    for (final entry in progress.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final index = int.tryParse(entry.key.substring(prefix.length));
      if (index == null ||
          entry.value < 0 ||
          entry.value >= ListeningSessionResult.values.length) {
        continue;
      }
      results[index] = ListeningSessionResult.values[entry.value];
    }
    return results;
  }

  Future<void> saveSessionResult(
    String lessonId,
    int sentenceIndex,
    ListeningSessionResult result,
  ) async {
    final progress = await _readRaw();
    final key = '$lessonId$_sessionResultMarker$sentenceIndex';
    final previous = progress[key];
    // An achieved Core cannot be downgraded by a later replay in this session.
    if (previous == ListeningSessionResult.achieved.index &&
        result != ListeningSessionResult.achieved) {
      return;
    }
    progress[key] = result.index;
    await _writeRaw(progress);
  }

  Future<int?> readCurrentChallengeIndex(String lessonId) async {
    final value = (await _readRaw())['$lessonId$_currentChallengeIndexSuffix'];
    return value == null || value < 0 ? null : value;
  }

  Future<void> saveCurrentChallengeIndex(String lessonId, int index) async {
    final progress = await _readRaw();
    progress['$lessonId$_currentChallengeIndexSuffix'] = index;
    await _writeRaw(progress);
  }

  Future<int> readChallengeRotationMask(String lessonId) async {
    return (await _readRaw())['$lessonId$_challengeRotationMaskSuffix'] ?? 0;
  }

  Future<void> markChallengeUsed(
    String lessonId, {
    required int index,
    required int challengeCount,
  }) async {
    if (index < 0 || challengeCount <= 0 || challengeCount > 30) return;
    final progress = await _readRaw();
    final key = '$lessonId$_challengeRotationMaskSuffix';
    var mask = progress[key] ?? 0;
    final fullMask = (1 << challengeCount) - 1;
    if ((mask & fullMask) == fullMask) mask = 0;
    progress[key] = mask | (1 << index);
    progress.remove('$lessonId$_currentChallengeIndexSuffix');
    await _writeRaw(progress);
  }

  Future<void> resetLessonRun(String lessonId) async {
    final progress = await _readRaw();
    progress
      ..remove('$lessonId$_challengeProcessedMarker')
      ..remove('$lessonId$_currentChallengeIndexSuffix')
      ..remove('$lessonId$_coreStartedSuffix')
      ..remove('$lessonId$_resumeSuffix')
      ..remove('$lessonId$_resumeStageSuffix');
    progress.removeWhere(
      (key, _) =>
          key.startsWith('$lessonId$_sessionResultMarker') ||
          key.startsWith('$lessonId$_skippedMarker') ||
          key.startsWith('$lessonId$_needsPracticeMarker'),
    );
    progress['$lessonId$_resumeSuffix'] = 0;
    progress['$lessonId$_resumeStageSuffix'] = ListeningResumeStage.core.index;
    await _writeRaw(progress);
  }

  Future<ListeningResumeStage> readResumeStage(String lessonId) async {
    final value = (await _readRaw())['$lessonId$_resumeStageSuffix'];
    if (value == null ||
        value < 0 ||
        value >= ListeningResumeStage.values.length) {
      return ListeningResumeStage.core;
    }
    final stage = ListeningResumeStage.values[value];
    return switch (stage) {
      ListeningResumeStage.mission ||
      ListeningResumeStage.reinforcement ||
      ListeningResumeStage.rolePlay => ListeningResumeStage.challenge,
      _ => stage,
    };
  }

  Future<void> saveResumeStage(
    String lessonId,
    ListeningResumeStage stage,
  ) async {
    final progress = await _readRaw();
    progress['$lessonId$_resumeStageSuffix'] = stage.index;
    await _writeRaw(progress);
  }

  Future<bool> hasStartedLessonCore(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_coreStartedSuffix'] == 1;
  }

  Future<void> markLessonCoreStarted(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_coreStartedSuffix'] = 1;
    progress.remove('$lessonId$_lessonRelearnPendingSuffix');
    await _writeRaw(progress);
  }

  Future<bool> hasLessonPendingRelearn(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_lessonRelearnPendingSuffix'] == 1;
  }

  Future<Set<String>> readStartedLessonCores() async {
    final progress = await _readRaw();
    return progress.entries
        .where(
          (entry) => entry.value == 1 && entry.key.endsWith(_coreStartedSuffix),
        )
        .map(
          (entry) => entry.key.substring(
            0,
            entry.key.length - _coreStartedSuffix.length,
          ),
        )
        .where((lessonId) => lessonId.isNotEmpty)
        .toSet();
  }

  Future<void> saveTopicSelectionCheckpoint(
    String courseId, {
    required int levelNumber,
    required bool announceLevel,
  }) async {
    final progress = await _readRaw();
    progress['$courseId$_topicSelectionLevelSuffix'] = levelNumber;
    progress['$courseId$_topicSelectionAnnounceSuffix'] = announceLevel ? 1 : 0;
    await _writeRaw(progress);
  }

  Future<ListeningTopicSelectionCheckpoint?> readTopicSelectionCheckpoint(
    String courseId,
  ) async {
    final progress = await _readRaw();
    final level = progress['$courseId$_topicSelectionLevelSuffix'];
    if (level == null || level <= 0) return null;
    return ListeningTopicSelectionCheckpoint(
      levelNumber: level,
      announceLevel: progress['$courseId$_topicSelectionAnnounceSuffix'] == 1,
    );
  }

  Future<void> clearTopicSelectionCheckpoint(String courseId) async {
    final progress = await _readRaw();
    progress
      ..remove('$courseId$_topicSelectionLevelSuffix')
      ..remove('$courseId$_topicSelectionAnnounceSuffix');
    await _writeRaw(progress);
  }

  Future<void> saveMissionSelection(
    String levelId,
    List<String> missionIds,
  ) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionSelectedMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    progress.removeWhere(
      (key, _) => key.startsWith('$levelId$_missionAnswerMarker'),
    );
    for (var index = 0; index < missionIds.length; index += 1) {
      progress['$prefix${missionIds[index]}'] = index + 1;
    }
    await _writeRaw(progress);
  }

  Future<List<String>> readMissionSelection(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionSelectedMarker';
    final selected =
        progress.entries
            .where((entry) => entry.key.startsWith(prefix) && entry.value > 0)
            .toList(growable: false)
          ..sort((left, right) => left.value.compareTo(right.value));
    return selected
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveMissionAnswer(
    String levelId,
    String missionId, {
    required bool correct,
  }) async {
    final progress = await _readRaw();
    progress['$levelId$_missionAnswerMarker$missionId'] = correct ? 1 : -1;
    await _writeRaw(progress);
  }

  Future<Map<String, bool>> readMissionAnswers(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionAnswerMarker';
    return <String, bool>{
      for (final entry in progress.entries)
        if (entry.key.startsWith(prefix) && entry.value != 0)
          entry.key.substring(prefix.length): entry.value == 1,
    };
  }

  Future<void> saveMissionWeakTargets(
    String levelId,
    Iterable<String> targetIds,
  ) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionWeakMarker';
    progress.removeWhere((key, _) => key.startsWith(prefix));
    for (final id in targetIds.where((id) => id.trim().isNotEmpty)) {
      progress['$prefix${id.trim()}'] = 1;
    }
    await _writeRaw(progress);
  }

  Future<Set<String>> readMissionWeakTargets(String levelId) async {
    final progress = await _readRaw();
    final prefix = '$levelId$_missionWeakMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<int> readMissionAttempt(String levelId) async {
    return (await _readRaw())['$levelId$_missionAttemptSuffix'] ?? 0;
  }

  Future<void> saveMissionAttempt(String levelId, int attempt) async {
    final progress = await _readRaw();
    progress['$levelId$_missionAttemptSuffix'] = attempt < 0 ? 0 : attempt;
    await _writeRaw(progress);
  }

  Future<void> clearMissionSession(String levelId) async {
    final progress = await _readRaw();
    progress.removeWhere(
      (key, _) =>
          key.startsWith('$levelId$_missionSelectedMarker') ||
          key.startsWith('$levelId$_missionAnswerMarker') ||
          key.startsWith('$levelId$_missionWeakMarker') ||
          key == '$levelId$_missionAttemptSuffix',
    );
    await _writeRaw(progress);
  }

  Future<bool> awardStar(String scopeId, String starId) async {
    final progress = await _readRaw();
    final key = '$scopeId$_starMarker$starId';
    if (progress[key] == 1) return false;
    progress[key] = 1;
    await _writeRaw(progress);
    return true;
  }

  Future<Set<String>> readEarnedStars(String scopeId) async {
    final progress = await _readRaw();
    final prefix = '$scopeId$_starMarker';
    return progress.entries
        .where((entry) => entry.key.startsWith(prefix) && entry.value == 1)
        .map((entry) => entry.key.substring(prefix.length))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<int> readTotalEarnedStars() async {
    final progress = await _readRaw();
    return progress.entries
        .where((entry) => entry.key.contains(_starMarker) && entry.value == 1)
        .length;
  }

  Future<void> markLessonMissionStarSlots(String lessonId) async {
    final progress = await _readRaw();
    progress['$lessonId$_lessonMissionStarSlotsSuffix'] = 1;
    await _writeRaw(progress);
  }

  Future<bool> hasLessonMissionStarSlots(String lessonId) async {
    final progress = await _readRaw();
    return progress['$lessonId$_lessonMissionStarSlotsSuffix'] == 1;
  }

  Future<void> markCourseCompleted(String courseId) async {
    final progress = await _readRaw();
    progress['$courseId$_courseCompletedSuffix'] = 1;
    await _writeRaw(progress);
  }

  Future<bool> isCourseCompleted(String courseId) async {
    return (await _readRaw())['$courseId$_courseCompletedSuffix'] == 1;
  }

  /// Returns true exactly once, so the Parent App integration can emit one
  /// completion event without duplicating it after relearn sessions.
  Future<bool> markCourseCompletionEventCreated(String courseId) async {
    final progress = await _readRaw();
    final key = '$courseId$_courseCompletionEventSuffix';
    if (progress[key] == 1) return false;
    progress[key] = 1;
    await _writeRaw(progress);
    return true;
  }

  /// Returns true only for the first historical completion of this Level.
  Future<bool> markLevelCompletionEventCreated(String levelId) async {
    final progress = await _readRaw();
    final key = '$levelId$_levelCompletionEventSuffix';
    if (progress[key] == 1) return false;
    progress[key] = 1;
    await _writeRaw(progress);
    return true;
  }

  Future<void> saveLesson(String lessonId, int completedSentences) async {
    final progress = await _readRaw();
    final previous = progress[lessonId] ?? 0;
    if (completedSentences <= previous) {
      return;
    }
    progress[lessonId] = completedSentences;
    await _writeRaw(progress);
  }

  /// Restarts authored progress while intentionally preserving earned stars.
  Future<void> resetLessonsForRelearn(Iterable<String> lessonIds) async {
    final progress = await _readRaw();
    for (final lessonId in lessonIds.where((id) => id.trim().isNotEmpty)) {
      // Relearn is a new run, not a rollback of historical completion.
      progress['$lessonId$_resumeSuffix'] = 0;
      progress['$lessonId$_resumeStageSuffix'] =
          ListeningResumeStage.core.index;
      progress.remove('$lessonId$_challengeProcessedMarker');
      progress.remove('$lessonId$_currentChallengeIndexSuffix');
      progress.remove('$lessonId$_coreStartedSuffix');
      progress['$lessonId$_lessonRelearnPendingSuffix'] = 1;
      progress.removeWhere(
        (key, _) =>
            key.startsWith('$lessonId$_skippedMarker') ||
            key.startsWith('$lessonId$_needsPracticeMarker') ||
            key.startsWith('$lessonId$_sessionResultMarker'),
      );
    }
    await _writeRaw(progress);
  }

  Future<void> resetLevelForRelearn({
    required String levelId,
    required Iterable<String> lessonIds,
  }) async {
    final progress = await _readRaw();
    for (final lessonId in lessonIds.where((id) => id.trim().isNotEmpty)) {
      progress['$lessonId$_resumeSuffix'] = 0;
      progress['$lessonId$_resumeStageSuffix'] =
          ListeningResumeStage.core.index;
      progress.remove('$lessonId$_challengeProcessedMarker');
      progress.remove('$lessonId$_currentChallengeIndexSuffix');
      progress.remove('$lessonId$_coreStartedSuffix');
      progress['$lessonId$_lessonRelearnPendingSuffix'] = 1;
      progress.removeWhere(
        (key, _) =>
            key.startsWith('$lessonId$_skippedMarker') ||
            key.startsWith('$lessonId$_needsPracticeMarker') ||
            key.startsWith('$lessonId$_sessionResultMarker'),
      );
    }
    // Historical progression must remain stable while an older Level is
    // being relearned.
    progress.removeWhere(
      (key, _) =>
          key.startsWith('$levelId$_missionSelectedMarker') ||
          key.startsWith('$levelId$_missionAnswerMarker') ||
          key.startsWith('$levelId$_missionWeakMarker') ||
          key == '$levelId$_missionAttemptSuffix',
    );
    await _writeRaw(progress);
  }

  Future<void> _writeRaw(Map<String, int> progress) async {
    await _persistence.write(jsonEncode(progress));
  }
}
