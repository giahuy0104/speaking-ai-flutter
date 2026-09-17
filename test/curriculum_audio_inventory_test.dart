import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_cloudinary_audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> prompts;
  late ListeningContentCatalog catalog;
  setUpAll(() async {
    final main =
        jsonDecode(
              await File(
                'assets/data/main_assistant_audio.json',
              ).readAsString(),
            )
            as Map;
    final pack =
        jsonDecode(
              await File('assets/data/curriculum_audio.json').readAsString(),
            )
            as Map;
    prompts = [
      ...main['prompts'] as List,
      ...pack['prompts'] as List,
    ].cast<Map<String, dynamic>>();
    catalog = await AssetListeningContentRepository().load();
  });
  Map<String, dynamic> find(String text, String locale) =>
      prompts.singleWhere((p) => p['text'] == text && p['locale'] == locale);
  test('every concrete curriculum manifest text has enabled audio', () async {
    final source =
        jsonDecode(
              await File(
                'assets/data/listening_audio_manifest_v4.json',
              ).readAsString(),
            )
            as Map;
    for (final entry in source['entries'] as List) {
      if (entry['kind'] == 'songReference') continue;
      final text = entry['sourceText'] as String;
      if (RegExp(r'[\[\]{}$]').hasMatch(text)) continue;
      expect(
        find(text, entry['locale'] as String)['enabled'],
        true,
        reason: entry['audioId'] as String,
      );
    }
    expect(
      prompts.map((p) => '${p['locale']}|${p['text']}').toSet().length,
      prompts.length,
    );
  });
  test(
    'all 109 lessons retain IDs and bundle all 1202 bilingual core samples',
    () {
      var lessons = 0;
      var samples = 0;
      var songs = 0;
      for (final group in catalog.groups) {
        for (final topic in group.topics) {
          for (final lesson in topic.lessons) {
            lessons++;
            expect(lesson.code, isNotEmpty);
            for (final sentence in lesson.sentences) {
              expect(
                sentence.audioUri.toString(),
                find(sentence.english, 'en-US')['url'],
              );
              expect(
                sentence.vietnameseAudioUri.toString(),
                find(sentence.vietnamese, 'vi-VN')['url'],
              );
              samples += 2;
            }
            for (final question in lesson.challengeBank) {
              expect(find(question.prompt, 'vi-VN')['enabled'], true);
              expect(find(question.correctAnswer, 'en-US')['enabled'], true);
              expect(
                find(question.correctVietnamese, 'vi-VN')['enabled'],
                true,
              );
            }
            if (lesson.hasV4SongStage) {
              songs++;
              expect(lesson.songAudioUri, isNotNull);
              expect(
                lesson.songAudioUri.toString(),
                isNot(contains('/CURRICULUM/')),
              );
            }
          }
        }
      }
      expect(lessons, 109);
      expect(samples, 1202);
      expect(songs, 5);
    },
  );
  test('runtime intro and resume strings have their own exact audio', () {
    for (final group in catalog.groups) {
      for (final topic in group.topics) {
        for (final lesson in topic.lessons) {
          final topicLead = lesson.number == 1
              ? 'Chủ đề ${topic.number}. '
              : '';
          final lessonLead = lesson.number == 1
              ? 'Bài đầu tiên là ${lesson.titleEn}. '
              : 'Bài này là ${lesson.titleEn}. ';
          final text =
              '$topicLead$lessonLead${lesson.entry?.text ?? ''} Bắt đầu nhé.'
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
          expect(find(text, 'vi-VN')['enabled'], true, reason: lesson.code);
          expect(
            find(
              'Mình học tiếp bài ${lesson.titleEn} nhé.',
              'vi-VN',
            )['enabled'],
            true,
          );
          expect(
            find('Mình học lại bài ${lesson.titleEn} nhé.', 'vi-VN')['enabled'],
            true,
          );
        }
      }
    }
  });
  test(
    'all uploaded curriculum files match their SHA-256 and receipts',
    () async {
      for (final prompt in prompts.where(
        (p) => (p['asset'] as String).contains('/CURRICULUM/'),
      )) {
        final bytes = await File(prompt['asset'] as String).readAsBytes();
        final digest = sha256.convert(bytes).toString();
        expect(digest, prompt['sha256'], reason: prompt['id'] as String);
        expect(Uri.parse(prompt['url'] as String).host, 'res.cloudinary.com');
        expect(prompt['durationSeconds'], inExclusiveRange(0, 45));
        final receipt =
            jsonDecode(
                  await File(
                    'deliverables/curriculum_audio_receipts/${prompt['id']}.json',
                  ).readAsString(),
                )
                as Map;
        expect(receipt['text'], prompt['text']);
        expect(receipt['sha256'], digest);
        expect((receipt['profiles'] as Map)['en'], {
          'voiceId': 'Nhs7eitvQWFTQBsf0yiT',
          'speed': 0.75,
        });
        expect((receipt['profiles'] as Map)['vi'], {
          'voiceId': '5CVDNcIPiOYgRUQuxXd7',
          'speed': 0.9,
        });
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'factory routes a lesson challenge to Cloudinary authored playback',
    () async {
      const channel = MethodChannel('ailingo_voice_prompt');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = createVoicePromptService(
        owner: AudioTurnOwner.listeningLesson,
        httpClient: createLocalCloudinaryAudioClient(),
      );
      await service.speakAndWait('Quả táo: Apple hay Ball?');
      expect(calls.single.method, 'playAuthoredAudioAndWait');
      await service.dispose();
    },
  );
}
