class VocabularyDictionaryDefinition {
  const VocabularyDictionaryDefinition({
    required this.vietnamese,
    this.partOfSpeech,
    this.example,
    this.source,
  });

  final String vietnamese;
  final String? partOfSpeech;
  final String? example;
  final String? source;
}

class VocabularyDictionaryResult {
  const VocabularyDictionaryResult({
    required this.english,
    required this.definitions,
    this.ipa,
    this.audioUri,
  });

  final String english;
  final List<VocabularyDictionaryDefinition> definitions;
  final String? ipa;
  final Uri? audioUri;
}

abstract interface class VocabularyDictionaryProvider {
  /// Returns null when the text is not a dictionary headword/phrase.  A
  /// sentence can still be spoken through [ttsUri].
  Future<VocabularyDictionaryResult?> lookupEnglish(String text);

  Uri ttsUri(String text, {required String locale});

  void dispose();
}

class VocabularyDictionaryUnavailable implements Exception {
  const VocabularyDictionaryUnavailable([
    this.message = 'Dictionary unavailable',
  ]);

  final String message;

  @override
  String toString() => message;
}
