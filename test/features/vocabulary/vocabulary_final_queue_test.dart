import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('TODAY_VIEW is fixed at the five oldest waiting entries', () async {
    const store = VocabularyStore();
    const sessions = VocabularySessionStore();
    final base = DateTime(2026, 9, 1);
    await store.write(<VocabularyEntry>[
      for (var index = 5; index >= 0; index--)
        VocabularyEntry(
          id: 'parent-$index',
          word: 'Word $index',
          meaning: 'Nghĩa $index',
          addedAt: base.add(Duration(days: index)),
        ),
    ]);

    final first = await sessions.prepareToday(
      store,
      now: DateTime(2026, 9, 14, 8),
    );
    final resumed = await sessions.prepareToday(
      store,
      now: DateTime(2026, 9, 14, 18),
      forceNextGroup: true,
    );

    expect(first?.entryIds, <String>[
      'parent-0',
      'parent-1',
      'parent-2',
      'parent-3',
      'parent-4',
    ]);
    expect(resumed?.entryIds, first?.entryIds);
    expect(
      (await store.read())
          .singleWhere((e) => e.id == 'parent-5')
          .isWaitingParent,
      isTrue,
    );

    for (final id in first!.entryIds) {
      await store.markTodayHeard(id, now: DateTime(2026, 9, 14, 19));
    }
    await sessions.clearActive();
    final replay = await sessions.prepareTodayReplay(
      store,
      now: DateTime(2026, 9, 14, 20),
    );
    expect(replay?.entryIds, first.entryIds);
    expect(replay?.currentIndex, 0);
  });

  test('an origin batch unlocks only after every item is HEARD', () async {
    const store = VocabularyStore();
    final now = DateTime(2026, 9, 14, 9);
    await store.addParentEntries(const <VocabularyTranslation>[
      VocabularyTranslation(englishText: 'Mad', vietnameseText: 'Tức giận'),
      VocabularyTranslation(
        englishText: 'I am mad.',
        vietnameseText: 'Con đang tức giận.',
      ),
    ], now: now);
    final view = await store.prepareTodayView(now: now);

    final firstUnlocked = await store.markTodayHeard(
      view!.entryIds.first,
      now: now,
    );
    var batch = await store.read();
    expect(firstUnlocked, isFalse);
    expect(batch.where((entry) => entry.isUnlockedParent), isEmpty);

    final secondUnlocked = await store.markTodayHeard(
      view.entryIds.last,
      now: now,
    );
    batch = await store.read();
    expect(secondUnlocked, isTrue);
    expect(batch.every((entry) => entry.isUnlockedParent), isTrue);
    expect(
      batch.every((entry) => entry.todayStatus == TodayVocabularyStatus.heard),
      isTrue,
    );
  });

  test(
    'a new day carries unheard items first and fills remaining slots',
    () async {
      const store = VocabularyStore();
      final firstDay = DateTime(2026, 9, 13, 8);
      await store.write(<VocabularyEntry>[
        for (var index = 0; index < 7; index += 1)
          VocabularyEntry(
            id: 'parent-$index',
            word: 'Word $index',
            meaning: 'Nghĩa $index',
            addedAt: firstDay.add(Duration(minutes: index)),
            source: VocabularySource.parent,
            parentState: ParentVocabularyState.waiting,
          ),
      ]);
      final oldView = await store.prepareTodayView(now: firstDay);
      await store.markTodayHeard(oldView!.entryIds[0], now: firstDay);
      await store.markTodayHeard(oldView.entryIds[1], now: firstDay);

      final nextDay = await store.prepareTodayView(
        now: firstDay.add(const Duration(days: 1)),
      );

      expect(nextDay?.entryIds, <String>[
        'parent-2',
        'parent-3',
        'parent-4',
        'parent-5',
        'parent-6',
      ]);
      final hiddenHeard = (await store.read()).where(
        (entry) => entry.id == 'parent-0' || entry.id == 'parent-1',
      );
      expect(hiddenHeard.every((entry) => entry.isWaitingParent), isTrue);
      expect(
        hiddenHeard.every(
          (entry) => entry.todayStatus == TodayVocabularyStatus.heard,
        ),
        isTrue,
      );
    },
  );

  test('Stars contain only Topic Core entries in oldest-first order', () async {
    const store = VocabularyStore();
    final base = DateTime(2026, 9, 1);
    await store.write(<VocabularyEntry>[
      VocabularyEntry(
        id: 'core-new',
        word: 'Core new',
        meaning: 'Core mới',
        addedAt: base,
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        earnedAt: base.add(const Duration(days: 2)),
        correctAudioPath: '/audio/core-new.wav',
      ),
      VocabularyEntry(
        id: 'role-play',
        word: 'Role play',
        meaning: 'Đóng vai',
        addedAt: base,
        collection: VocabularyCollection.star,
        source: VocabularySource.topicRolePlay,
        earnedAt: base,
        correctAudioPath: '/audio/role-play.wav',
      ),
      VocabularyEntry(
        id: 'core-old',
        word: 'Core old',
        meaning: 'Core cũ',
        addedAt: base,
        collection: VocabularyCollection.star,
        source: VocabularySource.topicCore,
        earnedAt: base.add(const Duration(days: 1)),
        correctAudioPath: '/audio/core-old.wav',
      ),
    ]);

    expect((await store.starEntries()).map((entry) => entry.id), <String>[
      'core-old',
      'core-new',
    ]);
  });

  test(
    'Review contains Topic targets only, never parent-added content',
    () async {
      const store = VocabularyStore();
      final now = DateTime(2026, 9, 14);
      await store.write(<VocabularyEntry>[
        VocabularyEntry(
          id: 'parent-review',
          word: 'Mad',
          meaning: 'Tức giận',
          addedAt: now,
          collection: VocabularyCollection.review,
          status: VocabularyLearningStatus.needsPractice,
          source: VocabularySource.parent,
          parentState: ParentVocabularyState.unlocked,
        ),
        VocabularyEntry(
          id: 'topic-review',
          word: 'Open your book',
          meaning: 'Mở sách ra',
          addedAt: now.add(const Duration(minutes: 1)),
          collection: VocabularyCollection.review,
          status: VocabularyLearningStatus.needsPractice,
          source: VocabularySource.topicCore,
        ),
      ]);

      expect((await store.reviewEntries()).map((entry) => entry.id), <String>[
        'topic-review',
      ]);
    },
  );

  test(
    'Review snapshot excludes new targets and does not repeat failures in one session',
    () async {
      const store = VocabularyStore();
      const sessions = VocabularySessionStore();
      final base = DateTime(2026, 9, 1);
      await store.write(<VocabularyEntry>[
        for (var index = 0; index < 7; index += 1)
          VocabularyEntry(
            id: 'review-$index',
            word: 'Sentence $index',
            meaning: 'Câu $index',
            addedAt: base.add(Duration(minutes: index)),
            collection: VocabularyCollection.review,
            status: VocabularyLearningStatus.needsPractice,
            source: VocabularySource.topicCore,
          ),
      ]);

      final first = await sessions.prepareReview(store, now: base);
      expect(first?.entryIds, <String>[
        'review-0',
        'review-1',
        'review-2',
        'review-3',
        'review-4',
      ]);

      await store.upsertLessonSentence(
        lessonCode: 'L02',
        sentenceId: 'new-after-snapshot',
        english: 'A new target',
        vietnamese: 'Một câu mới',
        collection: VocabularyCollection.review,
        source: VocabularySource.topicCore,
        occurredAt: base.add(const Duration(hours: 1)),
      );
      await store.commitPracticeResults(
        results: <String, bool>{
          'review-0': true,
          'review-1': true,
          'review-2': true,
          'review-3': true,
          'review-4': false,
        },
      );
      await sessions.completeReviewBlock(first!.entryIds);

      final second = await sessions.prepareReview(store, forceNextGroup: true);
      expect(second?.entryIds, <String>['review-5', 'review-6']);
      expect(second?.entryIds, isNot(contains('review-4')));
      expect(
        second?.entryIds,
        isNot(contains('lesson:L02:new-after-snapshot')),
      );

      await store.commitPracticeResults(
        results: <String, bool>{'review-5': true, 'review-6': true},
      );
      await sessions.completeReviewBlock(second!.entryIds);
      expect(await sessions.prepareReview(store, forceNextGroup: true), isNull);

      final nextSession = await sessions.prepareReview(store);
      expect(nextSession?.entryIds.first, 'review-4');
      expect(nextSession?.entryIds, contains('lesson:L02:new-after-snapshot'));
    },
  );
}
