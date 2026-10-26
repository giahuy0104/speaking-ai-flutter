import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/vocabulary_dictionary.dart';

class MinhqndDictionaryProvider implements VocabularyDictionaryProvider {
  MinhqndDictionaryProvider({
    http.Client? client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 3),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       baseUri = baseUri ?? Uri.parse('https://dict.minhqnd.com');

  final http.Client _client;
  final bool _ownsClient;
  final Uri baseUri;
  final Duration timeout;

  @override
  Future<VocabularyDictionaryResult?> lookupEnglish(String text) async {
    final query = text.trim();
    if (query.isEmpty) return null;
    final uri = baseUri.replace(
      path: '/api/v1/lookup',
      queryParameters: <String, String>{'word': query},
    );
    http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (error) {
      throw VocabularyDictionaryUnavailable(error.toString());
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VocabularyDictionaryUnavailable(
        'Dictionary returned HTTP ${response.statusCode}',
      );
    }

    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, Object?> || body['exists'] != true) return null;
      final results = (body['results'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<String, Object?>>();
      final englishResult = results
          .where((item) => item['lang_code'] == 'en')
          .firstOrNull;
      if (englishResult == null) return null;
      final definitions =
          (englishResult['meanings'] as List<Object?>? ?? const <Object?>[])
              .whereType<Map<String, Object?>>()
              .where((item) => item['definition_lang'] == 'vi')
              .map(
                (item) => VocabularyDictionaryDefinition(
                  vietnamese: (item['definition'] as String? ?? '').trim(),
                  partOfSpeech: (item['pos'] as String?)?.trim(),
                  example: (item['example'] as String?)?.trim(),
                  source: (item['source'] as String?)?.trim(),
                ),
              )
              .where((item) => item.vietnamese.isNotEmpty)
              .toList(growable: false);
      final pronunciations =
          (englishResult['pronunciations'] as List<Object?>? ??
                  const <Object?>[])
              .whereType<Map<String, Object?>>();
      final ipa = pronunciations
          .map((item) => (item['ipa'] as String? ?? '').trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull;
      final audioPath = (englishResult['audio'] as String?)?.trim();
      return VocabularyDictionaryResult(
        english: (body['word'] as String? ?? query).trim(),
        definitions: definitions,
        ipa: ipa,
        audioUri: audioPath == null || audioPath.isEmpty
            ? null
            : baseUri.resolve(audioPath),
      );
    } catch (error) {
      if (error is VocabularyDictionaryUnavailable) rethrow;
      throw VocabularyDictionaryUnavailable(
        'Dictionary response was invalid: $error',
      );
    }
  }

  @override
  Uri ttsUri(String text, {required String locale}) => baseUri.replace(
    path: '/api/v1/tts',
    queryParameters: <String, String>{
      'word': text.trim(),
      'lang': locale.toLowerCase().startsWith('vi') ? 'vi' : 'en',
    },
  );

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}
