import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/controlled_audio_playback.dart';

/// The media turn is exclusive: while it is held, a prompt waits. Releasing it
/// under a clip that is still playing lets the prompt start on top, and the
/// next stop cuts one of the two. That is the shape of QA row 6.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  const levelChannel = MethodChannel('ailingo_voice_prompt');
  const focusChannel = MethodChannel('ailingo_background_learning');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final uri = Uri.parse('file:///word.mp3');
  late List<String> acquiredFocus;
  late List<String> releasedFocus;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    acquiredFocus = [];
    releasedFocus = [];
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(levelChannel, (_) async => null);
    messenger.setMockMethodCallHandler(focusChannel, (call) async {
      final owner = (call.arguments as Map?)?['ownerId'] as String?;
      if (call.method == 'acquireAudioFocus') {
        acquiredFocus.add(owner!);
        return true;
      }
      if (call.method == 'releaseAudioFocus') releasedFocus.add(owner!);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(sessionChannel, null);
    messenger.setMockMethodCallHandler(levelChannel, null);
    messenger.setMockMethodCallHandler(focusChannel, null);
  });

  group('iOS native playback ownership', () {
    late _IosControlledPlayer player;
    late ControlledCache cache;
    late JustAudioPlaybackService service;
    late List<String> acquired;
    late List<String> released;
    Completer<bool>? pendingBegin;
    Object? beginError;
    bool? beginResult;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      player = _IosControlledPlayer();
      cache = ControlledCache();
      service = JustAudioPlaybackService(player: player, cache: cache);
      acquired = [];
      released = [];
      pendingBegin = null;
      beginError = null;
      beginResult = true;
      messenger.setMockMethodCallHandler(focusChannel, (call) async {
        if (call.method == 'isAudioHandoffActive') return true;
        final token = (call.arguments as Map?)?['token'] as String?;
        if (call.method == 'beginAudioPlayback') {
          acquired.add(token!);
          if (beginError case final error?) throw error;
          return pendingBegin == null
              ? beginResult
              : await pendingBegin!.future;
        }
        if (call.method == 'endAudioPlayback') released.add(token!);
        return null;
      });
    });

    tearDown(() async {
      await service.dispose();
      cache.dispose();
    });

    test(
      'holds priority until completion without a Dart turn coordinator',
      () async {
        await service.play(uri);
        expect(acquired, hasLength(1));
        expect(released, isEmpty);
        player.emitState(
          playing: true,
          processingState: ProcessingState.completed,
          position: const Duration(seconds: 2),
        );
        await flushMicrotasks();
        expect(released, acquired);
      },
    );

    test('a very short clip releases its own token exactly once', () async {
      player.finishImmediately = true;
      await service.play(uri);
      await flushMicrotasks();
      expect(released, acquired);
      await service.stop();
      expect(released, hasLength(1));
    });

    test('prepare and preload never acquire playback priority', () async {
      await service.prepare();
      await service.preload(uri);
      expect(acquired, isEmpty);
      expect(released, isEmpty);
    });

    test('does not play before the native priority acknowledgement', () async {
      pendingBegin = Completer<bool>();
      final started = service.play(uri);
      await flushMicrotasks();
      expect(acquired, hasLength(1));
      expect(player.playedPaths, isEmpty);
      pendingBegin!.complete(true);
      await started;
      expect(player.playedPaths, hasLength(1));
      expect(released, isEmpty);
    });

    test(
      'stop waits for actual player pause before releasing priority',
      () async {
        await service.play(uri);
        player.pauseGate = Completer<void>();
        final stopped = service.stop();
        await flushMicrotasks();
        expect(player.playing, isTrue);
        expect(released, isEmpty);
        player.pauseGate!.complete();
        await stopped;
        expect(player.playing, isFalse);
        expect(released, acquired);
      },
    );

    test(
      'failed pause retains priority until the player is disposed',
      () async {
        await service.play(uri);
        player.pauseError = StateError('pause failed');
        await expectLater(service.stop(), throwsStateError);
        expect(released, isEmpty);
        await service.dispose();
        expect(player.disposeCalls, 1);
        expect(released, acquired);
      },
    );

    test(
      'retry after failed pause retires old priority before playing again',
      () async {
        await service.play(uri);
        final oldToken = acquired.single;
        player.pauseError = StateError('pause failed');
        await expectLater(service.stop(), throwsStateError);
        expect(released, isEmpty);
        await expectLater(service.play(uri), throwsStateError);
        expect(acquired, [oldToken]);
        player.pauseError = null;
        await service.play(uri);
        expect(released, contains(oldToken));
        final currentToken = acquired.last;
        expect(currentToken, isNot(oldToken));
        expect(released, isNot(contains(currentToken)));
        player.emitState(
          playing: true,
          processingState: ProcessingState.completed,
          position: const Duration(seconds: 2),
        );
        await flushMicrotasks();
        expect(released, containsAll(acquired));
      },
    );

    test(
      'post-start decode failure pauses before releasing native priority',
      () async {
        player.playbackResult = Completer<void>();
        await service.play(uri);
        player.pauseGate = Completer<void>();
        player.playbackResult!.completeError(StateError('decode failed'));
        await flushMicrotasks();
        expect(released, isEmpty);
        player.pauseGate!.complete();
        await flushMicrotasks();
        expect(player.playing, isFalse);
        expect(released, acquired);
      },
    );

    test('source error after startup releases native priority', () async {
      await service.play(uri);
      player.emitState(
        playing: true,
        processingState: ProcessingState.ready,
        errorCode: 500,
      );
      await flushMicrotasks();
      expect(player.playing, isFalse);
      expect(released, acquired);
    });

    test(
      'an old play future failure cannot stop the replacement clip',
      () async {
        final oldResult = Completer<void>();
        player.playbackResult = oldResult;
        await service.play(uri);
        player.playbackResult = null;
        await service.play(uri);
        final current = acquired.last;
        oldResult.completeError(StateError('old decode failed'));
        await flushMicrotasks();
        expect(player.playing, isTrue);
        expect(released, isNot(contains(current)));
        await service.stop();
        expect(released, contains(current));
      },
    );

    test(
      'replacement waits for old pause and ignores its queued completion',
      () async {
        await service.play(uri);
        final first = acquired.single;
        player.pauseGate = Completer<void>();
        final next = service.play(uri);
        await flushMicrotasks();
        expect(acquired, hasLength(1));
        expect(released, isEmpty);
        player.pauseGate!.complete();
        await next;
        final second = acquired.last;
        expect(first, isNot(second));
        expect(released, [first]);
        player.emitDelayedPlayerState(
          PlayerState(true, ProcessingState.completed),
        );
        await flushMicrotasks();
        expect(released, [first]);
        await service.stop();
        expect(released, [first, second]);
      },
    );

    test('late cancelled begin cannot release the replacement token', () async {
      final delayed = Completer<bool>();
      pendingBegin = delayed;
      final first = service.play(uri);
      final cancelled = expectLater(first, throwsA(isA<PlaybackException>()));
      await flushMicrotasks();
      final oldToken = acquired.single;
      await service.stop();
      await cancelled;
      pendingBegin = null;
      await service.play(uri);
      final newToken = acquired.last;
      delayed.complete(true);
      await flushMicrotasks();
      expect(released, contains(oldToken));
      expect(released, isNot(contains(newToken)));
      expect(player.playedPaths, hasLength(1));
    });

    test(
      'dispose closes a delayed begin without starting the player',
      () async {
        final delayed = Completer<bool>();
        pendingBegin = delayed;
        final started = service.play(uri);
        final cancelled = expectLater(
          started,
          throwsA(isA<PlaybackException>()),
        );
        await flushMicrotasks();
        await service.dispose();
        await cancelled;
        delayed.complete(true);
        await flushMicrotasks();
        expect(player.playedPaths, isEmpty);
        expect(released, contains(acquired.single));
      },
    );

    test(
      'native media conflict prevents playback and cleans up its token',
      () async {
        beginError = PlatformException(code: 'EXTERNAL_MEDIA_ACTIVE');
        await expectLater(service.play(uri), throwsA(isA<PlatformException>()));
        expect(player.playedPaths, isEmpty);
        expect(released, contains(acquired.single));
      },
    );

    test('missing success acknowledgement fails closed', () async {
      beginResult = null;
      await expectLater(service.play(uri), throwsA(isA<PlaybackException>()));
      expect(player.playedPaths, isEmpty);
      expect(released, contains(acquired.single));
    });

    test('older native build without the optional API still plays', () async {
      beginError = MissingPluginException();
      await service.play(uri);
      expect(player.playedPaths, hasLength(1));
      expect(released, isEmpty);
    });
  });

  for (final recordedTake in [false, true]) {
    test(
      '${recordedTake ? "recording" : "authored clip"} source-end fallback releases audio before the next prompt',
      () async {
        final coordinator = AudioTurnCoordinator();
        addTearDown(coordinator.dispose);
        final player = ControlledPlayer();
        final cache = ControlledCache();
        final playback = JustAudioPlaybackService(
          player: player,
          cache: cache,
          audioTurnCoordinator: coordinator,
          audioTurnOwner: AudioTurnOwner.vocabulary,
        );
        final media = LessonMediaService(playbackService: playback);
        addTearDown(() async {
          await media.dispose();
          cache.dispose();
        });

        final completion = recordedTake
            ? media.playRecordedTakeToCompletion(uri)
            : media.playToCompletion(uri);
        completion.ignore();
        await cache.resolveEntered.future.timeout(const Duration(seconds: 2));
        await flushMicrotasks();
        expect(player.playedPaths, hasLength(1));
        player.emitState(
          playing: true,
          processingState: ProcessingState.ready,
          position: const Duration(milliseconds: 500),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final prompt = coordinator.acquire(
          owner: AudioTurnOwner.vocabulary,
          mode: AudioTurnMode.promptPlayback,
        );
        prompt.ignore();
        expect(coordinator.pendingCount, 1);

        // HM-D001 can finish the recording without a native completed event.
        player.emitState(
          playing: false,
          processingState: ProcessingState.ready,
          position: const Duration(seconds: 2),
        );
        await completion.timeout(const Duration(seconds: 2));
        final lease = await prompt.timeout(const Duration(milliseconds: 200));
        expect(releasedFocus, contains(acquiredFocus.last));
        await lease.release();
      },
    );
  }

  test(
    'queued old completion cannot release replacement audio leases',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final player = ControlledPlayer();
      final cache = ControlledCache();
      final service = JustAudioPlaybackService(
        player: player,
        cache: cache,
        audioTurnCoordinator: coordinator,
        audioTurnOwner: AudioTurnOwner.vocabulary,
      );
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      await service.play(uri);
      // The source emits completion now, while its derived PlayerState waits.
      player.emitState(
        playing: true,
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 2),
        publishPlayerState: false,
      );
      await flushMicrotasks();
      await service.play(uri);
      expect(acquiredFocus, hasLength(2));
      final replacementFocus = acquiredFocus.last;

      // Deliver the old state only after the new clip is genuinely playing.
      player.emitDelayedPlayerState(
        PlayerState(true, ProcessingState.completed),
      );
      await flushMicrotasks();
      expect(releasedFocus, isNot(contains(replacementFocus)));
      var promptGotTheTurn = false;
      unawaited(
        coordinator
            .acquire(
              owner: AudioTurnOwner.mainAssistant,
              mode: AudioTurnMode.promptPlayback,
            )
            .then((lease) {
              promptGotTheTurn = true;
              return lease.release();
            }),
      );
      await flushMicrotasks();
      expect(promptGotTheTurn, isFalse);

      player.emitState(
        playing: true,
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 2),
      );
      await flushMicrotasks();
      expect(releasedFocus.where((id) => id == replacementFocus), hasLength(1));
      expect(promptGotTheTurn, isTrue);
    },
  );

  test(
    'a clip completing inside play succeeds and releases only its leases',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final player = ControlledPlayer()..finishImmediately = true;
      final cache = ControlledCache();
      final service = JustAudioPlaybackService(
        player: player,
        cache: cache,
        audioTurnCoordinator: coordinator,
      );
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });
      await service.play(uri);
      await flushMicrotasks();
      expect(acquiredFocus, hasLength(1));
      expect(releasedFocus, acquiredFocus);
      final next = await coordinator
          .acquire(
            owner: AudioTurnOwner.mainAssistant,
            mode: AudioTurnMode.promptPlayback,
          )
          .timeout(const Duration(seconds: 1));
      await next.release();
    },
  );

  test(
    'stop releases native focus even when pausing the player fails',
    () async {
      final player = ControlledPlayer();
      final cache = ControlledCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });
      await service.play(uri);
      player.pauseError = StateError('native pause failed');
      await expectLater(service.stop(), throwsStateError);
      expect(releasedFocus, acquiredFocus);
      expect(releasedFocus, hasLength(1));
    },
  );

  test(
    'replaying the same clip keeps the audio turn until it really ends',
    () async {
      final coordinator = AudioTurnCoordinator();
      addTearDown(coordinator.dispose);
      final player = ControlledPlayer();
      final cache = ControlledCache();
      final service = JustAudioPlaybackService(
        player: player,
        cache: cache,
        audioTurnCoordinator: coordinator,
        audioTurnOwner: AudioTurnOwner.vocabulary,
      );
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });

      await service.play(uri);
      await flushMicrotasks();
      player.emitState(
        playing: true,
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 2),
      );
      await flushMicrotasks();

      // Same uri: the service skips setSource, so there is no loading event to
      // close the completion gate. Hold the replay open just after it has taken
      // the turn, which is the window the stale completed state lands in.
      final resolve = Completer<Uri>();
      cache.pendingResolve = resolve;
      final replay = service.play(uri);
      await flushMicrotasks();
      player.emitState(
        playing: true,
        processingState: ProcessingState.completed,
        position: const Duration(seconds: 2),
      );
      await flushMicrotasks();

      var promptGotTheTurn = false;
      unawaited(
        coordinator
            .acquire(
              owner: AudioTurnOwner.mainAssistant,
              mode: AudioTurnMode.promptPlayback,
            )
            .then((lease) {
              promptGotTheTurn = true;
              return lease.release();
            }),
      );
      await flushMicrotasks();

      expect(
        promptGotTheTurn,
        isFalse,
        reason: 'the replay still owns the turn, so a prompt must wait',
      );

      resolve.complete(uri);
      await replay;
      await flushMicrotasks();
    },
  );
}

class _IosControlledPlayer extends ControlledPlayer {
  Completer<void>? pauseGate;
  Completer<void>? playbackResult;

  @override
  Future<void> play() async {
    final result = playbackResult;
    await super.play();
    await result?.future;
  }

  @override
  Future<void> pause() async {
    await pauseGate?.future;
    await super.pause();
  }
}
