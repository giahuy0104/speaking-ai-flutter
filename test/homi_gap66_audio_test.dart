import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/homi_gap66_audio_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      jsonDecode(File(homiGap66ManifestAsset).readAsStringSync()) as Map;
  final entries = (manifest['prompts'] as List).cast<Map<String, dynamic>>();
  final groups = entries.map((e) => e['group'] as String).toSet();

  test(
    '66 exact reviewed texts, unique across every enabled pack, correct receipts',
    () async {
      final expected =
          (jsonDecode(
                    File(
                      'deliverables/audio-runtime-audit-2026-09-17/missing-audio.json',
                    ).readAsStringSync(),
                  )
                  as Map)['missing']
              as List;
      expect(entries, hasLength(66));
      expect(
        entries.map((e) => e['text']).toSet(),
        expected.map((e) => e['text']).toSet(),
      );
      expect(groups, homiGap66AudioGroups.keys.toSet());
      final all = [
        for (final path in [
          MainAssistantAudioPromptService.manifestAsset,
          homiGap66ManifestAsset,
        ])
          ...(jsonDecode(File(path).readAsStringSync())['prompts'] as List),
      ];
      for (final e in entries) {
        expect(e['enabled'], true);
        expect(
          e.containsKey('url'),
          false,
          reason: 'New fixed pack is bundled; no CDN dependency.',
        );
        final matches = all.where(
          (p) =>
              p['enabled'] == true &&
              (p['text'] == e['text'] ||
                  (p['lookupTexts'] as List? ?? []).contains(e['text'])) &&
              (p['locale'] == e['locale'] ||
                  (p['lookupLocales'] as List? ?? []).contains(e['locale'])),
        );
        expect(matches, hasLength(1), reason: e['text'] as String);
        final bytes = await File(e['asset'] as String).readAsBytes();
        final receipt = jsonDecode(
          File(
            'deliverables/homi-gap66-2026-09-17/ready/${e['id']}.json',
          ).readAsStringSync(),
        );
        expect(sha256.convert(bytes).toString(), e['sha256']);
        expect(receipt['finalSha256'], e['sha256']);
        expect(receipt['request']['text'], e['text']);
        expect(receipt['request']['model_id'], 'eleven_v3');
        expect(receipt['request']['voice_settings']['speed'], 1.0);
        expect(receipt['voiceId'], '5CVDNcIPiOYgRUQuxXd7');
        expect(receipt['speed'], 0.9);
        expect(
          receipt['durationSeconds'],
          closeTo((receipt['sourceDurationSeconds'] as num) / 0.9, 0.25),
        );
        expect(manifest['profiles']['en'], {
          'voiceId': 'Nhs7eitvQWFTQBsf0yiT',
          'speed': 0.75,
        });
        expect(e['durationSeconds'], inExclusiveRange(0, 45));
        expect(bytes.length, lessThan(2 * 1024 * 1024));
        expect(await rootBundle.load(e['asset'] as String), isA<ByteData>());
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('    - assets/audio/MAIN/GAP66/'));
      expect(pubspec, isNot(contains('    - deliverables/')));
    },
  );

  test(
    'real factory honors pack/global/per-group build switches on all routes',
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
        owner: AudioTurnOwner.mainAssistant,
      );
      addTearDown(() async {
        await service.dispose();
      });
      const global =
          bool.fromEnvironment(
            'HOMI_ASSISTANT_AUTHORED_AUDIO',
            defaultValue: true,
          ) &&
          bool.fromEnvironment('HOMI_MAIN_AUTHORED_AUDIO', defaultValue: true);
      for (final e in entries) {
        for (final route in ['normal', 'selected', 'phone']) {
          calls.clear();
          final text = e['text'] as String;
          if (route == 'selected') {
            await (service as SelectedMediaOutputVoicePromptService)
                .speakAndWaitOnSelectedMediaOutput(text);
          } else if (route == 'phone') {
            await (service as PhoneSpeakerVoicePromptService)
                .speakAndWaitOnPhoneSpeaker(text);
          } else {
            await service.speakAndWait(text);
          }
          final enabled =
              global &&
              homiGap66AudioEnabled &&
              homiGap66AudioGroups[e['group']]!;
          expect(calls, hasLength(1), reason: '${e['id']} $route');
          expect(
            calls.single.method,
            enabled ? 'playAuthoredAudioAndWait' : 'speakAndWait',
            reason: '${e['id']} $route',
          );
          if (enabled) {
            final args = calls.single.arguments as Map;
            expect(
              sha256.convert(args['bytes'] as Uint8List).toString(),
              e['sha256'],
            );
            expect(args['forceMediaPlayback'], route == 'selected');
            expect(args['forcePhoneSpeaker'], route == 'phone');
          }
        }
      }
    },
  );

  test('Topic GAP recordings support stable contextual audio keys', () async {
    final delegate = _Delegate();
    final service = MainAssistantAudioPromptService(
      delegate: delegate,
      enabled: true,
      additionalManifestAssets: const [homiGap66ManifestAsset],
    );
    addTearDown(service.dispose);

    final topicEntries = entries.where(
      (entry) =>
          entry['group'] == 'gap66-level-selection' ||
          entry['group'] == 'gap66-topic-replay',
    );
    for (final entry in topicEntries) {
      final key = entry['key'];
      if (key is! String) continue;
      delegate.events.clear();
      await service.speakAndWaitWithAudioKey(
        key,
        entry['text'] as String,
        locale: entry['locale'] as String,
      );
      expect(delegate.events, ['mp3'], reason: key);
    }
  });

  for (final group in groups) {
    test(
      'isolated rollback for $group leaves other new groups playing MP3',
      () async {
        final delegate = _Delegate();
        final service = MainAssistantAudioPromptService(
          delegate: delegate,
          enabled: true,
          additionalManifestAssets: const [homiGap66ManifestAsset],
          groupEnabled: {group: false},
        );
        addTearDown(service.dispose);
        for (final e in entries) {
          delegate.events.clear();
          await service.speakAndWait(e['text'] as String);
          expect(delegate.events, [
            e['group'] == group ? 'tts:${e['text']}' : 'mp3',
          ]);
        }
      },
    );
  }

  for (final failure in [
    'missing-pack',
    'missing-file',
    'corrupt-file',
    'playback',
  ]) {
    test(
      '$failure uses original TTS; unknown dynamic text remains TTS',
      () async {
        final delegate = _Delegate()..failPlayback = failure == 'playback';
        final service = MainAssistantAudioPromptService(
          delegate: delegate,
          enabled: true,
          bundle: _FailureBundle(failure),
          additionalManifestAssets: const [homiGap66ManifestAsset],
        );
        addTearDown(service.dispose);
        final text = entries.first['text'] as String;
        await service.speakAndWait(text);
        expect(delegate.events.last, 'tts:$text');
        await service.speakAndWait('Nội dung động chưa tạo audio.');
        expect(delegate.events.last, 'tts:Nội dung động chưa tạo audio.');
      },
    );
  }
}

class _Delegate implements VoicePromptService, AuthoredAudioVoicePromptService {
  final events = <String>[];
  bool failPlayback = false;
  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    events.add('mp3');
    if (failPlayback) throw StateError('Injected playback failure');
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    events.add('tts:$text');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _FailureBundle extends CachingAssetBundle {
  _FailureBundle(this.failure);
  final String failure;
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == homiGap66ManifestAsset && failure == 'missing-pack') {
      throw StateError('Missing manifest');
    }
    return File(key).readAsString();
  }

  @override
  Future<ByteData> load(String key) async {
    if (key.contains('/GAP66/')) {
      if (failure == 'missing-file') throw StateError('Missing file');
      if (failure == 'corrupt-file') {
        return ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
      }
    }
    return ByteData.sublistView(await File(key).readAsBytes());
  }
}
