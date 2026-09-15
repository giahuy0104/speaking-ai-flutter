import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';
import 'vocabulary_store.dart';

enum VocabularyPracticeMode { today, review }

class VocabularyReviewSessionSnapshot {
  const VocabularyReviewSessionSnapshot({
    required this.id,
    required this.entryIds,
    required this.triedEntryIds,
    required this.createdAt,
  });

  factory VocabularyReviewSessionSnapshot.fromJson(Map<String, Object?> json) =>
      VocabularyReviewSessionSnapshot(
        id: json['id'] as String? ?? '',
        entryIds: (json['entryIds'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
        triedEntryIds:
            (json['triedEntryIds'] as List<Object?>? ?? const <Object?>[])
                .whereType<String>()
                .toSet(),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final List<String> entryIds;
  final Set<String> triedEntryIds;
  final DateTime createdAt;

  bool get isValid => id.isNotEmpty && entryIds.isNotEmpty;

  VocabularyReviewSessionSnapshot copyWith({Set<String>? triedEntryIds}) =>
      VocabularyReviewSessionSnapshot(
        id: id,
        entryIds: entryIds,
        triedEntryIds: triedEntryIds ?? this.triedEntryIds,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'entryIds': entryIds,
    'triedEntryIds': triedEntryIds.toList(growable: false),
    'createdAt': createdAt.toIso8601String(),
  };
}

class VocabularyPracticeSession {
  const VocabularyPracticeSession({
    required this.id,
    required this.mode,
    required this.entryIds,
    required this.currentIndex,
    required this.results,
    required this.correctAudioPaths,
    required this.createdAt,
    this.dayKey,
  });

  factory VocabularyPracticeSession.fromJson(Map<String, Object?> json) {
    return VocabularyPracticeSession(
      id: json['id'] as String? ?? '',
      mode: VocabularyPracticeMode.values.firstWhere(
        (value) => value.name == json['mode'],
        orElse: () => VocabularyPracticeMode.today,
      ),
      entryIds: (json['entryIds'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      results: (json['results'] as Map<String, Object?>? ?? const {}).map(
        (key, value) => MapEntry(key, value == true),
      ),
      correctAudioPaths:
          (json['correctAudioPaths'] as Map<String, Object?>? ?? const {}).map(
            (key, value) => MapEntry(key, value as String),
          ),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      dayKey: json['dayKey'] as String?,
    );
  }

  final String id;
  final VocabularyPracticeMode mode;
  final List<String> entryIds;
  final int currentIndex;
  final Map<String, bool> results;
  final Map<String, String> correctAudioPaths;
  final DateTime createdAt;
  final String? dayKey;

  bool get isValid => id.isNotEmpty && entryIds.isNotEmpty;

  VocabularyPracticeSession copyWith({
    List<String>? entryIds,
    int? currentIndex,
    Map<String, bool>? results,
    Map<String, String>? correctAudioPaths,
  }) => VocabularyPracticeSession(
    id: id,
    mode: mode,
    entryIds: entryIds ?? this.entryIds,
    currentIndex: currentIndex ?? this.currentIndex,
    results: results ?? this.results,
    correctAudioPaths: correctAudioPaths ?? this.correctAudioPaths,
    createdAt: createdAt,
    dayKey: dayKey,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'mode': mode.name,
    'entryIds': entryIds,
    'currentIndex': currentIndex,
    'results': results,
    'correctAudioPaths': correctAudioPaths,
    'createdAt': createdAt.toIso8601String(),
    if (dayKey != null) 'dayKey': dayKey,
  };
}

class VocabularySessionStore {
  const VocabularySessionStore();

  static const _activeKey = 'innotrik.vocabulary-active-session.v2';
  static const _reviewSnapshotKey =
      'innotrik.vocabulary-review-session-snapshot.v4';
  static const _todaySuppressedKey = 'innotrik.vocabulary-today-suppressed.v2';
  static const _playbackCheckpointPrefix =
      'innotrik.vocabulary-playback-checkpoint.v2.';
  static const _lastVocabularyEntryDayKey =
      'innotrik.vocabulary-last-entry-day.v3';

  Future<VocabularyPracticeSession?> readActive() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_activeKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      if (decoded['mode'] == 'speakAgain') {
        await clearActive();
        return null;
      }
      final session = VocabularyPracticeSession.fromJson(decoded);
      return session.isValid ? session : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActive(VocabularyPracticeSession session) async {
    await (await SharedPreferences.getInstance()).setString(
      _activeKey,
      jsonEncode(session.toJson()),
    );
  }

  Future<void> clearActive() async {
    await (await SharedPreferences.getInstance()).remove(_activeKey);
  }

  Future<VocabularyReviewSessionSnapshot?> readReviewSessionSnapshot() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _reviewSnapshotKey,
      );
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final snapshot = VocabularyReviewSessionSnapshot.fromJson(decoded);
      return snapshot.isValid ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveReviewSessionSnapshot(
    VocabularyReviewSessionSnapshot snapshot,
  ) async {
    await (await SharedPreferences.getInstance()).setString(
      _reviewSnapshotKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> endReviewSession() async {
    final preferences = await SharedPreferences.getInstance();
    final active = await readActive();
    if (active?.mode == VocabularyPracticeMode.review) {
      await preferences.remove(_activeKey);
    }
    await preferences.remove(_reviewSnapshotKey);
  }

  Future<VocabularyPracticeSession?> prepareToday(
    VocabularyStore vocabularyStore, {
    DateTime? now,
    bool forceNextGroup = false,
  }) async {
    final currentTime = now ?? DateTime.now();
    final active = await readActive();
    if (active?.mode == VocabularyPracticeMode.today) {
      return _reconcile(active!, vocabularyStore);
    }
    if (!forceNextGroup && await isTodaySuppressed(currentTime)) {
      return null;
    }
    final view = await vocabularyStore.prepareTodayView(now: currentTime);
    if (view == null) {
      await clearActive();
      return null;
    }
    final entries = await vocabularyStore.todayEntries();
    final entryIds = entries
        .where((entry) => entry.todayStatus != TodayVocabularyStatus.heard)
        .map((entry) => entry.id)
        .toList(growable: false);
    if (entryIds.isEmpty) {
      await clearActive();
      return null;
    }
    final session = VocabularyPracticeSession(
      id: 'today:${view.dayKey}:${currentTime.microsecondsSinceEpoch}',
      mode: VocabularyPracticeMode.today,
      entryIds: entryIds,
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
      dayKey: view.dayKey,
    );
    await saveActive(session);
    return session;
  }

  Future<VocabularyPracticeSession?> prepareTodayReplay(
    VocabularyStore vocabularyStore, {
    DateTime? now,
  }) async {
    final view = await vocabularyStore.readTodayView();
    if (view == null) return null;
    final availableIds = (await vocabularyStore.read())
        .map((entry) => entry.id)
        .toSet();
    final entryIds = view.entryIds
        .where(availableIds.contains)
        .toList(growable: false);
    if (entryIds.isEmpty) return null;
    final currentTime = now ?? DateTime.now();
    final session = VocabularyPracticeSession(
      id: 'today-replay:${view.dayKey}:${currentTime.microsecondsSinceEpoch}',
      mode: VocabularyPracticeMode.today,
      entryIds: entryIds,
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
      dayKey: view.dayKey,
    );
    await saveActive(session);
    return session;
  }

  Future<VocabularyPracticeSession?> prepareReview(
    VocabularyStore vocabularyStore, {
    DateTime? now,
    bool forceNextGroup = false,
  }) async {
    final active = await readActive();
    if (!forceNextGroup && active?.mode == VocabularyPracticeMode.review) {
      return _reconcile(active!, vocabularyStore);
    }
    final currentTime = now ?? DateTime.now();
    var snapshot = await readReviewSessionSnapshot();
    if (snapshot == null) {
      final entryIds = (await vocabularyStore.reviewEntries())
          .map((entry) => entry.id)
          .toList(growable: false);
      if (entryIds.isEmpty) return null;
      snapshot = VocabularyReviewSessionSnapshot(
        id: 'review:${currentTime.microsecondsSinceEpoch}',
        entryIds: entryIds,
        triedEntryIds: const <String>{},
        createdAt: currentTime,
      );
      await _saveReviewSessionSnapshot(snapshot);
    }
    final availableIds = (await vocabularyStore.reviewEntries())
        .map((entry) => entry.id)
        .toSet();
    final entryIds = snapshot.entryIds
        .where(
          (id) =>
              availableIds.contains(id) &&
              !snapshot!.triedEntryIds.contains(id),
        )
        .take(5)
        .toList(growable: false);
    if (entryIds.isEmpty) {
      await endReviewSession();
      return null;
    }
    final session = VocabularyPracticeSession(
      id: '${snapshot.id}:block:${snapshot.triedEntryIds.length}',
      mode: VocabularyPracticeMode.review,
      entryIds: entryIds,
      currentIndex: 0,
      results: const <String, bool>{},
      correctAudioPaths: const <String, String>{},
      createdAt: currentTime,
    );
    await saveActive(session);
    return session;
  }

  Future<void> completeReviewBlock(Iterable<String> entryIds) async {
    final snapshot = await readReviewSessionSnapshot();
    if (snapshot != null) {
      await _saveReviewSessionSnapshot(
        snapshot.copyWith(
          triedEntryIds: <String>{...snapshot.triedEntryIds, ...entryIds},
        ),
      );
    }
    await clearActive();
  }

  Future<bool> hasPendingReviewEntries(VocabularyStore vocabularyStore) async {
    final snapshot = await readReviewSessionSnapshot();
    if (snapshot == null) return false;
    final availableIds = (await vocabularyStore.reviewEntries())
        .map((entry) => entry.id)
        .toSet();
    return snapshot.entryIds.any(
      (id) => availableIds.contains(id) && !snapshot.triedEntryIds.contains(id),
    );
  }

  Future<VocabularyPracticeSession?> _reconcile(
    VocabularyPracticeSession session,
    VocabularyStore vocabularyStore,
  ) async {
    final entries = await vocabularyStore.read();
    final available = entries.map((entry) => entry.id).toSet();
    final originalCurrentId = session.entryIds.isEmpty
        ? null
        : session.entryIds[session.currentIndex.clamp(
            0,
            session.entryIds.length - 1,
          )];
    var entryIds = session.entryIds
        .where(available.contains)
        .toList(growable: true);
    if (session.mode == VocabularyPracticeMode.today) {
      final view = await vocabularyStore.readTodayView();
      if (view != null) {
        entryIds = view.entryIds
            .where(available.contains)
            .toList(growable: true);
      }
    }
    if (entryIds.isEmpty) {
      await clearActive();
      return null;
    }
    final retainedCurrentIndex = originalCurrentId == null
        ? -1
        : entryIds.indexOf(originalCurrentId);
    final reconciled = session.copyWith(
      entryIds: entryIds,
      currentIndex: retainedCurrentIndex >= 0
          ? retainedCurrentIndex
          : session.currentIndex.clamp(0, entryIds.length - 1),
      results: Map<String, bool>.fromEntries(
        session.results.entries.where((entry) => available.contains(entry.key)),
      ),
      correctAudioPaths: Map<String, String>.fromEntries(
        session.correctAudioPaths.entries.where(
          (entry) => available.contains(entry.key),
        ),
      ),
    );
    await saveActive(reconciled);
    return reconciled;
  }

  Future<bool> isTodaySuppressed(DateTime now) async {
    final value = (await SharedPreferences.getInstance()).getString(
      _todaySuppressedKey,
    );
    return value == _dayKey(now);
  }

  Future<void> suppressToday(DateTime now) async {
    await (await SharedPreferences.getInstance()).setString(
      _todaySuppressedKey,
      _dayKey(now),
    );
  }

  Future<int> readPlaybackCheckpoint(String branch) async {
    return (await SharedPreferences.getInstance()).getInt(
          '$_playbackCheckpointPrefix$branch',
        ) ??
        0;
  }

  Future<void> savePlaybackCheckpoint(String branch, int index) async {
    await (await SharedPreferences.getInstance()).setInt(
      '$_playbackCheckpointPrefix$branch',
      index < 0 ? 0 : index,
    );
  }

  Future<void> clearPlaybackCheckpoint(String branch) async {
    await (await SharedPreferences.getInstance()).remove(
      '$_playbackCheckpointPrefix$branch',
    );
  }

  /// Persists the first vocabulary entry of the local day across app restarts.
  Future<bool> markAndCheckFirstEntryToday(DateTime now) async {
    final preferences = await SharedPreferences.getInstance();
    final today = _dayKey(now);
    if (preferences.getString(_lastVocabularyEntryDayKey) == today) {
      return false;
    }
    await preferences.setString(_lastVocabularyEntryDayKey, today);
    return true;
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
