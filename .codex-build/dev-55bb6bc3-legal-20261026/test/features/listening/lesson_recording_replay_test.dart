import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ailingo_voice_prompt');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late File original;
  late File normalized;
  late LessonMediaService media;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    directory = await Directory.systemTemp.createTemp('lesson-replay-');
    original = await File('${directory.path}/take.wav').writeAsBytes([1]);
    normalized = await File(
      '${directory.path}/take.normalized.wav',
    ).writeAsBytes([2]);
    media = LessonMediaService();
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    await media.dispose();
    await directory.delete(recursive: true);
  });

  LessonRecording recording(String path) =>
      LessonRecording(filePath: path, duration: const Duration(seconds: 2));

  test(
    'concurrent preparation and returned path normalize only once',
    () async {
      var calls = 0;
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        await gate.future;
        await original.delete(); // Native normalizer replaces the source.
        return normalized.path;
      });
      final first = media.prepareExternalRecordingForPlayback(
        recording(original.path),
      );
      final second = media.prepareExternalRecordingForPlayback(
        recording(original.path),
      );
      gate.complete();
      final results = await Future.wait([first, second]);
      final repeated = await media.prepareExternalRecordingForPlayback(
        results.first,
      );
      expect(calls, 1);
      expect(results.map((r) => r.filePath), everyElement(normalized.path));
      expect(repeated.filePath, normalized.path);
    },
  );

  test('transient normalization failure retries once', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) throw PlatformException(code: 'TEMPORARY');
      return normalized.path;
    });
    final prepared = await media.prepareExternalRecordingForPlayback(
      recording(original.path),
    );
    expect(prepared.filePath, normalized.path);
    expect(calls, 2);
  });

  for (final failure in ['platform', 'missingPlugin', 'null', 'missingFile']) {
    test('$failure never falls back to unnormalized audio', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        switch (failure) {
          case 'platform':
            throw PlatformException(code: 'FAILED');
          case 'missingPlugin':
            throw MissingPluginException();
          case 'missingFile':
            return '${directory.path}/missing.wav';
          default:
            return null;
        }
      });
      await expectLater(
        media.prepareExternalRecordingForPlayback(recording(original.path)),
        throwsA(isA<LessonMediaException>()),
      );
      expect(calls, 2);
      expect(await original.exists(), isTrue);
      // A failed preparation is not cached as a success.
      messenger.setMockMethodCallHandler(channel, (_) async => normalized.path);
      expect(
        (await media.prepareExternalRecordingForPlayback(
          recording(original.path),
        )).filePath,
        normalized.path,
      );
    });
  }

  test('already level native recording can keep its original path', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => original.path);
    expect(
      (await media.prepareExternalRecordingForPlayback(
        recording(original.path),
      )).filePath,
      original.path,
    );
  });

  test(
    'shared replay fixes gain, output and duration and propagates failure',
    () async {
      final player = _ReplayPolicyProbe();
      await player.playRecordingToCompletion(recording(normalized.path));
      expect(player.uri, Uri.file(normalized.path));
      expect(player.gain, 0);
      expect(player.fixed, isTrue);
      expect(player.route, LessonPlaybackRoute.selectedLessonDevice);
      expect(player.timeout, const Duration(seconds: 10));
      await player.playRecordingToCompletion(
        LessonRecording(
          filePath: normalized.path,
          duration: const Duration(seconds: 8),
        ),
      );
      expect(player.timeout, const Duration(seconds: 13));
      player.fail = true;
      await expectLater(
        player.playRecordingToCompletion(recording(normalized.path)),
        throwsA(isA<LessonMediaException>()),
      );
      await player.dispose();
    },
  );
}

class _ReplayPolicyProbe extends LessonMediaService {
  Uri? uri;
  double? gain;
  bool? fixed;
  LessonPlaybackRoute? route;
  Duration? timeout;
  bool fail = false;

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8,
    bool fixedPlaybackGain = false,
  }) async {
    this.uri = uri;
    this.timeout = timeout;
    this.route = route;
    gain = playbackGainDb;
    fixed = fixedPlaybackGain;
    if (fail) throw const LessonMediaException('Playback failed');
  }
}
