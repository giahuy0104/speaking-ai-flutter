import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks the exact V3 child-facing menu and completion copy', () {
    expect(
      VocabularyFlowV3.todayEmptyMenu,
      'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?',
    );
    expect(
      VocabularyFlowV3.todayCompletion,
      'Bạn muốn học nội dung khác hay học lại?',
    );
    expect(
      VocabularyFlowV3.parentGroupCompletion,
      'Bạn muốn học nội dung khác hay học tiếp?',
    );
    expect(
      VocabularyFlowV3.reviewGroupCompletion,
      'Bạn muốn học nội dung khác hay học tiếp?',
    );
    expect(
      VocabularyFlowV3.starGroupCompletion,
      'Bạn muốn học nội dung khác hay học tiếp?',
    );
  });

  test('registers the 23 FINAL fixed prompt state IDs once', () {
    final stateIds = VocabularyFlowV3.fixedPrompts
        .map((prompt) => prompt.stateId)
        .toList(growable: false);

    expect(stateIds, hasLength(23));
    expect(stateIds.toSet(), hasLength(23));
    expect(
      stateIds,
      containsAll(<String>[
        'VOCAB_MENU_01',
        'TODAY_INTRO_01',
        'TODAY_RESUME_01',
        'TODAY_BLOCK_END_01',
        'PARENT_LIST_SHORT_01',
        'PARENT_RESUME',
        'PARENT_LIST_BLOCK_END_01',
        'PARENT_LIST_OTHER_MENU_01',
        'PARENT_LIST_END_01',
        'PARENT_LIST_EMPTY_01',
        'STAR_INTRO_01',
        'STAR_INTRO_0_01',
        'STAR_MY_VOICE_01',
        'STAR_RESUME_ALL_01',
        'STAR_BLOCK_END_01',
        'STAR_OTHER_MENU_01',
        'STAR_END_01',
        'REVIEW_INTRO_01',
        'REVIEW_RESUME_01',
        'REVIEW_BLOCK_END_01',
        'REVIEW_OTHER_MENU_01',
        'REVIEW_PASS_END_01',
        'REVIEW_EMPTY_01',
      ]),
    );
    final sharedBlock = VocabularyFlowV3.fixedPromptForText(
      VocabularyFlowV3.reviewGroupCompletion,
    );
    expect(sharedBlock?.lookupCodes, contains('REVIEW_BLOCK_END_01'));
  });

  test('Parent Added and Stars always play oldest first', () {
    final entries = <VocabularyEntry>[
      _entry('middle', DateTime(2026, 9, 2)),
      _entry('oldest', DateTime(2026, 9, 1)),
      _entry('newest', DateTime(2026, 9, 3)),
    ];

    final ordered = VocabularyFlowV3.orderedForPlayback(
      entries,
      journey: VocabularyJourneyKind.stars,
    );

    expect(ordered.map((entry) => entry.id), <String>[
      'oldest',
      'middle',
      'newest',
    ]);
  });

  test('completed checkpoints resume at new items or reset to oldest', () {
    expect(VocabularyFlowV3.playbackStartIndex(checkpoint: 5, total: 7), 5);
    expect(VocabularyFlowV3.playbackStartIndex(checkpoint: 5, total: 5), 0);
    expect(VocabularyFlowV3.playbackBlockEnd(start: 5, total: 12), 10);
  });

  test(
    'Alphabet accepts the keyword alone but parent content is unchanged',
    () {
      final alphabet = VocabularyEntry(
        id: 'alphabet',
        word: 'A. Apple.',
        meaning: 'A. Quả táo.',
        addedAt: DateTime(2026, 9, 10),
        source: VocabularySource.topicCore,
      );
      final parent = VocabularyEntry(
        id: 'parent',
        word: 'A. Apple.',
        meaning: 'A. Quả táo.',
        addedAt: DateTime(2026, 9, 10),
      );

      expect(VocabularyFlowV3.acceptedVariantsFor(alphabet), <String>[
        'Apple.',
      ]);
      expect(VocabularyFlowV3.acceptedVariantsFor(parent), isEmpty);
    },
  );
}

VocabularyEntry _entry(String id, DateTime earnedAt) => VocabularyEntry(
  id: id,
  word: id,
  meaning: id,
  addedAt: earnedAt.subtract(const Duration(days: 10)),
  collection: VocabularyCollection.star,
  source: VocabularySource.topicCore,
  earnedAt: earnedAt,
  correctAudioPath: '/audio/$id.wav',
);
