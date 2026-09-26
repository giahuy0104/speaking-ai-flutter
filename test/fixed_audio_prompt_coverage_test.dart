import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog preserves exact runtime punctuation for fixed VI prompts', () {
    final catalog =
        jsonDecode(File('tool/fixed_audio_prompts.json').readAsStringSync())
            as Map<String, dynamic>;
    final prompts = (catalog['prompts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final byKey = <String, Map<String, dynamic>>{
      for (final prompt in prompts) prompt['key'] as String: prompt,
    };

    final expected = <String, String>{
      LessonGuideFlowV2.lastItemComplete.audioKey!:
          LessonGuideFlowV2.lastItemComplete.text,
      'assistant.learning.challenge_controls.vi':
          MasterNavigationContract.challengeControlPrompt,
      'assistant.learning.song_controls.vi':
          MasterNavigationContract.songControlPrompt,
    };
    for (final item in expected.entries) {
      final prompt = byKey[item.key];
      expect(prompt, isNotNull, reason: item.key);
      expect(prompt!['pack'], 'assistant-core', reason: item.key);
      expect(prompt['locale'], 'vi-VN', reason: item.key);
      expect(prompt['language'], 'vi', reason: item.key);
      expect(prompt['text'], item.value, reason: item.key);
    }

    final generator = File(
      'tool/generate_missing_fixed_audio.ps1',
    ).readAsStringSync();
    expect(generator, contains("vi = '5CVDNcIPiOYgRUQuxXd7'"));
    expect(generator, contains('vi = 0.9'));
    expect(generator, contains("\$modelId = 'eleven_v3'"));
  });

  test('reviewed fixed prompt catalog is fully authored and verified', () {
    final catalog =
        jsonDecode(File('tool/fixed_audio_prompts.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(catalog['schemaVersion'], 1);
    expect(catalog['modelId'], 'eleven_v3');
    expect(catalog['outputFormat'], 'mp3_44100_128');

    const manifestPaths = <String, String>{
      'assistant-core': 'assets/data/assistant_core_audio.json',
      'listening-common': 'assets/data/listening_common_audio.json',
      'vocabulary-common': 'assets/data/vocabulary_common_audio.json',
    };
    final entriesByPack = <String, Map<String, Map<String, dynamic>>>{};
    for (final item in manifestPaths.entries) {
      final manifest =
          jsonDecode(File(item.value).readAsStringSync())
              as Map<String, dynamic>;
      expect(manifest['pack'], item.key);
      entriesByPack[item.key] = {
        for (final prompt in (manifest['prompts'] as List<dynamic>))
          '${prompt['key']}\u0000${prompt['locale']}':
              prompt as Map<String, dynamic>,
      };
    }

    final catalogPrompts = (catalog['prompts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(catalogPrompts, hasLength(115));
    for (final source in catalogPrompts) {
      final pack = source['pack'] as String;
      final key = source['key'] as String;
      final locale = source['locale'] as String;
      final language = source['language'] as String;
      final text = _normalize(source['text'] as String);
      final entry = entriesByPack[pack]?['$key\u0000$locale'];
      expect(entry, isNotNull, reason: '$pack: $key');
      expect(_normalize(entry!['text'] as String), text, reason: key);
      expect(entry['textHash'], _textHash(text), reason: key);
      expect(entry['modelId'], 'eleven_v3', reason: key);
      expect(
        entry['voiceId'],
        language == 'en' ? 'Nhs7eitvQWFTQBsf0yiT' : '5CVDNcIPiOYgRUQuxXd7',
        reason: key,
      );
      expect(
        (entry['speed'] as num).toDouble(),
        language == 'en' ? 0.75 : 0.9,
        reason: key,
      );

      final audio = File(entry['asset'] as String);
      expect(audio.existsSync(), isTrue, reason: key);
      final bytes = audio.readAsBytesSync();
      expect(bytes, isNotEmpty, reason: key);
      expect(bytes.length, entry['sizeBytes'], reason: key);
      expect(sha256.convert(bytes).toString(), entry['sha256'], reason: key);
    }
  });
}

String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _textHash(String value) =>
    sha256.convert(utf8.encode(_normalize(value))).toString();
