import 'dart:io';
import 'dart:math';

import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_storage_native.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_wav_normalizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('existing mono PCM and metadata stay byte-identical', () {
    final mono = _withMetadata(_wav([0, 32767, -32768], channels: 1));
    expect(normalizeAndroidLessonWav(mono), same(mono));
  });

  test('stereo keeps the stronger channel without changing duration', () {
    final stereo = _wav([1000, 3000, 32767, 32767, -32768, -32768, -1, -2]);
    final originalCopy = Uint8List.fromList(stereo);
    final mono = normalizeAndroidLessonWav(stereo);
    final header = ByteData.sublistView(mono);
    expect(_samples(mono), [3000, 32767, -32768, -2]);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(32, Endian.little), 2);
    expect(header.getUint32(4, Endian.little), mono.length - 8);
    expect(header.getUint32(40, Endian.little), 8);
    expect((mono.length - 44) / 32000, (stereo.length - 44) / 64000);
    expect(stereo, originalCopy);
  });

  test('parses odd-sized metadata chunks before PCM', () {
    final stereo = _withMetadata(_wav([500, 1500, -500, -1500]));
    expect(_samples(normalizeAndroidLessonWav(stereo)), [1500, -1500]);
  });

  test('does not halve a capture with only one live channel', () {
    final leftOnly = _wav([12000, 0, -8000, 0, 4000, 0]);
    final rightOnly = _wav([0, 12000, 0, -8000, 0, 4000]);

    expect(_samples(normalizeAndroidLessonWav(leftOnly)), [12000, -8000, 4000]);
    expect(_samples(normalizeAndroidLessonWav(rightOnly)), [
      12000,
      -8000,
      4000,
    ]);
  });

  test('does not cancel phase-inverted stereo speech', () {
    final stereo = _wav([12000, -12000, -8000, 8000, 4000, -4000]);

    expect(_samples(normalizeAndroidLessonWav(stereo)), [12000, -8000, 4000]);
  });

  test('does not reinterpret unsupported rates or encodings', () {
    final differentRate = _wav([300, 500], sampleRate: 48000);
    expect(normalizeAndroidLessonWav(differentRate), same(differentRate));
    final differentEncoding = _wav([300, 500]);
    ByteData.sublistView(differentEncoding).setUint16(20, 3, Endian.little);
    expect(
      normalizeAndroidLessonWav(differentEncoding),
      same(differentEncoding),
    );
  });

  test('lifts quiet mono speech while preserving peak headroom', () {
    final quiet = _wav([100, 500, -1000, 800, -400], channels: 1);
    final normalized = normalizeLessonWavLoudness(quiet);
    final samples = _samples(normalized);
    expect(
      samples.map((sample) => sample.abs()).reduce(max),
      greaterThan(1000),
    );
    expect(samples.map((sample) => sample.abs()).reduce(max), lessThan(32767));
    expect(samples[2], isNegative);
  });

  test('does not amplify an already loud mono recording', () {
    final loud = _wav([0, 26000, -26000, 18000], channels: 1);
    expect(normalizeLessonWavLoudness(loud), same(loud));
  });

  test('rejects truncated containers and partial stereo frames', () {
    final complete = _wav([1, 2, 3, 4]);
    expect(
      () => normalizeAndroidLessonWav(Uint8List.sublistView(complete, 0, 49)),
      throwsFormatException,
    );
    expect(
      () => normalizeAndroidLessonWav(_wav([1, 2, 3])),
      throwsFormatException,
    );
    final oversizedData = _wav([1, 2]);
    ByteData.sublistView(oversizedData).setUint32(40, 1000, Endian.little);
    expect(
      () => normalizeAndroidLessonWav(oversizedData),
      throwsFormatException,
    );
  });

  test('rejects inconsistent PCM layout without modifying original', () {
    final stereo = _wav([1, 2]);
    ByteData.sublistView(stereo).setUint16(32, 2, Endian.little);
    final originalCopy = Uint8List.fromList(stereo);
    expect(() => normalizeAndroidLessonWav(stereo), throwsFormatException);
    expect(stereo, originalCopy);
  });

  group('new lesson recording finalization', () {
    late Directory temporary;
    late File recording;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('lesson-wav-test-');
      recording = File('${temporary.path}/attempt.wav');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ailingo_voice_prompt'),
            null,
          );
      debugDefaultTargetPlatformOverride = null;
      await temporary.delete(recursive: true);
    });

    test('Android returns same finalized path with normalized audio', () async {
      await recording.writeAsBytes(_wav([100, 300, -100, -300]));
      expect(
        await resolveLessonRecording(recording.path, recording.path),
        recording.path,
      );
      final samples = _samples(await recording.readAsBytes());
      expect(samples.first, isPositive);
      expect(samples.last, isNegative);
      expect(samples.first.abs(), greaterThan(300));
      expect(await temporary.list().length, 1);
    });

    test('malformed recording is preserved when normalization fails', () async {
      final malformed = Uint8List.fromList([1, 2, 3, 4]);
      await recording.writeAsBytes(malformed);
      await expectLater(
        resolveLessonRecording(recording.path, recording.path),
        throwsFormatException,
      );
      expect(await recording.readAsBytes(), malformed);
      expect(await temporary.list().length, 1);
    });

    test(
      'iOS recordings retain their original bytes and channel layout',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final original = _wav([100, 300]);
        await recording.writeAsBytes(original);
        await resolveLessonRecording(recording.path, recording.path);
        expect(await recording.readAsBytes(), original);
      },
    );

    test('iOS uses the native leveled recording when available', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final normalized = File('${temporary.path}/attempt.normalized.wav');
      await recording.writeAsBytes(_wav([100, 300]));
      await normalized.writeAsBytes(_wav([3000, 9000], channels: 1));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ailingo_voice_prompt'),
            (call) async {
              expect(call.method, 'normalizeLessonRecording');
              expect((call.arguments as Map)['path'], recording.path);
              return normalized.path;
            },
          );

      expect(
        await resolveLessonRecording(recording.path, recording.path),
        normalized.path,
      );
    });
  });
}

Uint8List _wav(List<int> samples, {int channels = 2, int sampleRate = 16000}) {
  final header = buildPcm16WavHeader(
    pcmByteLength: samples.length * 2,
    sampleRate: sampleRate,
    channelCount: channels,
  );
  final wav = Uint8List(header.length + samples.length * 2)..setAll(0, header);
  final view = ByteData.sublistView(wav);
  for (var index = 0; index < samples.length; index += 1) {
    view.setInt16(header.length + index * 2, samples[index], Endian.little);
  }
  return wav;
}

List<int> _samples(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  return [
    for (var offset = 44; offset < wav.length; offset += 2)
      view.getInt16(offset, Endian.little),
  ];
}

Uint8List _withMetadata(Uint8List wav) {
  final withMetadata = Uint8List.fromList([
    ...wav.sublist(0, 12),
    ...'JUNK'.codeUnits,
    3,
    0,
    0,
    0,
    10,
    20,
    30,
    0,
    ...wav.sublist(12),
  ]);
  ByteData.sublistView(
    withMetadata,
  ).setUint32(4, withMetadata.length - 8, Endian.little);
  return withMetadata;
}
