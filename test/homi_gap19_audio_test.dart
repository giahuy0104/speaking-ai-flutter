import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/homi_gap19_audio_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_cloudinary_audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pack =
      jsonDecode(File(homiGap19ManifestAsset).readAsStringSync()) as Map;
  final entries = (pack['prompts'] as List).cast<Map<String, dynamic>>();
  final audit =
      jsonDecode(
            File(
              'deliverables/audio-runtime-audit-2026-09-19/homi-speech-audit-summary.json',
            ).readAsStringSync(),
          )
          as Map;

  test('19 reviewed replies have unique, valid bundled MP3 files', () async {
    expect(pack['enabled'], true);
    expect(entries, hasLength(19));
    expect(
      entries.map((entry) => entry['text']).toSet(),
      (audit['currentMissing'] as List).map((entry) => entry['text']).toSet(),
    );
    final all = [
      for (final path in [
        'assets/data/main_assistant_audio.json',
        'assets/data/curriculum_audio.json',
        'assets/data/homi_gap66_audio.json',
        homiGap19ManifestAsset,
      ])
        ...(jsonDecode(File(path).readAsStringSync())['prompts'] as List),
    ];
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('    - assets/data/homi_gap19_audio.json'));
    expect(pubspec, contains('    - assets/audio/MAIN/GAP19/'));
    for (final entry in entries) {
      expect(entry['enabled'], true);
      expect(entry['locale'], 'vi-VN');
      expect(entry.containsKey('url'), false);
      final matches = all.where(
        (candidate) =>
            candidate['enabled'] == true &&
            (candidate['text'] == entry['text'] ||
                (candidate['lookupTexts'] as List? ?? []).contains(
                  entry['text'],
                )) &&
            (candidate['locale'] == entry['locale'] ||
                (candidate['lookupLocales'] as List? ?? []).contains(
                  entry['locale'],
                )),
      );
      expect(matches, hasLength(1), reason: entry['text'] as String);
      final bytes = File(entry['asset'] as String).readAsBytesSync();
      final isReplacement = entry['id'] == 'GAP19-006';
      final receipt =
          jsonDecode(
                File(
                  isReplacement
                      ? 'deliverables/homi-prompt-previews/ban-muon-nghe-lai-cau-truoc-hay-cau-sau/receipt.json'
                      : 'deliverables/homi-gap19-2026-09-19/ready/${entry['id']}.json',
                ).readAsStringSync(),
              )
              as Map;
      expect(sha256.convert(bytes).toString(), entry['sha256']);
      expect(receipt['finalSha256'], entry['sha256']);
      if (isReplacement) {
        final replacement =
            jsonDecode(
                  File(
                    'deliverables/homi-gap19-2026-09-19/replacements/GAP19-006.vi.v2.json',
                  ).readAsStringSync(),
                )
                as Map;
        expect(entry['version'], 2);
        expect(replacement['asset'], entry['asset']);
        expect(replacement['sha256'], entry['sha256']);
        expect(replacement['durationSeconds'], entry['durationSeconds']);
        expect(replacement['spokenText'], receipt['request']['text']);
      } else {
        expect(receipt['request']['text'], entry['text']);
      }
      expect(receipt['request']['model_id'], 'eleven_v3');
      expect(receipt['request']['voice_settings']['speed'], 1.0);
      expect(receipt['voiceId'], '5CVDNcIPiOYgRUQuxXd7');
      expect(receipt['speed'], 0.9);
      expect(entry['durationSeconds'], inExclusiveRange(0, 45));
      expect(bytes.length, lessThan(2 * 1024 * 1024));
      expect(await rootBundle.load(entry['asset'] as String), isA<ByteData>());
    }
  });

  test('factory plays new MP3, keeps old MP3 and dynamic TTS', () async {
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
    final client = createLocalCloudinaryAudioClient();
    final service = createVoicePromptService(httpClient: client);
    addTearDown(() async {
      await service.dispose();
      client.close();
    });
    const global =
        bool.fromEnvironment(
          'HOMI_ASSISTANT_AUTHORED_AUDIO',
          defaultValue: true,
        ) &&
        bool.fromEnvironment('HOMI_MAIN_AUTHORED_AUDIO', defaultValue: true);
    for (final entry in entries) {
      for (final route in ['normal', 'selected', 'phone']) {
        calls.clear();
        final text = entry['text'] as String;
        if (route == 'selected') {
          await (service as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text);
        } else if (route == 'phone') {
          await (service as PhoneSpeakerVoicePromptService)
              .speakAndWaitOnPhoneSpeaker(text);
        } else {
          await service.speakAndWait(text);
        }
        expect(calls, hasLength(1), reason: '${entry['id']} $route');
        expect(
          calls.single.method,
          global && homiGap19AudioEnabled
              ? 'playAuthoredAudioAndWait'
              : 'speakAndWait',
        );
        if (global && homiGap19AudioEnabled) {
          final args = calls.single.arguments as Map;
          expect(
            sha256.convert(args['bytes'] as Uint8List).toString(),
            entry['sha256'],
          );
          expect(args['forceMediaPlayback'], route == 'selected');
          expect(args['forcePhoneSpeaker'], route == 'phone');
        }
      }
    }
    calls.clear();
    await service.speakAndWait(
      'HOMI đây. Bạn muốn dịch sang tiếng Anh, học theo chủ đề hay học bộ từ vựng?',
    );
    expect(
      calls.single.method,
      global ? 'playAuthoredAudioAndWait' : 'speakAndWait',
    );
    calls.clear();
    await service.speakAndWait('Câu động chưa biết trước.');
    expect(calls.single.method, 'speakAndWait');
  });
}
