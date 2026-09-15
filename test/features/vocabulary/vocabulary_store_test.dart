import 'dart:convert';

import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('starts empty so parents provide the Family vocabulary', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final entries = await const VocabularyStore().read();

    expect(entries, isEmpty);
  });

  test(
    'removes the three legacy starter words from existing installs',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[
          for (final item in <(String, String, String)>[
            ('family', 'Family', 'Gia đình'),
            ('school', 'School', 'Trường học'),
            ('happy', 'Happy', 'Vui vẻ'),
            ('parent-word', 'Apple', 'Quả táo'),
          ])
            <String, Object>{
              'id': item.$1,
              'word': item.$2,
              'meaning': item.$3,
              'addedAt': DateTime(2026, 8, 18).toIso8601String(),
              'collection': VocabularyCollection.saved.name,
            },
        ]),
      });

      final store = const VocabularyStore();
      final entries = await store.read();

      expect(entries.map((entry) => entry.id), <String>['parent-word']);
      expect((await store.read()).map((entry) => entry.id), <String>[
        'parent-word',
      ]);
    },
  );

  test(
    'moves one lesson sentence from Review to Stars without duplication',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[]),
      });
      const store = VocabularyStore();

      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: "I'm An",
        vietnamese: 'Con là An',
        collection: VocabularyCollection.review,
      );
      var entries = await store.read();
      expect(entries, hasLength(1));
      expect(entries.single.collection, VocabularyCollection.review);

      await store.upsertLessonSentence(
        lessonCode: 'A035_T01_L01',
        sentenceId: 'S1',
        english: "I'm An",
        vietnamese: 'Con là An',
        collection: VocabularyCollection.star,
      );
      entries = await store.read();

      expect(entries, hasLength(1));
      expect(entries.single.collection, VocabularyCollection.star);
      expect(entries.single.word, "I'm An");
      expect(entries.single.meaning, 'Con là An');
    },
  );

  test('loads legacy vocabulary entries into the Saved collection', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[
        <String, Object>{
          'id': 'legacy',
          'word': 'Family',
          'meaning': 'Gia đình',
          'addedAt': DateTime(2026, 8, 14).toIso8601String(),
        },
      ]),
    });

    final entries = await const VocabularyStore().read();

    expect(entries.single.collection, VocabularyCollection.saved);
  });

  test('migrates an introduced legacy parent entry as learned well', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[
        <String, Object>{
          'id': 'legacy-learned',
          'word': 'Apple',
          'meaning': 'Quả táo',
          'addedAt': DateTime(2026, 8, 14).toIso8601String(),
          'introducedAt': DateTime(2026, 8, 15).toIso8601String(),
        },
      ]),
    });

    final entry = (await const VocabularyStore().read()).single;

    expect(entry.status, VocabularyLearningStatus.learnedWell);
    expect(entry.isParentAdded, isTrue);
    expect(entry.parentState, ParentVocabularyState.unlocked);
  });

  test('migrates legacy parent data in place to the FINAL schema', () async {
    final addedAt = DateTime(2026, 8, 14);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[
        <String, Object>{
          'id': 'legacy-sentence',
          'word': 'I like red apples.',
          'meaning': 'Con thích những quả táo đỏ.',
          'addedAt': addedAt.toIso8601String(),
        },
      ]),
    });

    const store = VocabularyStore();
    final entry = (await store.read()).single;

    expect(entry.contentKind, VocabularyContentKind.sentence);
    expect(entry.parentState, ParentVocabularyState.waiting);
    expect(entry.todayStatus, isNull);
    expect(entry.canParentEdit, isTrue);

    final preferences = await SharedPreferences.getInstance();
    final persisted =
        jsonDecode(preferences.getString('innotrik.vocabulary.v1')!)
            as List<Object?>;
    final migrated = persisted.single as Map<String, Object?>;
    expect(migrated['schemaVersion'], 4);
    expect(migrated['contentKind'], 'sentence');
    expect(migrated['parentState'], 'waiting');
  });

  test(
    'new parent selections share a batch id and infer content kind',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();

      final entries = await store.addParentEntries(
        const <VocabularyTranslation>[
          VocabularyTranslation(englishText: 'Mad', vietnameseText: 'Tức giận'),
          VocabularyTranslation(
            englishText: 'I am mad.',
            vietnameseText: 'Con đang tức giận.',
          ),
        ],
        now: DateTime(2026, 9, 14, 9),
      );
      final parent = entries.where((entry) => entry.isParentAdded).toList();

      expect(parent.map((entry) => entry.parentState).toSet(), {
        ParentVocabularyState.waiting,
      });
      expect(parent.map((entry) => entry.originBatchId).toSet(), hasLength(1));
      expect(
        parent.map((entry) => entry.contentKind),
        containsAll(<Object>[
          VocabularyContentKind.word,
          VocabularyContentKind.sentence,
        ]),
      );
    },
  );

  test(
    'marks parent vocabulary as introduced and persists the state',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'innotrik.vocabulary.v1': jsonEncode(<Object>[
          <String, Object>{
            'id': 'parent-apple',
            'word': 'Apple',
            'meaning': 'Quả táo',
            'addedAt': DateTime(2026, 8, 18).toIso8601String(),
            'collection': VocabularyCollection.saved.name,
          },
        ]),
      });
      const store = VocabularyStore();

      await store.markIntroduced(const <String>['parent-apple']);
      final entry = (await store.read()).single;

      expect(entry.introducedAt, isNotNull);
      expect(entry.word, 'Apple');
      expect(entry.collection, VocabularyCollection.saved);
    },
  );

  test(
    'suggestions are capped at three and unsafe content is rejected',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = VocabularyStore();
      final options = await store
          .filterParentSuggestions(const <VocabularyTranslation>[
            VocabularyTranslation(englishText: 'One', vietnameseText: 'Một'),
            VocabularyTranslation(englishText: 'Two', vietnameseText: 'Hai'),
            VocabularyTranslation(englishText: 'Three', vietnameseText: 'Ba'),
            VocabularyTranslation(englishText: 'Four', vietnameseText: 'Bốn'),
          ]);

      expect(options, hasLength(3));
      await expectLater(
        store.validateParentCandidate(
          const VocabularyTranslation(
            englishText: 'A shit word',
            vietnameseText: 'Nội dung xấu',
          ),
        ),
        throwsA(isA<VocabularyValidationException>()),
      );
    },
  );
}
