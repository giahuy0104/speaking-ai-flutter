import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vocabulary packs contain verified Eleven v3 audio', () async {
    final common = _readManifest('assets/data/vocabulary_common_audio.json');
    final builtIn = _readManifest('assets/data/vocabulary_built_in_audio.json');

    expect(common['pack'], 'vocabulary-common');
    expect(builtIn['pack'], 'vocabulary-built-in');
    final commonPrompts = (common['prompts'] as List)
        .cast<Map<String, dynamic>>();
    final builtInPrompts = (builtIn['prompts'] as List)
        .cast<Map<String, dynamic>>();
    expect(commonPrompts, hasLength(30));
    expect(builtInPrompts, hasLength(1130));
    expect(commonPrompts.map((entry) => entry['asset']).toSet(), hasLength(26));

    for (final prompt in [...commonPrompts, ...builtInPrompts]) {
      final file = File(prompt['asset'] as String);
      expect(file.existsSync(), isTrue, reason: '${prompt['key']}');
      final bytes = await file.readAsBytes();
      expect(
        sha256.convert(bytes).toString(),
        prompt['sha256'],
        reason: '${prompt['key']}',
      );
      expect(bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(
        (prompt['durationSeconds'] as num).toDouble(),
        inExclusiveRange(0, 45),
      );
      expect(prompt['modelId'], 'eleven_v3');
      if ((prompt['locale'] as String).startsWith('en')) {
        expect(prompt['voiceId'], 'Nhs7eitvQWFTQBsf0yiT');
        expect(prompt['speed'], 0.75);
      } else {
        expect(prompt['voiceId'], '5CVDNcIPiOYgRUQuxXd7');
        expect(prompt['speed'], 0.9);
      }
    }
  });

  test('every built-in sentence has word and meaning Registry keys', () {
    final lessons = _readManifest('assets/data/listening_lessons.json');
    final manifest = _readManifest(
      'assets/data/vocabulary_built_in_audio.json',
    );
    final keys = (manifest['prompts'] as List)
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['key'])
        .toSet();
    var sentenceCount = 0;
    for (final group
        in (lessons['groups'] as List).cast<Map<String, dynamic>>()) {
      for (final topic
          in (group['topics'] as List).cast<Map<String, dynamic>>()) {
        for (final lesson
            in (topic['lessons'] as List).cast<Map<String, dynamic>>()) {
          for (final sentence
              in (lesson['sentences'] as List).cast<Map<String, dynamic>>()) {
            sentenceCount += 1;
            final id = sentence['id'];
            expect(keys, contains('vocabulary.entry.$id.word.en'));
            expect(keys, contains('vocabulary.entry.$id.meaning.vi'));
          }
        }
      }
    }
    expect(sentenceCount, 565);
  });
}

Map<String, dynamic> _readManifest(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
