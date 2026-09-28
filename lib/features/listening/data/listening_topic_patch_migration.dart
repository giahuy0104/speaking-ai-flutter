import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/listening_content.dart';

/// The immutable, shipped V4.1 -> V4.2 placement table. Target IDs identify
/// content; lesson numbers and sentence positions do not.
class ListeningTopicPatchMigration {
  ListeningTopicPatchMigration._({
    required this.oldLessons,
    required this.newLessons,
    required this.placements,
  }) : _byTarget = {
         for (final placement in placements)
           placement.source.targetId: placement,
       };

  factory ListeningTopicPatchMigration.fromJson(Map<String, dynamic> json) {
    Map<String, ListeningTopicPatchLesson> lessons(String key) {
      final result = <String, ListeningTopicPatchLesson>{};
      for (final wrapper in (json[key] as List).cast<Map>()) {
        final topic = wrapper['topic'] as Map;
        for (final lesson in (topic['lessons'] as List).cast<Map>()) {
          final parsed = ListeningTopicPatchLesson.fromJson(
            Map<String, dynamic>.from(lesson),
            startAge: wrapper['startAge'] as int,
            endAge: wrapper['endAge'] as int,
            topicNumber: topic['number'] as int,
          );
          result[parsed.id] = parsed;
        }
      }
      return Map.unmodifiable(result);
    }

    return ListeningTopicPatchMigration._(
      oldLessons: lessons('oldTopics'),
      newLessons: lessons('newTopics'),
      placements: List.unmodifiable(
        (json['placements'] as List).cast<Map>().map(
          (value) => ListeningTopicPatchPlacement(
            source: ListeningTopicPatchLocation.fromJson(
              Map<String, dynamic>.from(value['source'] as Map),
            ),
            destination: ListeningTopicPatchLocation.fromJson(
              Map<String, dynamic>.from(value['destination'] as Map),
            ),
          ),
        ),
      ),
    );
  }

  static const assetPath = 'assets/data/listening_topic_patch_v42.json';
  static const marker = '__listening-topic-patch-v42';
  static const archivePrefix = '__topic-patch-v41::';
  static const legacyPrefix = 'legacy-v41:';
  static const retainedRunSuffix = '::topic-patch-retained-run-v42';
  static const processedCoreMarker = '::topic-patch-processed-core-v42::';
  static Future<ListeningTopicPatchMigration>? _loading;

  static Future<ListeningTopicPatchMigration> load() => _loading ??= () async {
    try {
      return ListeningTopicPatchMigration.fromJson(
        jsonDecode(await rootBundle.loadString(assetPath))
            as Map<String, dynamic>,
      );
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();

  static String archivedLessonId(String id) => '$legacyPrefix$id';
  static String archivedLessonCode(String code) => 'LEGACY-V41:$code';
  static String unlockKeyForGroup(int startAge, int endAge) =>
      '__topic-patch-v42-unlocked-level:$startAge-$endAge';
  static String unlockKeyForLesson(String lessonId) =>
      '__topic-patch-v42-unlocked-lesson:$lessonId';

  final Map<String, ListeningTopicPatchLesson> oldLessons;
  final Map<String, ListeningTopicPatchLesson> newLessons;
  final List<ListeningTopicPatchPlacement> placements;
  final Map<String, ListeningTopicPatchPlacement> _byTarget;

  ListeningTopicPatchPlacement? placementForTarget(String targetId) =>
      _byTarget[targetId];

  ListeningTopicPatchLocation? destinationForTarget(String targetId) =>
      _byTarget[targetId]?.destination;

  bool isAffectedLessonId(String id) =>
      oldLessons.containsKey(id) || newLessons.containsKey(id);
  bool isAffectedLessonCode(String code) =>
      oldLessons.values.any((lesson) => lesson.code == code) ||
      newLessons.values.any((lesson) => lesson.code == code);
  bool isDeprecatedTarget(String targetId) =>
      !_byTarget.containsKey(targetId) &&
      oldLessons.values.any((lesson) => lesson.targetIds.contains(targetId));

  ListeningTopicPatchLocation? destinationForIndex(
    String oldLessonId,
    int sentenceIndex,
  ) {
    final lesson = oldLessons[oldLessonId];
    if (lesson == null ||
        sentenceIndex < 0 ||
        sentenceIndex >= lesson.targetIds.length) {
      return null;
    }
    return destinationForTarget(lesson.targetIds[sentenceIndex]);
  }

  /// True only for a complete lesson relocation, never a positional ID reuse.
  ListeningTopicPatchLesson? unchangedSourceFor(
    ListeningTopicPatchLesson destination,
  ) {
    if (destination.targetIds.isEmpty) return null;
    final first = placementForTarget(destination.targetIds.first);
    final source = oldLessons[first?.source.lessonId];
    if (source == null ||
        !_sameList(source.targetIds, destination.targetIds) ||
        source.challengeBank.length != destination.challengeBank.length ||
        source.songAudioId != destination.songAudioId ||
        source.songTitle != destination.songTitle) {
      return null;
    }
    for (var index = 0; index < source.challengeBank.length; index++) {
      if (!_sameChallenge(
        source.challengeBank[index],
        destination.challengeBank[index],
      )) {
        return null;
      }
    }
    return source;
  }

  /// No user audio is touched. A complete original affected-key snapshot is
  /// retained for checkpoint recovery and for future support/repair.
  Map<String, int> migrateProgress(
    Map<String, int> original, {
    ListeningContentCatalog? catalog,
  }) {
    if (original[marker] == 42) return Map.of(original);
    final result = Map<String, int>.of(original);
    for (final entry in original.entries) {
      if (_owningOldLesson(entry.key) == null) continue;
      result['$archivePrefix${entry.key}'] = entry.value;
      result.remove(entry.key);
    }

    // Archive retired star slots separately from the raw backup. They still
    // count as earned rewards, without counting the raw snapshot twice.
    for (final entry in original.entries) {
      final oldLesson = _owningOldLesson(entry.key);
      if (oldLesson == null || !entry.key.contains(_star)) continue;
      final suffix = entry.key.substring(oldLesson.id.length);
      final target = suffix.startsWith('${_star}core:')
          ? suffix.substring('${_star}core:'.length)
          : null;
      final destination = target == null ? null : destinationForTarget(target);
      final scope = destination?.lessonId ?? archivedLessonId(oldLesson.id);
      result['$scope$suffix'] = entry.value;
    }

    for (final destination in newLessons.values) {
      final unchanged = unchangedSourceFor(destination);
      if (unchanged != null) {
        for (final entry in original.entries) {
          if (!_isLessonKey(entry.key, unchanged.id)) continue;
          final suffix = entry.key.substring(unchanged.id.length);
          result['${destination.id}$suffix'] = entry.value;
          // A legacy non-Core star also belongs to this unchanged lesson.
          if (suffix.startsWith(_star)) {
            result.remove('${archivedLessonId(unchanged.id)}$suffix');
          }
        }
        if (original.containsKey(unchanged.id) ||
            original.containsKey('${unchanged.id}$_cursor') ||
            original['${unchanged.id}$_started'] == 1) {
          result['${destination.id}$retainedRunSuffix'] = 1;
        }
        continue;
      }
      _migrateChangedLesson(original, result, destination);
    }
    _preserveUnlockedLessons(original, result);
    if (catalog != null) _preserveUnlockedLevels(original, result, catalog);
    result[marker] = 42;
    return result;
  }

  void _preserveUnlockedLessons(
    Map<String, int> original,
    Map<String, int> result,
  ) {
    for (final destination in newLessons.values) {
      if (destination.number <= 1) continue;
      final previousVersion =
          oldLessons.values
              .where(
                (lesson) =>
                    lesson.startAge == destination.startAge &&
                    lesson.topicNumber == destination.topicNumber,
              )
              .toList()
            ..sort((left, right) => left.number.compareTo(right.number));
      final oldPosition = previousVersion
          .where((lesson) => lesson.number == destination.number)
          .firstOrNull;
      final unchanged = unchangedSourceFor(destination);
      final previousNumber = (unchanged ?? oldPosition)?.number;
      if (previousNumber == null || previousNumber <= 1) continue;
      final prerequisites = previousVersion.where(
        (lesson) => lesson.number < previousNumber,
      );
      if (prerequisites.isNotEmpty &&
          prerequisites.every((lesson) => _lessonCompleted(original, lesson))) {
        result[unlockKeyForLesson(destination.id)] = 1;
      }
    }
  }

  void _migrateChangedLesson(
    Map<String, int> original,
    Map<String, int> result,
    ListeningTopicPatchLesson destination,
  ) {
    final sources = <String>{};
    var completedPrefix = 0;
    var prefixOpen = true;
    var hasState = false;
    int? mappedCursor;
    for (var index = 0; index < destination.targetIds.length; index++) {
      final placement = placementForTarget(destination.targetIds[index]);
      if (placement == null) {
        prefixOpen = false;
        continue;
      }
      final source = placement.source;
      sources.add(source.lessonId);
      final oldIndex = source.sentenceIndex;
      final oldCount = original[source.lessonId] ?? 0;
      final session = original['${source.lessonId}$_session$oldIndex'];
      final knownResult = session != null && session > 0 && session <= 3;
      final processed = oldIndex < oldCount || knownResult;
      if (oldIndex < oldCount && !knownResult) {
        // Older releases only stored a contiguous processed count. Regrouping
        // can create a gap (for example J processed, F-I untouched). Preserve
        // that evidence without inventing achieved/skipped outcomes or stars.
        result['${destination.id}$processedCoreMarker$index'] = 1;
      }
      if (prefixOpen && processed) {
        completedPrefix++;
      } else {
        prefixOpen = false;
      }
      for (final suffix in [_session, _skipped, _needsPractice]) {
        final value = original['${source.lessonId}$suffix$oldIndex'];
        if (value == null) continue;
        result['${destination.id}$suffix$index'] = value;
        hasState = true;
      }
      if (original['${source.lessonId}$_cursor'] == oldIndex) {
        mappedCursor ??= index;
      }
      if (processed) hasState = true;
    }
    if (mappedCursor != null) hasState = true;
    if (hasState) {
      result['${destination.id}$retainedRunSuffix'] = 1;
      result[destination.id] = completedPrefix;
      if (destination.number > 1) {
        result[unlockKeyForLesson(destination.id)] = 1;
      }
      result['${destination.id}$_cursor'] =
          mappedCursor ??
          completedPrefix.clamp(0, destination.targetIds.length);
      result['${destination.id}$_started'] = 1;
      result['${destination.id}$_stage'] = 0; // Core.
    }

    var historicallyProcessedChallenge = false;
    for (
      var newIndex = 0;
      newIndex < destination.challengeBank.length;
      newIndex++
    ) {
      final challenge = destination.challengeBank[newIndex];
      for (final sourceId in sources) {
        final sourceLesson = oldLessons[sourceId]!;
        for (
          var oldIndex = 0;
          oldIndex < sourceLesson.challengeBank.length;
          oldIndex++
        ) {
          if (!_sameChallenge(
            challenge,
            sourceLesson.challengeBank[oldIndex],
          )) {
            continue;
          }
          if (((original['$sourceId$_rotation'] ?? 0) & (1 << oldIndex)) != 0) {
            historicallyProcessedChallenge = true;
          }
        }
      }
    }
    // The patch explicitly starts a fresh rotation for restructured lessons.
    // Old masks prove historical completion only; no operational cursor or
    // rotation mask is carried into a differently grouped challenge bank.

    if (completedPrefix == destination.targetIds.length &&
        destination.targetIds.isNotEmpty) {
      // Completing old Core is not evidence that a different Challenge or
      // Song was completed. Only an identical processed Challenge transfers.
      result['${destination.id}$_stage'] = 1; // Challenge.
      if (historicallyProcessedChallenge) {
        result['${destination.id}$_challengeProcessed'] = 1;
        final songCompleted =
            destination.songTitle == null ||
            sources.any((id) {
              final source = oldLessons[id]!;
              return source.songAudioId == destination.songAudioId &&
                  source.songTitle == destination.songTitle &&
                  _lessonCompleted(original, source);
            });
        if (songCompleted) {
          result['${destination.id}$_completed'] = 1;
          result['${destination.id}$_stage'] = 5; // Completed.
        } else {
          result['${destination.id}$_stage'] = 2; // Song.
        }
      }
    }
  }

  void _preserveUnlockedLevels(
    Map<String, int> original,
    Map<String, int> result,
    ListeningContentCatalog catalog,
  ) {
    for (final group in catalog.groups) {
      if (!oldLessons.values.any(
        (lesson) => lesson.startAge == group.startAge,
      )) {
        continue;
      }
      var highestUnlocked = 1;
      var sequentiallyUnlocked = true;
      for (final level in group.levels) {
        if (sequentiallyUnlocked && level.number > highestUnlocked) {
          highestUnlocked = level.number;
        }
        var complete = true;
        for (final topic in group.topics.where(
          (topic) => level.topicNumbers.contains(topic.number),
        )) {
          final previous = oldLessons.values
              .where(
                (lesson) =>
                    lesson.startAge == group.startAge &&
                    lesson.topicNumber == topic.number,
              )
              .toList();
          final lessons = previous.isNotEmpty
              ? previous
              : topic.lessons.map(
                  (lesson) => ListeningTopicPatchLesson.fromContent(
                    lesson,
                    startAge: group.startAge,
                    endAge: group.endAge,
                    topicNumber: topic.number,
                  ),
                );
          for (final lesson in lessons) {
            final done = _lessonCompleted(original, lesson);
            if (!done) complete = false;
            if (done ||
                (original[lesson.id] ?? 0) > 0 ||
                original['${lesson.id}$_started'] == 1 ||
                (original['${lesson.id}$_cursor'] ?? 0) > 0) {
              if (level.number > highestUnlocked) {
                highestUnlocked = level.number;
              }
            }
          }
        }
        sequentiallyUnlocked = sequentiallyUnlocked && complete;
      }
      if (highestUnlocked > 1) {
        result[unlockKeyForGroup(group.startAge, group.endAge)] =
            highestUnlocked;
      }
    }
  }

  ListeningTopicPatchLesson? _owningOldLesson(String key) {
    for (final lesson in oldLessons.values) {
      if (_isLessonKey(key, lesson.id)) return lesson;
    }
    return null;
  }

  static bool _isLessonKey(String key, String id) =>
      key == id || key.startsWith('$id::');
  static bool _lessonCompleted(
    Map<String, int> progress,
    ListeningTopicPatchLesson lesson,
  ) =>
      (progress[lesson.id] ?? 0) >= lesson.targetIds.length &&
      (progress['${lesson.id}$_completed'] == 1 ||
          (progress['${lesson.id}::v4-lesson-activity-passed'] == 1 &&
              progress['${lesson.id}$_stage'] == 5));

  static bool _sameChallenge(
    ListeningChallengeContent left,
    ListeningChallengeContent right,
  ) =>
      left.id == right.id &&
      left.targetId == right.targetId &&
      left.prompt == right.prompt &&
      left.correctAnswer == right.correctAnswer &&
      _sameList(left.choices, right.choices);

  static bool _sameList(List<String> left, List<String> right) =>
      left.length == right.length &&
      Iterable<int>.generate(
        left.length,
      ).every((index) => left[index] == right[index]);

  static const _cursor = '::current-sentence';
  static const _skipped = '::skipped-sentence::';
  static const _needsPractice = '::needs-practice::';
  static const _session = '::session-result-v5::';
  static const _stage = '::resume-stage';
  static const _started = '::core-started';
  static const _star = '::earned-star::';
  static const _completed = '::lesson-completed-v5';
  static const _challengeProcessed = '::challenge-processed-v5';
  static const _rotation = '::challenge-rotation-mask-v5';
}

class ListeningTopicPatchPlacement {
  const ListeningTopicPatchPlacement({
    required this.source,
    required this.destination,
  });
  final ListeningTopicPatchLocation source;
  final ListeningTopicPatchLocation destination;
}

class ListeningTopicPatchLocation {
  const ListeningTopicPatchLocation({
    required this.lessonId,
    required this.lessonCode,
    required this.startAge,
    required this.endAge,
    required this.topicNumber,
    required this.lessonNumber,
    required this.sentenceIndex,
    required this.targetId,
  });

  factory ListeningTopicPatchLocation.fromJson(Map<String, dynamic> json) =>
      ListeningTopicPatchLocation(
        lessonId: json['lessonId'] as String,
        lessonCode: json['lessonCode'] as String,
        startAge: json['startAge'] as int,
        endAge: json['endAge'] as int,
        topicNumber: json['topicNumber'] as int,
        lessonNumber: json['lessonNumber'] as int,
        sentenceIndex: json['sentenceIndex'] as int,
        targetId: json['targetId'] as String,
      );

  final String lessonId;
  final String lessonCode;
  final int startAge;
  final int endAge;
  final int topicNumber;
  final int lessonNumber;
  final int sentenceIndex;
  final String targetId;
}

class ListeningTopicPatchLesson {
  ListeningTopicPatchLesson.fromContent(
    ListeningLessonContent content, {
    required this.startAge,
    required this.endAge,
    required this.topicNumber,
  }) : id = content.id,
       code = content.code,
       number = content.number,
       titleEn = content.titleEn,
       titleVi = content.titleVi,
       targetIds = List.unmodifiable(
         content.sentences.map((sentence) => sentence.id),
       ),
       challengeBank = content.challengeBank,
       songAudioId = content.songAudioId,
       songTitle = content.songTitle;

  factory ListeningTopicPatchLesson.fromJson(
    Map<String, dynamic> json, {
    required int startAge,
    required int endAge,
    required int topicNumber,
  }) => ListeningTopicPatchLesson.fromContent(
    ListeningLessonContent.fromJson(json),
    startAge: startAge,
    endAge: endAge,
    topicNumber: topicNumber,
  );

  final String id;
  final String code;
  final int number;
  final int startAge;
  final int endAge;
  final int topicNumber;
  final String titleEn;
  final String titleVi;
  final List<String> targetIds;
  final List<ListeningChallengeContent> challengeBank;
  final String? songAudioId;
  final String? songTitle;
}
