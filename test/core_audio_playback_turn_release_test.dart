import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
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
