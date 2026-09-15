import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary_entry.dart';

class VocabularyTodayView {
  const VocabularyTodayView({
    required this.dayKey,
    required this.entryIds,
    required this.createdAt,
  });

  factory VocabularyTodayView.fromJson(Map<String, Object?> json) =>
      VocabularyTodayView(
        dayKey: json['dayKey'] as String? ?? '',
        entryIds: (json['entryIds'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String dayKey;
  final List<String> entryIds;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'dayKey': dayKey,
    'entryIds': entryIds,
    'createdAt': createdAt.toIso8601String(),
  };
}

class VocabularyStore {
  const VocabularyStore();

  static const _key = 'innotrik.vocabulary.v1';
  static const _parentAddCountKeyPrefix =
      'innotrik.vocabulary-parent-add-count.v2.';
  static const _todayViewKey = 'innotrik.vocabulary-today-view.v4';
  static const int parentDailyLimit = 5;
  static const Set<String> _legacyStarterIds = <String>{
    'family',
    'school',
    'happy',
  };
  static final StreamController<void> _changes =
      StreamController<void>.broadcast(sync: true);

  Stream<void> get changes => _changes.stream;

  Future<List<VocabularyEntry>> read() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null || encoded.isEmpty) {
      return const <VocabularyEntry>[];
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) {
        return const <VocabularyEntry>[];
      }
      final entries = decoded
          .whereType<Map<String, Object?>>()
          .map(VocabularyEntry.fromJson)
          .toList(growable: false);
      final migrated = entries
          .where((entry) => !_legacyStarterIds.contains(entry.id))
          .toList(growable: false);
      final normalized = jsonEncode(
        migrated.map((entry) => entry.toJson()).toList(),
      );
      if (normalized != encoded) {
        // Rewrite legacy vocabulary.v1 data in place.  Do not emit a change
        // event while reading: listeners may otherwise recursively reload.
        await preferences.setString(_key, normalized);
      }
      return migrated;
    } catch (_) {
      return const <VocabularyEntry>[];
    }
  }

  Future<void> write(List<VocabularyEntry> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
    _changes.add(null);
  }

  Future<List<VocabularyEntry>> parentEntries() async {
    final entries = (await read())
        .where((entry) => entry.isParentAdded)
        .toList(growable: false);
    return entries..sort((a, b) => a.addedAt.compareTo(b.addedAt));
  }

  Future<List<VocabularyEntry>> pendingParentEntries() async {
    final entries = (await read())
        .where((entry) => entry.isWaitingParent || entry.isTodayParent)
        .toList(growable: false);
    return entries..sort((a, b) => a.addedAt.compareTo(b.addedAt));
  }

  Future<List<VocabularyEntry>> learnedParentEntries() async {
    final entries = (await read())
        .where((entry) => entry.isUnlockedParent)
        .toList(growable: false);
    return entries..sort((a, b) => a.addedAt.compareTo(b.addedAt));
  }

  Future<VocabularyTodayView?> readTodayView() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _todayViewKey,
      );
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final view = VocabularyTodayView.fromJson(decoded);
      return view.dayKey.isEmpty || view.entryIds.isEmpty ? null : view;
    } catch (_) {
      return null;
    }
  }

  Future<List<VocabularyEntry>> todayEntries() async {
    final view = await readTodayView();
    if (view == null) return const <VocabularyEntry>[];
    final byId = <String, VocabularyEntry>{
      for (final entry in await read()) entry.id: entry,
    };
    return view.entryIds
        .map((id) => byId[id])
        .whereType<VocabularyEntry>()
        .toList(growable: false);
  }

  /// Creates TODAY_VIEW once, keeps it fixed for the local day, and returns an
  /// unfinished view from an earlier day before considering new waiting work.
  Future<VocabularyTodayView?> prepareTodayView({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final today = _dayKey(currentTime);
    var entries = await read();
    final existing = await readTodayView();
    if (existing != null && existing.dayKey == today) {
      final byId = <String, VocabularyEntry>{
        for (final entry in entries) entry.id: entry,
      };
      final retainedIds = existing.entryIds.where(byId.containsKey).toList();
      final retained = VocabularyTodayView(
        dayKey: existing.dayKey,
        entryIds: retainedIds,
        createdAt: existing.createdAt,
      );
      if (retainedIds.isEmpty) {
        await _clearTodayView();
      } else if (retainedIds.length != existing.entryIds.length) {
        await _writeTodayView(retained);
      }
      return retainedIds.isEmpty ? null : retained;
    }

    final byId = <String, VocabularyEntry>{
      for (final entry in entries) entry.id: entry,
    };
    final carry = <VocabularyEntry>[];
    if (existing != null) {
      for (final id in existing.entryIds) {
        final entry = byId[id];
        if (entry != null &&
            entry.isParentAdded &&
            entry.todayStatus != TodayVocabularyStatus.heard) {
          carry.add(entry);
        }
      }
    } else {
      carry.addAll(
        entries.where(
          (entry) =>
              entry.isTodayParent &&
              entry.todayStatus != TodayVocabularyStatus.heard,
        ),
      );
    }
    carry.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    if (carry.length > parentDailyLimit) {
      carry.removeRange(parentDailyLimit, carry.length);
    }
    final carryIds = carry.map((entry) => entry.id).toSet();
    final oldViewIds = existing?.entryIds.toSet() ?? const <String>{};
    entries = entries
        .map((entry) {
          if (carryIds.contains(entry.id)) {
            return entry.copyWith(
              parentState: ParentVocabularyState.today,
              todayDayKey: today,
            );
          }
          if (oldViewIds.contains(entry.id) &&
              entry.isTodayParent &&
              entry.todayStatus == TodayVocabularyStatus.heard &&
              !entry.isUnlockedParent) {
            return entry.copyWith(
              parentState: ParentVocabularyState.waiting,
              todayDayKey: null,
            );
          }
          return entry;
        })
        .toList(growable: false);

    final candidates =
        entries
            .where(
              (entry) =>
                  entry.isWaitingParent &&
                  entry.todayStatus != TodayVocabularyStatus.heard &&
                  !carryIds.contains(entry.id),
            )
            .toList()
          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    final selected = candidates
        .take(parentDailyLimit - carry.length)
        .toList(growable: false);
    if (carry.isEmpty && selected.isEmpty) {
      await _clearTodayView();
      await write(entries);
      return null;
    }
    final selectedIds = selected.map((entry) => entry.id).toSet();
    final newBatchId =
        'parent-batch:$today:${currentTime.microsecondsSinceEpoch}';
    entries = entries
        .map(
          (entry) => selectedIds.contains(entry.id)
              ? entry.copyWith(
                  parentState: ParentVocabularyState.today,
                  todayStatus: TodayVocabularyStatus.notHeard,
                  todayDayKey: today,
                  originBatchId: entry.originBatchId ?? newBatchId,
                )
              : entry,
        )
        .toList(growable: false);
    await write(entries);
    final view = VocabularyTodayView(
      dayKey: today,
      entryIds: <String>[
        ...carry.map((entry) => entry.id),
        ...selected.map((entry) => entry.id),
      ],
      createdAt: currentTime,
    );
    await _writeTodayView(view);
    return view;
  }

  /// Marks one listen-only item HEARD. The complete origin batch moves to the
  /// parent library atomically only after every item in that batch is HEARD.
  Future<bool> markTodayHeard(String entryId, {DateTime? now}) async {
    final entries = await read();
    final target = entries.where((entry) => entry.id == entryId).firstOrNull;
    if (target == null || !target.isParentAdded) return false;
    final heardAt = now ?? DateTime.now();
    final batchId = target.originBatchId ?? target.id;
    var updated = entries
        .map(
          (entry) => entry.id == entryId
              ? entry.copyWith(
                  todayStatus: TodayVocabularyStatus.heard,
                  lastPracticedAt: heardAt,
                )
              : entry,
        )
        .toList(growable: false);
    final batch = updated.where(
      (entry) =>
          entry.isParentAdded && (entry.originBatchId ?? entry.id) == batchId,
    );
    final unlock =
        batch.isNotEmpty &&
        batch.every(
          (entry) => entry.todayStatus == TodayVocabularyStatus.heard,
        );
    if (unlock) {
      updated = updated
          .map(
            (entry) =>
                entry.isParentAdded &&
                    (entry.originBatchId ?? entry.id) == batchId
                ? entry.copyWith(
                    parentState: ParentVocabularyState.unlocked,
                    status: VocabularyLearningStatus.learnedWell,
                    collection: VocabularyCollection.saved,
                    unlockedAt: entry.unlockedAt ?? heardAt,
                    introducedAt: entry.introducedAt ?? heardAt,
                  )
                : entry,
          )
          .toList(growable: false);
    }
    await write(updated);
    return unlock;
  }

  Future<List<VocabularyEntry>> reviewEntries() async {
    final entries =
        (await read())
            .where((entry) => entry.needsPractice && !entry.isParentAdded)
            .toList()
          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    final byTarget = <String, VocabularyEntry>{};
    for (final entry in entries) {
      final target = _normalizedText(entry.word);
      byTarget.putIfAbsent(target, () => entry);
    }
    final deduplicated = byTarget.values.toList();
    deduplicated.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return deduplicated;
  }

  Future<List<VocabularyEntry>> starEntries() async {
    final entries = (await read())
        .where(
          (entry) =>
              entry.isStar &&
              entry.source == VocabularySource.topicCore &&
              (entry.correctAudioPath?.trim().isNotEmpty ?? false),
        )
        .toList(growable: false);
    return entries..sort(
      (a, b) => (a.earnedAt ?? a.addedAt).compareTo(b.earnedAt ?? b.addedAt),
    );
  }

  Future<int> parentAddCountForDay(DateTime day) async {
    final preferences = await SharedPreferences.getInstance();
    final key = '$_parentAddCountKeyPrefix${_dayKey(day)}';
    final stored = preferences.getInt(key);
    if (stored != null) {
      return stored;
    }
    final count = (await read())
        .where(
          (entry) => entry.isParentAdded && _isSameLocalDay(entry.addedAt, day),
        )
        .length;
    await preferences.setInt(key, count);
    return count;
  }

  Future<List<VocabularyEntry>> addParentEntries(
    List<VocabularyTranslation> selections, {
    DateTime? now,
    int childAge = 5,
  }) async {
    if (selections.isEmpty) {
      return read();
    }
    if (selections.length > 3) {
      throw const VocabularyValidationException(
        'Mỗi lần chỉ được chọn tối đa 3 nội dung.',
      );
    }
    final createdAt = now ?? DateTime.now();
    final usedToday = await parentAddCountForDay(createdAt);
    if (usedToday + selections.length > parentDailyLimit) {
      throw VocabularyDailyLimitException(
        remaining: (parentDailyLimit - usedToday).clamp(0, parentDailyLimit),
      );
    }

    final entries = await read();
    final batch = <String>[];
    for (final selection in selections) {
      _validateTranslation(selection, childAge: childAge);
      final english = selection.englishText.trim();
      final normalized = _normalizedText(english);
      final duplicate = entries
          .where((entry) => _isSameOrNearDuplicate(entry.word, english))
          .firstOrNull;
      if (duplicate != null) {
        if (!duplicate.isParentAdded) {
          throw const VocabularyTopicDuplicateException();
        }
        throw const VocabularyDuplicateException();
      }
      if (batch.any((item) => _isSameOrNearDuplicate(item, normalized))) {
        throw const VocabularyDuplicateException();
      }
      batch.add(normalized);
    }

    final additions = <VocabularyEntry>[
      for (var index = 0; index < selections.length; index++)
        VocabularyEntry(
          id: 'parent:${createdAt.microsecondsSinceEpoch}:$index',
          word: selections[index].englishText.trim(),
          meaning: selections[index].vietnameseText.trim(),
          addedAt: createdAt.add(Duration(microseconds: index)),
          source: VocabularySource.parent,
          status: VocabularyLearningStatus.unlearned,
          contentKind: VocabularyEntry.inferContentKind(
            selections[index].englishText,
          ),
          parentState: ParentVocabularyState.waiting,
          todayStatus: null,
          originBatchId: null,
        ),
    ];
    final updated = <VocabularyEntry>[...additions.reversed, ...entries];
    await write(updated);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      '$_parentAddCountKeyPrefix${_dayKey(createdAt)}',
      usedToday + additions.length,
    );
    return updated;
  }

  Future<void> validateParentCandidate(
    VocabularyTranslation candidate, {
    int childAge = 5,
  }) async {
    _validateTranslation(candidate, childAge: childAge);
    final duplicate = (await read())
        .where(
          (entry) => _isSameOrNearDuplicate(entry.word, candidate.englishText),
        )
        .firstOrNull;
    if (duplicate == null) return;
    if (duplicate.isParentAdded) throw const VocabularyDuplicateException();
    throw const VocabularyTopicDuplicateException();
  }

  /// Removes invalid/duplicate suggestions before they are visible to a
  /// parent. A bad AI/curated option therefore cannot be selected or saved.
  Future<List<VocabularyTranslation>> filterParentSuggestions(
    Iterable<VocabularyTranslation> candidates, {
    int limit = 3,
    int childAge = 5,
  }) async {
    final entries = await read();
    final result = <VocabularyTranslation>[];
    for (final candidate in candidates) {
      try {
        _validateTranslation(candidate, childAge: childAge);
      } on VocabularyValidationException {
        continue;
      }
      if (entries.any(
        (entry) => _isSameOrNearDuplicate(entry.word, candidate.englishText),
      )) {
        continue;
      }
      if (result.any(
        (item) =>
            _isSameOrNearDuplicate(item.englishText, candidate.englishText) &&
            _isSameOrNearDuplicate(
              item.vietnameseText,
              candidate.vietnameseText,
            ),
      )) {
        continue;
      }
      result.add(candidate);
      if (result.length >= limit) break;
    }
    return result;
  }

  Future<void> markLearningStarted(String entryId, {DateTime? now}) async {
    final entries = await read();
    final startedAt = now ?? DateTime.now();
    var changed = false;
    final updated = entries
        .map((entry) {
          if (entry.id != entryId || entry.learningStartedAt != null) {
            return entry;
          }
          changed = true;
          return entry.copyWith(
            learningStartedAt: startedAt,
            parentState: entry.isParentAdded
                ? ParentVocabularyState.unlocked
                : entry.parentState,
            unlockedAt: entry.isParentAdded
                ? entry.unlockedAt ?? startedAt
                : entry.unlockedAt,
          );
        })
        .toList(growable: false);
    if (changed) {
      await write(updated);
    }
  }

  Future<void> deleteParentEntry(String entryId) async {
    final entries = await read();
    final entry = entries.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) {
      return;
    }
    if (!entry.canParentDelete) {
      throw const VocabularyLockedException();
    }
    var updated = entries.where((item) => item.id != entryId).toList();
    final view = await readTodayView();
    if (view == null || !view.entryIds.contains(entryId)) {
      await write(updated);
      return;
    }
    final retainedIds = view.entryIds.where((id) => id != entryId).toList();
    final replacement =
        updated
            .where(
              (item) =>
                  item.isWaitingParent &&
                  item.todayStatus != TodayVocabularyStatus.heard &&
                  !retainedIds.contains(item.id),
            )
            .toList()
          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    if (replacement.isNotEmpty && retainedIds.length < parentDailyLimit) {
      final next = replacement.first;
      final backfillBatchId =
          'parent-batch:${view.dayKey}:${DateTime.now().microsecondsSinceEpoch}';
      retainedIds.add(next.id);
      updated = updated
          .map(
            (item) => item.id == next.id
                ? item.copyWith(
                    parentState: ParentVocabularyState.today,
                    todayStatus: TodayVocabularyStatus.notHeard,
                    todayDayKey: view.dayKey,
                    originBatchId: item.originBatchId ?? backfillBatchId,
                  )
                : item,
          )
          .toList(growable: false);
    }
    await write(updated);
    if (retainedIds.isEmpty) {
      await _clearTodayView();
    } else {
      await _writeTodayView(
        VocabularyTodayView(
          dayKey: view.dayKey,
          entryIds: retainedIds,
          createdAt: view.createdAt,
        ),
      );
    }
  }

  Future<void> updateParentEntry({
    required String entryId,
    required VocabularyTranslation value,
  }) async {
    final entries = await read();
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) {
      return;
    }
    if (!entries[index].canParentEdit) {
      throw const VocabularyLockedException();
    }
    _validateTranslation(value);
    final duplicate = entries
        .where(
          (entry) =>
              entry.id != entryId &&
              _isSameOrNearDuplicate(entry.word, value.englishText),
        )
        .firstOrNull;
    if (duplicate != null) {
      if (!duplicate.isParentAdded) {
        throw const VocabularyTopicDuplicateException();
      }
      throw const VocabularyDuplicateException();
    }
    final updated = List<VocabularyEntry>.of(entries);
    updated[index] = updated[index].copyWith(
      word: value.englishText.trim(),
      meaning: value.vietnameseText.trim(),
    );
    await write(updated);
  }

  /// Applies all provisional results from one group in a single persistence
  /// write. A pass always wins when the child revisits an item in the group.
  Future<void> commitPracticeResults({
    required Map<String, bool> results,
    Map<String, String> correctAudioPaths = const <String, String>{},
    DateTime? now,
  }) async {
    if (results.isEmpty) {
      return;
    }
    final practicedAt = now ?? DateTime.now();
    final entries = await read();
    final retryResultsByTarget = <String, bool>{};
    for (final entry in entries) {
      final result = results[entry.id];
      if (result != null && entry.needsPractice) {
        retryResultsByTarget[_normalizedText(entry.word)] = result;
      }
    }
    final updated = <VocabularyEntry>[];
    for (final entry in entries) {
      final passed =
          results[entry.id] ??
          (entry.needsPractice
              ? retryResultsByTarget[_normalizedText(entry.word)]
              : null);
      if (passed == null) {
        updated.add(entry);
        continue;
      }
      if (passed && !entry.isParentAdded && entry.needsPractice) {
        // Topic targets have no parent-owned archive. Passing removes only the
        // retry record and never creates a vocabulary star.
        continue;
      }
      updated.add(
        entry.copyWith(
          collection: passed
              ? VocabularyCollection.saved
              : VocabularyCollection.review,
          status: passed
              ? VocabularyLearningStatus.learnedWell
              : VocabularyLearningStatus.needsPractice,
          correctAudioPath: passed
              ? correctAudioPaths[entry.id] ?? entry.correctAudioPath
              : entry.correctAudioPath,
          lastPracticedAt: practicedAt,
          learningStartedAt: entry.learningStartedAt ?? practicedAt,
        ),
      );
    }
    await write(updated);
  }

  Future<void> markParentPracticeResult({
    required String entryId,
    required bool passed,
    String? correctAudioPath,
    DateTime? now,
  }) => commitPracticeResults(
    results: <String, bool>{entryId: passed},
    correctAudioPaths: correctAudioPath == null
        ? const <String, String>{}
        : <String, String>{entryId: correctAudioPath},
    now: now,
  );

  Future<void> clearTopicReviewTarget(String english) async {
    final target = _normalizedText(english);
    final entries = await read();
    final updated = entries
        .where(
          (entry) =>
              !entry.needsPractice ||
              entry.isParentAdded ||
              _normalizedText(entry.word) != target,
        )
        .toList(growable: false);
    if (updated.length != entries.length) await write(updated);
  }

  /// Marks parent-added words as already introduced by the MAIN assistant.
  /// They remain visible in Family, but are no longer announced as new on the
  /// next vocabulary session.
  Future<void> markIntroduced(Iterable<String> entryIds) async {
    final ids = entryIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final entries = await read();
    final now = DateTime.now();
    var changed = false;
    final updated = entries
        .map((entry) {
          if (!ids.contains(entry.id) || entry.introducedAt != null) {
            return entry;
          }
          changed = true;
          return entry.copyWith(introducedAt: now);
        })
        .toList(growable: false);
    if (changed) {
      await write(updated);
    }
  }

  /// Adds a lesson sentence to a learning collection, or moves the existing
  /// sentence between Review and Stars without creating a duplicate.
  Future<void> upsertLessonSentence({
    required String lessonCode,
    required String sentenceId,
    required String english,
    required String vietnamese,
    required VocabularyCollection collection,
    VocabularySource source = VocabularySource.topicCore,
    String? starSlotId,
    String? correctAudioPath,
    DateTime? occurredAt,
  }) async {
    final entries = await read();
    final normalizedEnglish = english.trim().toLowerCase();
    final eventTime = occurredAt ?? DateTime.now();
    final resolvedStarSlotId = collection == VocabularyCollection.star
        ? starSlotId ?? '$lessonCode:$sentenceId'
        : null;
    final stableId = resolvedStarSlotId == null
        ? 'lesson:$lessonCode:$sentenceId'
        : 'star:${_storageId(resolvedStarSlotId)}';
    VocabularyEntry? previousStar;
    if (resolvedStarSlotId != null) {
      previousStar = entries
          .where((entry) => entry.starSlotId == resolvedStarSlotId)
          .firstOrNull;
    }
    final updated = entries
        .where((entry) {
          if ((entry.id == stableId &&
                  (collection != VocabularyCollection.review ||
                      !entry.isStar)) ||
              (resolvedStarSlotId != null &&
                  entry.starSlotId == resolvedStarSlotId)) {
            return false;
          }
          if (collection == VocabularyCollection.review) {
            return !entry.needsPractice ||
                _normalizedText(entry.word) !=
                    _normalizedText(normalizedEnglish);
          }
          if (collection == VocabularyCollection.star && entry.needsPractice) {
            final sameTarget =
                _normalizedText(entry.word) ==
                _normalizedText(normalizedEnglish);
            return !sameTarget || entry.isParentAdded;
          }
          return true;
        })
        .map((entry) {
          final promotesMatchingParent =
              collection == VocabularyCollection.star &&
              entry.isParentAdded &&
              entry.needsPractice &&
              _normalizedText(entry.word) == _normalizedText(normalizedEnglish);
          if (!promotesMatchingParent) return entry;
          return entry.copyWith(
            collection: VocabularyCollection.saved,
            status: VocabularyLearningStatus.learnedWell,
            correctAudioPath: correctAudioPath ?? entry.correctAudioPath,
            lastPracticedAt: eventTime,
          );
        })
        .toList();
    updated.insert(
      0,
      VocabularyEntry(
        id: previousStar?.id ?? stableId,
        word: english.trim(),
        meaning: vietnamese.trim(),
        addedAt: previousStar?.addedAt ?? eventTime,
        collection: collection,
        status: collection == VocabularyCollection.review
            ? VocabularyLearningStatus.needsPractice
            : VocabularyLearningStatus.learnedWell,
        source: source,
        sourceLessonCode: lessonCode,
        sourceSentenceId: sentenceId,
        starSlotId: resolvedStarSlotId,
        correctAudioPath: correctAudioPath ?? previousStar?.correctAudioPath,
        lastPracticedAt: eventTime,
        earnedAt: collection == VocabularyCollection.star
            ? previousStar?.earnedAt ?? eventTime
            : null,
      ),
    );
    await write(updated);
  }

  static String _normalizedText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[\s.,!?;:…_-]+"), ' ')
      .trim();

  static String _storageId(String value) => base64Url
      .encode(utf8.encode(value.trim().toLowerCase()))
      .replaceAll('=', '');

  static bool _isSameOrNearDuplicate(String left, String right) {
    final normalizedLeft = _normalizedText(left);
    final normalizedRight = _normalizedText(right);
    if (normalizedLeft == normalizedRight) return true;
    if (normalizedLeft.length < 8 || normalizedRight.length < 8) return false;
    final leftTokens = normalizedLeft.split(' ');
    final rightTokens = normalizedRight.split(' ');
    if ((leftTokens.length - rightTokens.length).abs() > 1) return false;
    final longest = normalizedLeft.length > normalizedRight.length
        ? normalizedLeft.length
        : normalizedRight.length;
    return 1 - (_editDistance(normalizedLeft, normalizedRight) / longest) >=
        0.92;
  }

  static int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex;
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex++) {
        final substitution =
            previous[rightIndex - 1] +
            (left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
                ? 0
                : 1);
        final deletion = previous[rightIndex] + 1;
        final insertion = current[rightIndex - 1] + 1;
        current[rightIndex] = <int>[
          substitution,
          deletion,
          insertion,
        ].reduce((a, b) => a < b ? a : b);
      }
      previous = current;
    }
    return previous.last;
  }

  static void _validateTranslation(
    VocabularyTranslation value, {
    int childAge = 5,
  }) {
    final english = value.englishText.trim();
    final vietnamese = value.vietnameseText.trim();
    if (english.isEmpty || vietnamese.isEmpty) {
      throw const VocabularyValidationException(
        'Nội dung cần có đủ tiếng Anh và nghĩa tiếng Việt.',
      );
    }
    if (english.length > 160 || vietnamese.length > 220) {
      throw const VocabularyValidationException(
        'Nội dung quá dài. Ba mẹ hãy chọn một câu ngắn hơn.',
      );
    }
    final maxEnglishWords = childAge <= 5
        ? 10
        : childAge <= 10
        ? 16
        : 24;
    if (english.split(RegExp(r'\s+')).length > maxEnglishWords) {
      throw const VocabularyValidationException(
        'Câu này hơi dài so với độ tuổi của con. Ba mẹ chọn câu ngắn hơn nhé.',
      );
    }
    final safeText = _normalizedText('$english $vietnamese');
    const blockedTerms = <String>{
      'fuck',
      'shit',
      'bitch',
      'địt',
      'đụ',
      'lồn',
      'cặc',
    };
    final tokens = safeText.split(' ').toSet();
    if (blockedTerms.any(tokens.contains)) {
      throw const VocabularyValidationException(
        'Nội dung này chưa phù hợp với trẻ em. Ba mẹ chọn nội dung khác nhé.',
      );
    }
  }

  static bool _isSameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _writeTodayView(VocabularyTodayView view) async {
    await (await SharedPreferences.getInstance()).setString(
      _todayViewKey,
      jsonEncode(view.toJson()),
    );
  }

  Future<void> _clearTodayView() async {
    await (await SharedPreferences.getInstance()).remove(_todayViewKey);
  }
}

class VocabularyValidationException implements Exception {
  const VocabularyValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VocabularyDuplicateException extends VocabularyValidationException {
  const VocabularyDuplicateException()
    : super('Câu này đã có. Bạn thêm câu mới nhé.');
}

class VocabularyTopicDuplicateException extends VocabularyValidationException {
  const VocabularyTopicDuplicateException()
    : super(
        'Nội dung này đã có trong phần Chủ đề. Bạn thêm nội dung khác nhé.',
      );
}

class VocabularyDailyLimitException extends VocabularyValidationException {
  const VocabularyDailyLimitException({required this.remaining})
    : super('Ba mẹ đã dùng hết số nội dung có thể thêm hôm nay.');

  final int remaining;
}

class VocabularyLockedException extends VocabularyValidationException {
  const VocabularyLockedException()
    : super('Nội dung đã được học nên không thể sửa hoặc xóa.');
}
