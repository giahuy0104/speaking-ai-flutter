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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final uri = Uri.parse('file:///word.mp3');

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

  test('replaying the same clip keeps the audio turn until it really ends', () async {
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
  });
}
