import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streamed_wav_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';

import 'core/audio/streamed_wav_source_test.dart' show streamingWavHeader;
import 'support/controlled_audio_playback.dart';

/// Never downloads: a network clip stays a network clip, and the background
/// cache copy started after playback cannot reach a real host.
class _NetworkCache extends ControlledCache {
  @override
  Future<Uri?> cache(Uri remoteUri) async => null;
}

/// One live backend stream: the test feeds its bytes and decides when it ends.
class _Backend {
  final upstream = StreamController<List<int>>();
  int requests = 0;

  http.Client client() => MockClient.streaming((request, _) async {
    requests++;
    return http.StreamedResponse(
      upstream.stream,
      200,
      headers: const {'content-type': 'audio/wav'},
    );
  });

  /// [seconds] of 24 kHz mono 16-bit PCM (48 000 bytes/s) after the live
  /// header, which claims 0xFFFFFFFF data bytes like the backend's does.
  void send(double seconds) {
    upstream.add(streamingWavHeader());
    upstream.add(Uint8List((48000 * seconds).round()));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const levelChannel = MethodChannel('ailingo_voice_prompt');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final englishStream = Uri.parse(
    'https://api-dev.example/api/audio/stream?text=Good%20morning',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(levelChannel, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(sessionChannel, null);
    messenger.setMockMethodCallHandler(levelChannel, null);
  });

  ({JustAudioPlaybackService service, ControlledPlayer player, _Backend backend})
  createService() {
    final player = ControlledPlayer();
    final cache = _NetworkCache();
    final backend = _Backend();
    final service = JustAudioPlaybackService(
      player: player,
      cache: cache,
      streamedWavClient: backend.client,
    );
    addTearDown(() async {
      await service.dispose();
      cache.dispose();
      // Not awaited: with no listener (iOS, other clips) close never completes.
      unawaited(backend.upstream.close());
    });
    return (service: service, player: player, backend: backend);
  }

  group('Android live speech stream', () {
    test('plays through the loopback server, not the backend URL', () async {
      final (:service, :player, :backend) = createService();

      await service.play(englishStream);

      final played = Uri.parse(player.loadedPath!);
      expect(played.host, '127.0.0.1');
      expect(played.path, startsWith('/wav/'));
      expect(backend.requests, 1, reason: 'downloaded by the app itself');
    });

    test(
      'completes when the real sound has played, though the player believes '
      'the clip lasts ~24.8 hours',
      () async {
        final (:service, :player, :backend) = createService();
        final completion = service.completionStream.first;
        final playing = <bool>[];
        final playingSubscription = service.playingStream.listen(playing.add);
        addTearDown(playingSubscription.cancel);

        await service.play(englishStream);
        backend.send(1.0);
        await backend.upstream.close();
        player.emitState(
          playing: true,
          processingState: ProcessingState.ready,
          position: const Duration(seconds: 1),
        );

        await completion.timeout(const Duration(seconds: 2));
        expect(player.playing, isFalse, reason: 'paused at its real end');
        // The same paused state reaches playingStream right after completion.
        await Future<void>.delayed(Duration.zero);
        expect(playing.last, isFalse);
      },
    );

    test(
      'does not end while the stream is still downloading, then ends at the '
      'real duration',
      () async {
        final (:service, :player, :backend) = createService();
        var completed = false;
        final subscription = service.completionStream.listen(
          (_) => completed = true,
        );
        addTearDown(subscription.cancel);

        await service.play(englishStream);
        backend.send(0.5);
        // Synthesis is slower than playback: the player waits for bytes.
        player.emitState(
          playing: true,
          processingState: ProcessingState.buffering,
          position: const Duration(milliseconds: 500),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(completed, isFalse);
        expect(player.playing, isTrue);

        backend.upstream.add(Uint8List(48000));
        await backend.upstream.close();
        player.emitState(
          playing: true,
          processingState: ProcessingState.ready,
          position: const Duration(milliseconds: 1500),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(completed, isTrue);
      },
    );

    test('a completion armed for the next play ignores the old clip', () async {
      final (:service, :player, :backend) = createService();
      await service.play(englishStream);
      backend.send(1.0);
      await backend.upstream.close();
      player.emitState(
        playing: true,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(player.playing, isFalse);

      var nextCompleted = false;
      final subscription = service.completionStream.listen(
        (_) => nextCompleted = true,
      );
      addTearDown(subscription.cancel);
      player.emitState(playing: false, processingState: ProcessingState.ready);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(nextCompleted, isFalse);
    });

    test('replaying an ended stream rewinds it and plays it again', () async {
      final (:service, :player, :backend) = createService();
      await service.play(englishStream);
      backend.send(1.0);
      await backend.upstream.close();
      player.emitState(
        playing: true,
        processingState: ProcessingState.ready,
        position: const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(player.playing, isFalse);

      await service.play(englishStream);

      expect(player.playing, isTrue);
      expect(player.position, Duration.zero);
      expect(backend.requests, 1, reason: 'replayed from memory');
    });
  });

  test('iOS keeps asking the backend for the finished file', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final (:service, :player, :backend) = createService();

    await service.play(englishStream);

    final played = Uri.parse(player.loadedPath!);
    expect(played.host, 'api-dev.example');
    expect(played.queryParameters['format'], 'caf');
    expect(backend.requests, 0);
  });

  test('Android plays any other network clip directly', () async {
    final (:service, :player, :backend) = createService();
    final clip = Uri.parse('https://cdn.example/audio/clip.mp3');

    await service.play(clip);

    expect(player.loadedPath, clip.toString());
    expect(backend.requests, 0);
  });

  group('StreamedWavEndDetector', () {
    final start = DateTime(2026, 11, 20, 12);

    test('never ends while the clip is still downloading', () {
      final detector = StreamedWavEndDetector();
      expect(
        detector.observe(
          playableDuration: null,
          position: const Duration(hours: 1),
          playing: true,
          now: start,
        ),
        isFalse,
      );
    });

    test('ends at the real duration, minus a small tolerance', () {
      final detector = StreamedWavEndDetector();
      const real = Duration(seconds: 3);
      expect(
        detector.observe(
          playableDuration: real,
          position: const Duration(milliseconds: 2500),
          playing: true,
          now: start,
        ),
        isFalse,
      );
      expect(
        detector.observe(
          playableDuration: real,
          position: const Duration(milliseconds: 2900),
          playing: true,
          now: start,
        ),
        isTrue,
      );
    });

    test('ends when a downloaded clip stops moving short of its end', () {
      final detector = StreamedWavEndDetector();
      const real = Duration(seconds: 3);
      const stuck = Duration(milliseconds: 2600);
      bool at(Duration elapsed) => detector.observe(
        playableDuration: real,
        position: stuck,
        playing: true,
        now: start.add(elapsed),
      );

      expect(at(Duration.zero), isFalse);
      expect(at(const Duration(milliseconds: 100)), isFalse);
      expect(at(const Duration(milliseconds: 1000)), isFalse);
      expect(at(const Duration(milliseconds: 1700)), isTrue);
    });

    test('a paused player is never treated as stalled', () {
      final detector = StreamedWavEndDetector();
      const real = Duration(seconds: 3);
      const stuck = Duration(milliseconds: 1000);
      for (var ms = 0; ms <= 5000; ms += 500) {
        expect(
          detector.observe(
            playableDuration: real,
            position: stuck,
            playing: false,
            now: start.add(Duration(milliseconds: ms)),
          ),
          isFalse,
        );
      }
    });
  });
}
