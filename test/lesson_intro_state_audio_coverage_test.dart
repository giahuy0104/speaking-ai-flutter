import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every V4 topic and lesson opening state has authored audio', () {
    final catalog =
        jsonDecode(
              File('assets/data/listening_lessons.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final manifest =
        jsonDecode(
              File(
                'assets/data/listening_common_audio.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final entries = <String, Map<String, dynamic>>{
      for (final prompt in (manifest['prompts'] as List<dynamic>))
        (prompt as Map<String, dynamic>)['key'] as String: prompt,
    };
    var lessonCount = 0;
    var songCount = 0;
    var maximumStars = 0;
    final topicNumbers = <int>{};

    for (final group in (catalog['groups'] as List<dynamic>)) {
      for (final topic
          in ((group as Map<String, dynamic>)['topics'] as List<dynamic>)) {
        final topicNumber = (topic as Map<String, dynamic>)['number'] as int;
        if (topicNumbers.add(topicNumber)) {
          _expectVerified(
            entries,
            'listening.topic.$topicNumber.resume.vi',
            'Mình học tiếp Chủ đề $topicNumber nhé.',
          );
        }
        for (final lesson in (topic['lessons'] as List<dynamic>)) {
          final item = lesson as Map<String, dynamic>;
          final id = item['id'] as String;
          final title = _normalize(
            (item['titleEn'] as String?)?.trim().isNotEmpty == true
                ? item['titleEn'] as String
                : item['titleVi'] as String,
          );
          lessonCount += 1;
          final sentenceCount = (item['sentences'] as List<dynamic>).length;
          if (sentenceCount > maximumStars) maximumStars = sentenceCount;
          _expectVerified(
            entries,
            'listening.lesson.$id.resume.vi',
            'Mình học tiếp bài $title nhé.',
          );
          _expectVerified(
            entries,
            'listening.lesson.$id.relearn.vi',
            'Mình học lại bài $title nhé.',
          );
          final songTitle = _normalize(item['songTitle'] as String? ?? '');
          if (songTitle.isNotEmpty) {
            songCount += 1;
            _expectVerified(
              entries,
              'listening.lesson.$id.song_resume.vi',
              'Mình nghe lại bài hát $songTitle nhé.',
            );
          }
        }
      }
    }

    for (var remaining = 1; remaining <= maximumStars; remaining += 1) {
      _expectVerified(
        entries,
        'listening.lesson.remaining_stars.$remaining.young.vi',
        'Bài này bạn còn $remaining Ngôi sao chưa chinh phục. '
            'Mình cùng thử nhé!',
      );
      _expectVerified(
        entries,
        'listening.lesson.remaining_stars.$remaining.older.vi',
        'Bài này bạn còn $remaining Ngôi sao chưa chinh phục.',
      );
    }

    expect(lessonCount, 109);
    expect(songCount, 5);
    expect(maximumStars, 6);
    expect(topicNumbers, <int>{1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
  });
}

void _expectVerified(
  Map<String, Map<String, dynamic>> entries,
  String key,
  String expectedText,
) {
  final entry = entries[key];
  expect(entry, isNotNull, reason: key);
  final normalizedText = _normalize(expectedText);
  expect(_normalize(entry!['text'] as String), normalizedText, reason: key);
  expect(entry['textHash'], _textHash(normalizedText), reason: key);
  expect(entry['locale'], 'vi-VN', reason: key);
  expect(entry['modelId'], 'eleven_v3', reason: key);
  expect(entry['voiceId'], '5CVDNcIPiOYgRUQuxXd7', reason: key);
  expect((entry['speed'] as num).toDouble(), 0.9, reason: key);

  final audio = File(entry['asset'] as String);
  expect(audio.existsSync(), isTrue, reason: key);
  final bytes = audio.readAsBytesSync();
  expect(bytes, isNotEmpty, reason: key);
  expect(bytes.length, entry['sizeBytes'], reason: key);
  expect(sha256.convert(bytes).toString(), entry['sha256'], reason: key);
}

String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _textHash(String value) =>
    sha256.convert(utf8.encode(_normalize(value))).toString();
