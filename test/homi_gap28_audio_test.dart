import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_base.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> gaps;
  late List<Map<String, dynamic>> all;
  setUpAll(() {
    final plan =
        jsonDecode(
              File(
                'deliverables/homi-gap28-audio-plan.json',
              ).readAsStringSync(),
            )
            as Map;
    gaps = (plan['prompts'] as List).cast<Map<String, dynamic>>();
    all = [
      for (final name in ['main_assistant_audio', 'curriculum_audio'])
        ...(jsonDecode(File('assets/data/$name.json').readAsStringSync())
                as Map)['prompts']
            as List,
    ].cast<Map<String, dynamic>>();
  });

  test(
    'all 28 reviewed gaps have unique enabled bundled Eleven v3 audio',
    () async {
      expect(gaps, hasLength(28));
      expect(gaps.map((p) => p['text']).toSet(), hasLength(28));
      expect(gaps.every((p) => p['locale'] == 'vi-VN'), true);
      for (final gap in gaps) {
        final matches = all.where(
          (p) => p['text'] == gap['text'] && p['locale'] == gap['locale'],
        );
        expect(matches, hasLength(1), reason: gap['text'] as String);
        final prompt = matches.single;
        expect(prompt['enabled'], true);
        expect(prompt['asset'], gap['asset']);
        final asset = prompt['asset'] as String;
        final receipt =
            jsonDecode(File('$asset.json').readAsStringSync()) as Map;
        final bundled = await rootBundle.load(asset);
        final bytes = bundled.buffer.asUint8List(
          bundled.offsetInBytes,
          bundled.lengthInBytes,
        );
        expect(sha256.convert(bytes).toString(), prompt['sha256']);
        expect(receipt['finalSha256'], prompt['sha256']);
        expect(receipt['voiceId'], '5CVDNcIPiOYgRUQuxXd7');
        expect(receipt['request']['model_id'], 'eleven_v3');
        expect(receipt['request']['text'], gap['text']);
        expect(receipt['request']['language_code'], 'vi');
        expect(receipt['request']['voice_settings']['speed'], 1.0);
        expect(receipt['speed'], 0.9);
        expect(receipt['speedMethod'], 'ffmpeg-atempo');
        expect(
          receipt['durationSeconds'],
          closeTo((receipt['sourceDurationSeconds'] as num) / 0.9, 0.25),
        );
        expect(bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
      }
    },
  );

  test(
    'real text lookup plays each gap as an asset on all output routes, without TTS',
    () async {
      final delegate = _GapDelegate();
      final service = MainAssistantAudioPromptService(
        delegate: delegate,
        additionalManifestAssets: const ['assets/data/curriculum_audio.json'],
      );
      addTearDown(service.dispose);
      for (final gap in gaps) {
        final text = gap['text'] as String;
        final expected = all.singleWhere((p) => p['id'] == gap['id'])['sha256'];
        expect(await service.authoredPromptBudget(text), isNotNull);
        await service.speakAndWait(text);
        expect(delegate.played.last, '$expected:normal');
        await service.speakAndWaitOnSelectedMediaOutput(text);
        expect(delegate.played.last, '$expected:selected');
        await service.speakAndWaitOnPhoneSpeaker(text);
        expect(delegate.played.last, '$expected:phone');
      }
      expect(delegate.played, hasLength(84));
      expect(delegate.spoken, isEmpty);
      await service.speakAndWait('Câu mới chưa nằm trong kho audio.');
      expect(delegate.spoken, ['Câu mới chưa nằm trong kho audio.']);
    },
  );
}

class _GapDelegate
    implements VoicePromptService, AuthoredAudioVoicePromptService {
  final played = <String>[];
  final spoken = <String>[];
  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    final route = forcePhoneSpeaker
        ? 'phone'
        : forceMediaPlayback
        ? 'selected'
        : 'normal';
    played.add('${sha256.convert(bytes)}:$route');
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async =>
      spoken.add(text);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
