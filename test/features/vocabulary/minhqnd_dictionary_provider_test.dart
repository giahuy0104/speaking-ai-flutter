import 'dart:convert';

import 'package:ai_speaking_flutter_app/features/vocabulary/data/minhqnd_dictionary_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'parses the English result, Vietnamese meanings, IPA and audio',
    () async {
      late Uri requested;
      final provider = MinhqndDictionaryProvider(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode(<String, Object?>{
              'exists': true,
              'word': 'dog',
              'results': <Object?>[
                <String, Object?>{
                  'lang_code': 'en',
                  'audio': '/api/v1/tts?word=dog&lang=en',
                  'meanings': <Object?>[
                    <String, Object?>{
                      'definition': 'Chó.',
                      'definition_lang': 'vi',
                      'pos': 'Danh từ',
                      'source': 'Wiktionary',
                    },
                  ],
                  'pronunciations': <Object?>[
                    <String, Object?>{'ipa': '/dɑɡ/'},
                  ],
                },
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final result = await provider.lookupEnglish(' dog ');

      expect(requested.path, '/api/v1/lookup');
      expect(requested.queryParameters['word'], 'dog');
      expect(result?.english, 'dog');
      expect(result?.definitions.single.vietnamese, 'Chó.');
      expect(result?.definitions.single.partOfSpeech, 'Danh từ');
      expect(result?.ipa, '/dɑɡ/');
      expect(result?.audioUri.toString(), contains('word=dog'));
    },
  );

  test('returns null for a sentence missing from dictionary lookup', () async {
    final provider = MinhqndDictionaryProvider(
      client: MockClient((_) async => http.Response('{}', 404)),
    );

    expect(await provider.lookupEnglish('I like red apples.'), isNull);
  });

  test('builds encoded TTS URLs for English and Vietnamese sentences', () {
    final provider = MinhqndDictionaryProvider(
      client: MockClient((_) async {
        return http.Response('{}', 200);
      }),
    );

    final english = provider.ttsUri('I like red apples.', locale: 'en-US');
    final vietnamese = provider.ttsUri('Con thích táo đỏ.', locale: 'vi-VN');

    expect(english.queryParameters, <String, String>{
      'word': 'I like red apples.',
      'lang': 'en',
    });
    expect(vietnamese.queryParameters['lang'], 'vi');
  });
}
