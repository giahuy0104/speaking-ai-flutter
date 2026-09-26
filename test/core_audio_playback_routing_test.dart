import 'dart:async';
import 'dart:math' as math;

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const levelChannel = MethodChannel('ailingo_voice_prompt');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final firstUri = Uri.parse('file:///first.wav');
  final secondUri = Uri.parse('file:///second.wav');

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

  test(
    'stop removes a queued play before its H20 route can be released',
    () async {
      final coordinator = AudioTurnCoordinator();
      final prompt = await coordinator.acquire(
        owner: AudioTurnOwner.mainAssistant,
        mode: AudioTurnMode.promptPlayback,
      );
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(
        player: player,
        cache: cache,
        audioTurnCoordinator: coordinator,
      );
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
        await coordinator.dispose();
      });

      final playing = service.play(firstUri);
      final cancelled = expectLater(
        playing,
        throwsA(isA<AudioTurnAcquireCancelled>()),
      );
      await _flush();
      expect(coordinator.pendingCount, 1);
      await service.stop();
      await cancelled;
      expect(coordinator.pendingCount, 0);
      await prompt.release();
      await _flush();
      expect(player.playedPaths, isEmpty);
      expect(cache.resolveCalls, 0);

      await service.play(secondUri);
      expect(player.playedPaths, <String>[secondUri.toFilePath()]);
    },
  );

  test(
    'late cache result cannot restart a stopped clip or release a newer turn',
    () async {
      final coordinator = AudioTurnCoordinator();
      final player = _ControlledPlayer();
      final cache = _ControlledCache()..pendingResolve = Completer<Uri>();
      final pending = cache.pendingResolve!;
      final service = JustAudioPlaybackService(
        player: player,
        cache: cache,
        audioTurnCoordinator: coordinator,
      );
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
        await coordinator.dispose();
      });

      final playing = service.play(firstUri);
      final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
      await cache.resolveEntered.future;
      await service.stop();
      await cancelled;
      cache.pendingResolve = null;
      await service.play(secondUri);
      final newToken = coordinator.currentToken;
      expect(newToken, isNotNull);
      pending.complete(firstUri);
      await _flush();
      expect(player.playedPaths, <String>[secondUri.toFilePath()]);
      expect(coordinator.currentToken, newToken);
    },
  );

  test(
    'stop during native source loading prevents late play and permits next clip',
    () async {
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });
      // Seed the cached source identity, then cancel a different native load.
      await service.play(secondUri);
      await service.stop();
      player.playedPaths.clear();
      player.pendingLoad = Completer<void>();
      final pending = player.pendingLoad!;
      final playing = service.play(firstUri);
      final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
      await player.blockedLoadEntered.future;
      await service.stop();
      await cancelled;
      player.pendingLoad = null;
      final next = service.play(secondUri);
      pending.complete();
      await next;
      expect(player.playedPaths, <String>[secondUri.toFilePath()]);
    },
  );

  test('stop immediately before native play keeps the phone silent', () async {
    final player = _ControlledPlayer()..pendingSpeed = Completer<void>();
    final cache = _ControlledCache();
    final service = JustAudioPlaybackService(player: player, cache: cache);
    addTearDown(() async {
      await service.dispose();
      cache.dispose();
    });
    final playing = service.play(firstUri);
    final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
    await player.speedEntered.future;
    await service.stop();
    await cancelled;
    player.pendingSpeed!.complete();
    await _flush();
    expect(player.playedPaths, isEmpty);
  });

  test(
    'dispose cancels pending cache work without reviving the player',
    () async {
      final player = _ControlledPlayer();
      final cache = _ControlledCache()..pendingResolve = Completer<Uri>();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(cache.dispose);
      final playing = service.play(firstUri);
      final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
      await cache.resolveEntered.future;
      await service.dispose();
      await cancelled;
      cache.pendingResolve!.complete(firstUri);
      await _flush();
      expect(player.playedPaths, isEmpty);
      expect(player.disposeCalls, 1);
      await expectLater(
        service.play(secondUri),
        throwsA(isA<PlaybackException>()),
      );
    },
  );

  test(
    'each Android player keeps its selected output when another session prepares media',
    () async {
      final h20Player = _ControlledPlayer();
      final phonePlayer = _ControlledPlayer();
      final cache = _ControlledCache();
      final h20 = JustAudioPlaybackService(player: h20Player, cache: cache);
      final phone = JustAudioPlaybackService(player: phonePlayer, cache: cache);
      addTearDown(() async {
        await h20.dispose();
        await phone.dispose();
        cache.dispose();
      });
      h20.setCommunicationRouteActive(true);
      await h20.prepare();
      await phone.prepare();
      await h20.play(firstUri);
      expect(
        h20Player.attributesAtPlay.single.usage,
        AndroidAudioUsage.voiceCommunication,
      );
      expect(
        h20Player.attributesAtPlay.single.contentType,
        AndroidAudioContentType.speech,
      );
      await phone.play(secondUri);
      expect(
        phonePlayer.attributesAtPlay.single.usage,
        AndroidAudioUsage.media,
      );
      expect(h20Player.attributes!.usage, AndroidAudioUsage.voiceCommunication);

      h20.setCommunicationRouteActive(false);
      await h20.play(secondUri);
      expect(h20Player.attributesAtPlay.last.usage, AndroidAudioUsage.media);
    },
  );

  test('late cancelled preparation cannot overwrite the next output', () async {
    final firstPreparation = Completer<void>();
    final preparationEntered = Completer<void>();
    var preparations = 0;
    messenger.setMockMethodCallHandler(sessionChannel, (call) async {
      if (call.method == 'setConfiguration' && ++preparations == 1) {
        preparationEntered.complete();
        await firstPreparation.future;
      }
      return null;
    });
    final player = _ControlledPlayer();
    final cache = _ControlledCache();
    final service = JustAudioPlaybackService(player: player, cache: cache);
    addTearDown(() async {
      await service.dispose();
      cache.dispose();
    });
    service.setCommunicationRouteActive(true);
    final playing = service.play(firstUri);
    final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
    await preparationEntered.future;
    await service.stop();
    await cancelled;
    service.setCommunicationRouteActive(false);
    await service.play(secondUri);
    firstPreparation.complete();
    await _flush();
    expect(player.attributes!.usage, AndroidAudioUsage.media);
    expect(player.playedPaths, <String>[secondUri.toFilePath()]);
  });

  test('iOS playback does not receive Android attribute overrides', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final player = _ControlledPlayer();
    final cache = _ControlledCache();
    final service = JustAudioPlaybackService(player: player, cache: cache);
    addTearDown(() async {
      await service.dispose();
      cache.dispose();
    });
    service.setCommunicationRouteActive(true);
    await service.play(firstUri);
    expect(player.attributes, isNull);
    expect(player.playedPaths, <String>[firstUri.toFilePath()]);
  });

  test(
    'measured negative gain attenuates the source before playback',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(levelChannel, (call) async {
        calls.add(call);
        return <String, Object?>{'gainDb': -6.0};
      });
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      await service.play(firstUri);

      expect(calls.single.method, 'analyzePlaybackLevel');
      expect(calls.single.arguments, {'path': firstUri.toFilePath()});
      expect(player.volumesAtPlay.single, closeTo(math.pow(10, -6 / 20), 1e-9));
      expect(player.volumeChanges, player.volumesAtPlay);
    },
  );

  for (final followingGain in <double>[0.0, 6.0]) {
    test(
      'measured $followingGain dB resets a previous clip attenuation',
      () async {
        messenger.setMockMethodCallHandler(levelChannel, (call) async {
          final path = (call.arguments as Map<Object?, Object?>)['path'];
          return {
            'gainDb': path == firstUri.toFilePath() ? -12.0 : followingGain,
          };
        });
        final player = _ControlledPlayer();
        final cache = _ControlledCache();
        final service = JustAudioPlaybackService(player: player, cache: cache);
        addTearDown(() async {
          await service.dispose();
          cache.dispose();
        });

        await service.play(firstUri);
        await service.play(secondUri);

        expect(player.volumesAtPlay.first, lessThan(1.0));
        expect(player.volumesAtPlay.last, 1.0);
      },
    );
  }

  test(
    'cancelled measurement neither delays nor changes the following clip',
    () async {
      final pendingMeasurement = Completer<Map<String, Object?>>();
      final measurementEntered = Completer<void>();
      messenger.setMockMethodCallHandler(levelChannel, (call) async {
        final path = (call.arguments as Map<Object?, Object?>)['path'];
        if (path == firstUri.toFilePath()) {
          measurementEntered.complete();
          return pendingMeasurement.future;
        }
        return {'gainDb': 0.0};
      });
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      final firstPlay = service.play(firstUri);
      final cancelled = expectLater(
        firstPlay,
        throwsA(isA<PlaybackException>()),
      );
      await measurementEntered.future;
      await service.stop();
      await cancelled;
      final next = service.play(secondUri);
      try {
        await _flush();
        expect(player.playedPaths, <String>[secondUri.toFilePath()]);
        expect(player.volumeChanges, <double>[1.0]);
      } finally {
        pendingMeasurement.complete({'gainDb': -24.0});
        await next;
      }
      await _flush();
      expect(player.playedPaths, <String>[secondUri.toFilePath()]);
      expect(player.volumeChanges, <double>[1.0]);
    },
  );

  test(
    'unsupported measurement resets attenuation and uses fallback immediately',
    () async {
      messenger.setMockMethodCallHandler(levelChannel, (call) async {
        final path = (call.arguments as Map<Object?, Object?>)['path'];
        return path == firstUri.toFilePath() ? {'gainDb': -6.0} : null;
      });
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      await service.play(firstUri);
      await service.play(secondUri).timeout(const Duration(seconds: 1));

      expect(player.volumesAtPlay.first, lessThan(1.0));
      expect(player.volumesAtPlay.last, 1.0);
    },
  );

  test(
    'timed out measurement falls back and ignores its late gain result',
    () async {
      final pendingMeasurement = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(levelChannel, (call) async {
        final path = (call.arguments as Map<Object?, Object?>)['path'];
        return path == firstUri.toFilePath()
            ? {'gainDb': -6.0}
            : pendingMeasurement.future;
      });
      final player = _ControlledPlayer();
      final cache = _ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      await service.play(firstUri);
      await service.play(secondUri).timeout(const Duration(seconds: 2));
      expect(player.volumesAtPlay.last, 1.0);
      final changesBeforeLateResult = List<double>.of(player.volumeChanges);
      pendingMeasurement.complete({'gainDb': -30.0});
      await _flush();
      expect(player.volumeChanges, changesBeforeLateResult);
      expect(player.playedPaths, <String>[
        firstUri.toFilePath(),
        secondUri.toFilePath(),
      ]);
    },
  );
}

Future<void> _flush() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledCache extends DeviceAudioCache {
  Completer<Uri>? pendingResolve;
  final resolveEntered = Completer<void>();
  int resolveCalls = 0;

  @override
  Future<Uri> resolveAfterPreload(
    Uri uri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async {
    resolveCalls++;
    if (!resolveEntered.isCompleted) resolveEntered.complete();
    return pendingResolve?.future ?? uri;
  }
}

class _ControlledPlayer implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final List<String> playedPaths = <String>[];
  final List<double> volumeChanges = <double>[];
  final List<double> volumesAtPlay = <double>[];
  final List<AndroidAudioAttributes> attributesAtPlay =
      <AndroidAudioAttributes>[];
  final blockedLoadEntered = Completer<void>();
  final speedEntered = Completer<void>();
  Completer<void>? pendingLoad;
  Completer<void>? pendingSpeed;
  AndroidAudioAttributes? attributes;
  String? loadedPath;
  int disposeCalls = 0;
  bool _playing = false;
  double _volume = 1.0;

  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => ProcessingState.ready;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 2);
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    final pending = pendingLoad;
    if (pending != null) {
      if (!blockedLoadEntered.isCompleted) blockedLoadEntered.complete();
      await pending.future;
    }
    loadedPath = path;
    return duration;
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!speedEntered.isCompleted) speedEntered.complete();
    await pendingSpeed?.future;
  }

  @override
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes value) async {
    attributes = value;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumeChanges.add(volume);
  }

  @override
  Future<void> play() async {
    playedPaths.add(loadedPath!);
    volumesAtPlay.add(_volume);
    if (attributes != null) attributesAtPlay.add(attributes!);
    _playing = true;
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _states.close();
    await _positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
