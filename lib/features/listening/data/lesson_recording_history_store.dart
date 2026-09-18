import 'dart:convert';

import 'lesson_recording_history_persistence.dart';
import 'listening_topic_patch_migration.dart';

class LessonRecordingHistoryEntry {
  const LessonRecordingHistoryEntry({
    required this.id,
    required this.lessonId,
    required this.lessonTitle,
    required this.sentenceId,
    required this.sentenceNumber,
    required this.english,
    required this.vietnamese,
    required this.filePath,
    required this.duration,
    required this.createdAt,
    this.curriculumVersion,
  });

  factory LessonRecordingHistoryEntry.fromJson(Map<String, Object?> json) {
    return LessonRecordingHistoryEntry(
      id: json['id'] as String? ?? '',
      lessonId: json['lessonId'] as String? ?? '',
      lessonTitle: json['lessonTitle'] as String? ?? '',
      sentenceId: json['sentenceId'] as String? ?? '',
      sentenceNumber: json['sentenceNumber'] as int? ?? 0,
      english: json['english'] as String? ?? '',
      vietnamese: json['vietnamese'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      curriculumVersion: json['curriculumVersion'] as int?,
    );
  }

  final String id;
  final String lessonId;
  final String lessonTitle;
  final String sentenceId;
  final int sentenceNumber;
  final String english;
  final String vietnamese;
  final String filePath;
  final Duration duration;
  final DateTime createdAt;
  final int? curriculumVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'lessonId': lessonId,
    'lessonTitle': lessonTitle,
    'sentenceId': sentenceId,
    'sentenceNumber': sentenceNumber,
    'english': english,
    'vietnamese': vietnamese,
    'filePath': filePath,
    'durationMs': duration.inMilliseconds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (curriculumVersion != null) 'curriculumVersion': curriculumVersion,
  };
}

class LessonRecordingHistoryStore {
  const LessonRecordingHistoryStore({
    this.customPath,
    this.maxPerSentence = 3,
    this.topicPatchMigration,
  });

  final String? customPath;
  final int maxPerSentence;
  final ListeningTopicPatchMigration? topicPatchMigration;

  LessonRecordingHistoryPersistence get _persistence =>
      LessonRecordingHistoryPersistence(customPath: customPath);

  Future<List<LessonRecordingHistoryEntry>> readAll() async {
    final List<LessonRecordingHistoryEntry> original;
    try {
      final raw = await _persistence.read();
      if (raw == null || raw.trim().isEmpty) {
        return <LessonRecordingHistoryEntry>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) {
        return <LessonRecordingHistoryEntry>[];
      }
      original = decoded
          .whereType<Map<String, Object?>>()
          .map(LessonRecordingHistoryEntry.fromJson)
          .where((entry) => entry.id.isNotEmpty && entry.filePath.isNotEmpty)
          .toList();
    } catch (_) {
      return <LessonRecordingHistoryEntry>[];
    }
    // Fail without overwriting history if migration metadata is unavailable.
    final entries = await _migrateEntries(original);
    if (entries.indexed.any((item) => !identical(item.$2, original[item.$1]))) {
      await _persistence.write(
        jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      );
    }
    entries.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return entries;
  }

  Future<List<LessonRecordingHistoryEntry>> _migrateEntries(
    List<LessonRecordingHistoryEntry> entries,
  ) async {
    final affectedId = RegExp(r'^c(?:35|67)-l1-t0[12]-b\d+$');
    final affectedTarget = RegExp(r'^C(?:35|67)-L1-T0[12]-B\d+-T\d+$');
    if (!entries.any(
      (entry) =>
          affectedId.hasMatch(entry.lessonId) &&
          affectedTarget.hasMatch(entry.sentenceId),
    )) {
      return entries;
    }
    final patch =
        topicPatchMigration ?? await ListeningTopicPatchMigration.load();
    return entries.map((entry) {
      if (!patch.isAffectedLessonId(entry.lessonId)) return entry;
      final destination = patch.destinationForTarget(entry.sentenceId);
      if (destination == null && !patch.isDeprecatedTarget(entry.sentenceId)) {
        return entry;
      }
      final newLessonId =
          destination?.lessonId ??
          ListeningTopicPatchMigration.archivedLessonId(entry.lessonId);
      final newTitle = destination == null
          ? entry.lessonTitle
          : patch.newLessons[newLessonId]!.titleVi;
      final newNumber = destination == null
          ? entry.sentenceNumber
          : destination.sentenceIndex + 1;
      if (entry.lessonId == newLessonId &&
          entry.lessonTitle == newTitle &&
          entry.sentenceNumber == newNumber &&
          entry.curriculumVersion == 42) {
        return entry;
      }
      return LessonRecordingHistoryEntry.fromJson(<String, Object?>{
        ...entry.toJson(),
        'lessonId': newLessonId,
        'lessonTitle': newTitle,
        'sentenceNumber': newNumber,
        'curriculumVersion': 42,
      });
    }).toList();
  }

  Future<List<LessonRecordingHistoryEntry>> readForSentence(
    String lessonId,
    String sentenceId,
  ) async {
    return (await readAll())
        .where(
          (entry) =>
              entry.lessonId == lessonId && entry.sentenceId == sentenceId,
        )
        .take(maxPerSentence)
        .toList(growable: false);
  }

  Future<List<String>> addSuccessful(LessonRecordingHistoryEntry entry) async {
    final entries = await readAll();
    entry = (await _migrateEntries(<LessonRecordingHistoryEntry>[
      entry,
    ])).single;
    entries.insert(0, entry);
    final matching = entries
        .where(
          (candidate) =>
              candidate.lessonId == entry.lessonId &&
              candidate.sentenceId == entry.sentenceId,
        )
        .toList();
    final evicted = matching.skip(maxPerSentence).toList(growable: false);
    final evictedIds = evicted.map((candidate) => candidate.id).toSet();
    entries.removeWhere((candidate) => evictedIds.contains(candidate.id));
    await _persistence.write(
      jsonEncode(entries.map((candidate) => candidate.toJson()).toList()),
    );
    return evicted
        .map((candidate) => candidate.filePath)
        .toList(growable: false);
  }

  /// Removes every saved attempt for [lessonId] and returns the associated
  /// media paths so the caller can delete/revoke the actual audio files.
  ///
  /// An explicit "learn again from the beginning" action represents a fresh
  /// practice session. Keeping attempts from the previous run would make the
  /// first sentence look completed and can prevent the guided recorder from
  /// starting again.
  Future<List<String>> removeLesson(String lessonId) async {
    final entries = await readAll();
    final removedPaths = entries
        .where((entry) => entry.lessonId == lessonId)
        .map((entry) => entry.filePath)
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    entries.removeWhere((entry) => entry.lessonId == lessonId);
    await _persistence.write(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    return removedPaths;
  }
}
