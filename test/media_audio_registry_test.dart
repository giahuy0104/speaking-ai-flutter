import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_manifest.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/media_audio_keys.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('songs pack registers exactly the five approved recordings', () async {
    final raw =
        jsonDecode(await File('assets/data/songs_audio.json').readAsString())
            as Map<String, dynamic>;
    final manifest = AudioPackManifest.fromJson(raw);

    expect(manifest.pack, 'songs');
    expect(raw['allowTtsFallback'], isFalse);
    expect(manifest.prompts, hasLength(5));
    expect(manifest.prompts.map((prompt) => prompt.key.value).toSet(), <String>{
      MediaAudioKeys.songA067T05,
      MediaAudioKeys.songA067T07,
      MediaAudioKeys.songA067T08,
      MediaAudioKeys.songA0810T03,
      MediaAudioKeys.songA0810T04,
    });
    await _expectVerifiedAssets(manifest);
  });

  test('system-sfx pack registers H20 test and Star Ting', () async {
    final raw =
        jsonDecode(
              await File('assets/data/system_sfx_audio.json').readAsString(),
            )
            as Map<String, dynamic>;
    final manifest = AudioPackManifest.fromJson(raw);

    expect(manifest.pack, 'system-sfx');
    expect(raw['allowTtsFallback'], isFalse);
    expect(manifest.prompts.map((prompt) => prompt.key.value).toSet(), <String>{
      MediaAudioKeys.h20SpeakerTest,
      MediaAudioKeys.rewardStarTing,
    });
    await _expectVerifiedAssets(manifest);
  });

  test(
    'all five curriculum song IDs resolve to loadable bundled assets',
    () async {
      for (final id in const <String>[
        'C35-L1-T02-B02_SONG',
        'C35-L3-T09-B02_SONG',
        'C35-L3-T10-B02_SONG',
        'C67-L3-T08-B01_SONG',
        'C810-L1-T01-B02_SONG',
      ]) {
        final uri = MediaAudioKeys.bundledSongUri(id);
        expect(uri?.scheme, 'asset');
        expect(uri?.path, endsWith('.mp3'));
        final assetPath = uri!.path.replaceFirst(RegExp(r'^/'), '');
        final bytes = await rootBundle.load(assetPath);
        expect(bytes.lengthInBytes, greaterThan(0), reason: id);
      }
      expect(MediaAudioKeys.bundledSongUri('missing-song'), isNull);
    },
  );
}

Future<void> _expectVerifiedAssets(AudioPackManifest manifest) async {
  for (final prompt in manifest.prompts) {
    final file = File(prompt.asset!);
    expect(await file.exists(), isTrue, reason: prompt.key.value);
    final bytes = await file.readAsBytes();
    expect(bytes.length, prompt.sizeBytes, reason: prompt.key.value);
    expect(
      sha256.convert(bytes).toString(),
      prompt.sha256,
      reason: prompt.key.value,
    );
  }
}
