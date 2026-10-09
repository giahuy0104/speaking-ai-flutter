import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'listening_progress_store.dart';
import 'listening_topic_patch_migration.dart';

class ActiveListeningSessionCheckpoint {
  const ActiveListeningSessionCheckpoint({
    required this.childAge,
    required this.topicNumber,
    required this.lessonNumber,
    required this.updatedAtEpochMs,
    this.contentVersion = '4.2',
  });

  factory ActiveListeningSessionCheckpoint.fromJson(Map<String, Object?> json) {
    return ActiveListeningSessionCheckpoint(
      childAge: (json['childAge'] as num?)?.toInt() ?? 0,
      topicNumber: (json['topicNumber'] as num?)?.toInt() ?? 0,
      lessonNumber: (json['lessonNumber'] as num?)?.toInt() ?? 0,
      updatedAtEpochMs: (json['updatedAtEpochMs'] as num?)?.toInt() ?? 0,
      contentVersion: json['contentVersion'] as String? ?? '',
    );
  }

  final int childAge;
  final int topicNumber;
  final int lessonNumber;
  final int updatedAtEpochMs;
  final String contentVersion;

  bool get isValid => childAge > 0 && topicNumber > 0 && lessonNumber > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'childAge': childAge,
    'topicNumber': topicNumber,
    'lessonNumber': lessonNumber,
    'updatedAtEpochMs': updatedAtEpochMs,
    'contentVersion': contentVersion,
  };
}

/// Durable pointer to the smallest safe lesson unit that can be reconstructed.
///
/// Sentence and authored activity progress remain in [ListeningProgressStore].
/// This file restores the route hierarchy after Android recreates its
/// foreground-service process or after iOS relaunches the app. A recording in
/// progress is deliberately never checkpointed and is therefore restarted
/// from the beginning of its item.
class ActiveListeningSessionStore {
  const ActiveListeningSessionStore({
    this.progressStore = const ListeningProgressStore(),
  });

  final ListeningProgressStore progressStore;

  static const String _preferenceKey = 'active-listening-session-v1';

  Future<ActiveListeningSessionCheckpoint?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_preferenceKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['invalidatedByTopicPatch'] == true) return null;
      final checkpoint = ActiveListeningSessionCheckpoint.fromJson(decoded);
      if (!checkpoint.isValid) return null;
      if (checkpoint.contentVersion == '4.2' ||
          checkpoint.childAge > 7 ||
          checkpoint.topicNumber > 2) {
        return checkpoint;
      }
      final migration = await ListeningTopicPatchMigration.load();
      final oldLesson = migration.oldLessons.values
          .where(
            (lesson) =>
                checkpoint.childAge >= lesson.startAge &&
                checkpoint.childAge <= lesson.endAge &&
                checkpoint.topicNumber == lesson.topicNumber &&
                checkpoint.lessonNumber == lesson.number,
          )
          .firstOrNull;
      if (oldLesson == null) return checkpoint;
      final oldProgress = await progressStore.readBeforeTopicPatch();
      final oldIndex =
          (oldProgress['${oldLesson.id}::current-sentence'] ??
                  oldProgress[oldLesson.id] ??
                  0)
              .clamp(0, oldLesson.targetIds.length - 1);
      final destination = migration.destinationForTarget(
        oldLesson.targetIds[oldIndex],
      );
      // Preserve the original pointer for rollback. A removed target, or one
      // moved to another course, must not silently change the child's age group.
      const archiveKey = 'active-listening-session-before-topic-patch-v42';
      if (!preferences.containsKey(archiveKey)) {
        await preferences.setString(archiveKey, raw);
      }
      // A newer navigation may have saved its checkpoint while assets/progress
      // were loading. Never overwrite that current route with an old pointer.
      if (preferences.getString(_preferenceKey) != raw) return read();
      if (destination == null ||
          checkpoint.childAge < destination.startAge ||
          checkpoint.childAge > destination.endAge) {
        await preferences.setString(
          _preferenceKey,
          jsonEncode({
            ...decoded,
            'contentVersion': '4.2',
            'invalidatedByTopicPatch': true,
          }),
        );
        return null;
      }
      final migrated = ActiveListeningSessionCheckpoint(
        childAge: checkpoint.childAge,
        topicNumber: destination.topicNumber,
        lessonNumber: destination.lessonNumber,
        updatedAtEpochMs: checkpoint.updatedAtEpochMs,
      );
      await preferences.setString(
        _preferenceKey,
        jsonEncode(migrated.toJson()),
      );
      return migrated;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required int childAge,
    required int topicNumber,
    required int lessonNumber,
  }) async {
    try {
      final checkpoint = ActiveListeningSessionCheckpoint(
        childAge: childAge,
        topicNumber: topicNumber,
        lessonNumber: lessonNumber,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      final encoded = jsonEncode(checkpoint.toJson());
      await (await SharedPreferences.getInstance()).setString(
        _preferenceKey,
        encoded,
      );
    } catch (_) {
      // Checkpoint persistence must never delay or block lesson navigation.
    }
  }

  Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_preferenceKey);
    } catch (_) {
      // Recovery metadata must never block the normal lesson exit path.
    }
  }
}
