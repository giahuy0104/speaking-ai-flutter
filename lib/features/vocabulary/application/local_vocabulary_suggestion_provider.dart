import '../domain/vocabulary_entry.dart';

/// Creates a small set of deterministic, child-friendly sentence options.
///
/// This provider is intentionally local: it does not call an AI model or a
/// network endpoint. Authored curriculum suggestions should be tried first.
class LocalVocabularySuggestionProvider {
  const LocalVocabularySuggestionProvider();

  List<VocabularyTranslation> suggest({
    required VocabularyTranslation base,
    String? partOfSpeech,
  }) {
    final english = _plainWord(base.englishText);
    final vietnamese = _plainMeaning(base.vietnameseText);
    if (vietnamese.isEmpty || base.englishText.trim().isEmpty) {
      return const <VocabularyTranslation>[];
    }

    final normalizedPart = _normalizedPartOfSpeech(partOfSpeech);
    if (english != null && _isAdjective(normalizedPart)) {
      if (_colorWords.contains(english.toLowerCase())) {
        return <VocabularyTranslation>[
          VocabularyTranslation(
            englishText: 'It is $english.',
            vietnameseText: 'Nó có màu $vietnamese.',
          ),
          VocabularyTranslation(
            englishText: 'I like the $english color.',
            vietnameseText: 'Con thích màu $vietnamese.',
          ),
        ];
      }
      return <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'I am $english.',
          vietnameseText: 'Con $vietnamese.',
        ),
        VocabularyTranslation(
          englishText: 'I feel very $english.',
          vietnameseText: 'Con cảm thấy rất $vietnamese.',
        ),
      ];
    }
    if (english != null && _isVerb(normalizedPart)) {
      return <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'I can $english.',
          vietnameseText: 'Con có thể $vietnamese.',
        ),
        VocabularyTranslation(
          englishText: 'I like to $english.',
          vietnameseText: 'Con thích $vietnamese.',
        ),
      ];
    }
    if (english != null && _isNoun(normalizedPart)) {
      return <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'This is my $english.',
          vietnameseText: 'Đây là $vietnamese của con.',
        ),
        VocabularyTranslation(
          englishText: 'I like this $english.',
          vietnameseText: 'Con thích $vietnamese này.',
        ),
      ];
    }
    final quotedEnglish = _quoteContent(base.englishText);
    final quotedVietnamese = _quoteContent(base.vietnameseText);
    return <VocabularyTranslation>[
      VocabularyTranslation(
        englishText: 'I can say: “$quotedEnglish”.',
        vietnameseText: 'Con có thể nói: “$quotedVietnamese”.',
      ),
      VocabularyTranslation(
        englishText: 'Let’s say: “$quotedEnglish”.',
        vietnameseText: 'Mình cùng nói: “$quotedVietnamese” nhé.',
      ),
    ];
  }

  String _quoteContent(String value) =>
      value.trim().replaceAll(RegExp(r'[.!?]+$'), '');

  String? _plainWord(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[.!?]+$'), '');
    if (!RegExp(r"^[A-Za-z]+(?:[-'][A-Za-z]+)?$").hasMatch(normalized)) {
      return null;
    }
    return normalized.toLowerCase();
  }

  String _plainMeaning(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[.!?]+$'), '');
    if (normalized.isEmpty) return '';
    return '${normalized[0].toLowerCase()}${normalized.substring(1)}';
  }

  String _normalizedPartOfSpeech(String? value) =>
      (value ?? '').trim().toLowerCase();

  bool _isNoun(String value) =>
      value.contains('danh từ') || value == 'noun' || value == 'n';

  bool _isVerb(String value) =>
      value.contains('động từ') || value == 'verb' || value == 'v';

  bool _isAdjective(String value) =>
      value.contains('tính từ') || value == 'adjective' || value == 'adj';

  static const Set<String> _colorWords = <String>{
    'black',
    'blue',
    'brown',
    'green',
    'orange',
    'pink',
    'purple',
    'red',
    'white',
    'yellow',
  };
}
