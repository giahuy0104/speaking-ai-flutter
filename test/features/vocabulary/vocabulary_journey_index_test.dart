import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_journey_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('precomputes stable sorted collections without changing flow rules', () {
    final entries = <VocabularyEntry>[
      _entry(
        id: 'star-new',
        word: 'New',
        source: VocabularySource.topicCore,
        collection: VocabularyCollection.star,
        correctAudioPath: 'new.m4a',
        addedDay: 3,
      ),
      _entry(
        id: 'family-old',
        word: 'Family old',
        parentState: ParentVocabularyState.unlocked,
        addedDay: 1,
      ),
      _entry(
        id: 'family-new',
        word: 'Family new',
        parentState: ParentVocabularyState.unlocked,
        addedDay: 2,
      ),
      _entry(
        id: 'star-old',
        word: 'Old',
        source: VocabularySource.topicCore,
        collection: VocabularyCollection.star,
        correctAudioPath: 'old.m4a',
        addedDay: 1,
      ),
      _entry(
        id: 'review-duplicate-new',
        word: '  HELLO! ',
        source: VocabularySource.topicMission,
        status: VocabularyLearningStatus.needsPractice,
        addedDay: 4,
      ),
      _entry(
        id: 'review-duplicate-old',
        word: 'hello',
        source: VocabularySource.topicCore,
        status: VocabularyLearningStatus.needsPractice,
        addedDay: 2,
      ),
      _entry(
        id: 'review-other',
        word: 'World',
        source: VocabularySource.topicCore,
        status: VocabularyLearningStatus.needsPractice,
        addedDay: 3,
      ),
      _entry(
        id: 'legacy-review',
        word: 'Legacy',
        source: VocabularySource.topicCore,
        status: VocabularyLearningStatus.needsPractice,
        sourceLessonCode: 'LEGACY-V41:C35-L1-T01-B1',
        addedDay: 1,
      ),
    ];

    final index = VocabularyJourneyIndex.fromEntries(entries);

    expect(index.family.map((entry) => entry.id), <String>[
      'family-old',
      'family-new',
    ]);
    expect(index.stars.map((entry) => entry.id), <String>[
      'star-old',
      'star-new',
    ]);
    expect(index.review.map((entry) => entry.id), <String>[
      'review-other',
      'review-duplicate-new',
    ]);

    // Rebuilds consume the exact precomputed immutable lists.
    expect(identical(index.family, index.family), isTrue);
    expect(() => index.review.clear(), throwsUnsupportedError);
  });
}

VocabularyEntry _entry({
  required String id,
  required String word,
  required int addedDay,
  VocabularySource source = VocabularySource.parent,
  VocabularyCollection collection = VocabularyCollection.saved,
  VocabularyLearningStatus status = VocabularyLearningStatus.unlearned,
  ParentVocabularyState? parentState,
  String? correctAudioPath,
  String? sourceLessonCode,
}) {
  return VocabularyEntry(
    id: id,
    word: word,
    meaning: '$word meaning',
    addedAt: DateTime.utc(2026, 1, addedDay),
    source: source,
    collection: collection,
    status: status,
    parentState: parentState,
    correctAudioPath: correctAudioPath,
    sourceLessonCode: sourceLessonCode,
  );
}
