import 'package:ai_speaking_flutter_app/features/vocabulary/application/local_vocabulary_suggestion_provider.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = LocalVocabularySuggestionProvider();

  test('creates adjective sentences locally without an AI provider', () {
    final suggestions = provider.suggest(
      base: const VocabularyTranslation(
        englishText: 'Mad',
        vietnameseText: 'Tức giận',
      ),
      partOfSpeech: 'Tính từ',
    );

    expect(suggestions.map((item) => item.englishText), <String>[
      'I am mad.',
      'I feel very mad.',
      'I know the word “mad”.',
    ]);
    expect(suggestions.first.vietnameseText, 'Con tức giận.');
  });

  test('creates safe local alternatives for an arbitrary short sentence', () {
    final suggestions = provider.suggest(
      base: const VocabularyTranslation(
        englishText: 'I missed the bus',
        vietnameseText: 'Con bị lỡ xe buýt',
      ),
      partOfSpeech: 'Tính từ',
    );

    expect(suggestions.map((item) => item.englishText), <String>[
      'I can say: “I missed the bus”.',
      'Let’s say: “I missed the bus”.',
      'Practice: “I missed the bus”.',
    ]);
    expect(suggestions.first.vietnameseText, contains('Con bị lỡ xe buýt'));
  });

  test('creates three deterministic alternatives for a phrase', () {
    final suggestions = provider.suggest(
      base: const VocabularyTranslation(
        englishText: 'at school',
        vietnameseText: 'ở trường',
      ),
    );

    expect(suggestions, hasLength(3));
    expect(
      suggestions.every((item) => item.englishText.contains('at school')),
      isTrue,
    );
  });
}
