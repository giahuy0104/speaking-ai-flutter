import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/audio_loudness_manifest.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AudioLoudnessManifest.resetForTesting);
  tearDown(AudioLoudnessManifest.resetForTesting);

  test('reads the gain of a bundled clip', () async {
    final manifest = await AudioLoudnessManifest.load(
      bundle: _FakeBundle('''
{"policy": {"targetRmsDbfs": -21.0},
 "gainDb": {"assets/audio/MAIN/a.mp3": -8.25,
            "assets/audio/MAIN/b.mp3": -12}}
'''),
    );

    expect(manifest.gainDbForAsset('assets/audio/MAIN/a.mp3'), -8.25);
    expect(manifest.gainDbForAsset('assets/audio/MAIN/b.mp3'), -12.0);
    expect(manifest.gainDbForAsset('assets/audio/MAIN/missing.mp3'), isNull);
  });

  test('a missing or unreadable manifest never blocks playback', () async {
    final manifest = await AudioLoudnessManifest.load(bundle: _MissingBundle());

    expect(manifest.length, 0);
    expect(manifest.gainDbForAsset('assets/audio/MAIN/a.mp3'), isNull);
  });

  test('malformed content is treated as no measurements', () async {
    final manifest = await AudioLoudnessManifest.load(
      bundle: _FakeBundle('["not", "an", "object"]'),
    );

    expect(manifest.length, 0);
  });

  group('the shipped manifest', () {
    late Map<String, Object?> payload;

    setUpAll(() {
      payload =
          jsonDecode(File('assets/data/audio_loudness.json').readAsStringSync())
              as Map<String, Object?>;
    });

    test('measures the bundled catalogue', () {
      final gains = (payload['gainDb']! as Map<String, Object?>);
      final bundled = Directory('assets/audio')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path)
          .where((path) => path.endsWith('.mp3'))
          .toSet();

      expect(bundled, isNotEmpty);
      for (final key in gains.keys) {
        expect(bundled, contains(key), reason: '$key is not a bundled clip');
      }
      // Clips longer than the 30s metering window are left alone on purpose,
      // exactly as Android skips them, so full coverage is not expected.
      expect(gains.length / bundled.length, greaterThan(0.95));
    });

    test('keeps the level policy in step with Android', () {
      final policy = payload['policy']! as Map<String, Object?>;
      final kotlin = File(
        'android/app/src/main/kotlin/com/innotrik/aispeaking/'
        'AndroidPlaybackLoudness.kt',
      ).readAsStringSync();

      // Two platforms reading one manifest only sound the same while the
      // manifest was built to the same target the runtime meter aims at.
      double constant(String name) => double.parse(
        RegExp('const val $name = (-?[0-9.]+)').firstMatch(kotlin)!.group(1)!,
      );

      expect(policy['targetRmsDbfs'], constant('TARGET_RMS_DBFS'));
      expect(
        policy['samplePeakCeilingDbfs'],
        constant('SAMPLE_PEAK_CEILING_DBFS'),
      );
      expect(policy['maxGainDb'], constant('MAX_GAIN_DB'));
      expect(policy['measurement'], 'gated-rms-dbfs');
    });

    test('levels the Vietnamese and English halves of the catalogue', () {
      final gains = (payload['gainDb']! as Map<String, Object?>).map(
        (key, value) => MapEntry(key, (value! as num).toDouble()),
      );
      // The complaint behind this work: a Vietnamese lead followed by a much
      // quieter English sentence. If the two groups still need materially
      // different gains after measuring, the measurement is wrong.
      final vietnamese = _median(gains, '.vi.mp3');
      final english = _median(gains, '.en.mp3');

      expect(vietnamese, isNotNull);
      expect(english, isNotNull);
      // Vietnamese clips were authored ~4 dB louder, so they must be pulled
      // down further than the English ones.
      expect(vietnamese!, lessThan(english!));
      expect(english - vietnamese, greaterThan(2.0));
    });
  });
}

double? _median(Map<String, double> gains, String suffix) {
  final values =
      gains.entries
          .where((entry) => entry.key.endsWith(suffix))
          .map((entry) => entry.value)
          .toList()
        ..sort();
  return values.isEmpty ? null : values[values.length ~/ 2];
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final String contents;

  @override
  Future<ByteData> load(String key) async {
    expect(key, AudioLoudnessManifest.assetKey);
    return ByteData.sublistView(utf8.encode(contents));
  }
}

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Unable to load asset: $key');
}
