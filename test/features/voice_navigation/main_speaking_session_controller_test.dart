import 'dart:async';

import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exits speaking mode after ten seconds of waiting for Main', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.enter();
    expect(controller.state, MainSpeakingSessionState.ready);

    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(controller.state, MainSpeakingSessionState.inactive);
    expect(controller.isActive, isFalse);
  });

  test('suspends idle timeout while a speaking turn is active', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);

    controller.enter();
    controller.synchronize(isRecording: true, isBusy: true, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.recording);

    controller.synchronize(isRecording: false, isBusy: true, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.processing);

    controller.synchronize(isRecording: false, isBusy: false, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.playing);

    controller.synchronize(isRecording: false, isBusy: false, isPlaying: false);
    expect(controller.state, MainSpeakingSessionState.ready);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.inactive);
  });

  test('repeated synchronization does not extend the ready timeout', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);

    controller.enter();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.synchronize(isRecording: false, isBusy: false, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.state, MainSpeakingSessionState.inactive);
  });

  test('retries the first silent turn and exits after the second', () {
    final controller = MainSpeakingSessionController();
    addTearDown(controller.dispose);

    controller.enter();
    expect(controller.registerNoSpeechTurn(), MainSpeakingNoSpeechAction.retry);
    expect(controller.consecutiveNoSpeechTurns, 1);
    expect(controller.registerNoSpeechTurn(), MainSpeakingNoSpeechAction.exit);
    expect(controller.consecutiveNoSpeechTurns, 2);
  });

  test('a successful turn resets the consecutive silence count', () {
    final controller = MainSpeakingSessionController();
    addTearDown(controller.dispose);

    controller.enter();
    controller.registerNoSpeechTurn();
    controller.markSpeechTurnCompleted();

    expect(controller.consecutiveNoSpeechTurns, 0);
    expect(controller.registerNoSpeechTurn(), MainSpeakingNoSpeechAction.retry);
  });

  test('re-opens the mic after two failed turns in a row, then exits', () {
    final controller = MainSpeakingSessionController();
    addTearDown(controller.dispose);

    controller.enter();
    expect(controller.registerFailedTurn(), MainSpeakingFailedTurnAction.retry);
    expect(controller.registerFailedTurn(), MainSpeakingFailedTurnAction.retry);
    expect(controller.registerFailedTurn(), MainSpeakingFailedTurnAction.exit);
    expect(controller.consecutiveFailedTurns, 3);
  });

  test('a successful turn or a new session resets failed turns', () {
    final controller = MainSpeakingSessionController();
    addTearDown(controller.dispose);

    controller.enter();
    controller.registerFailedTurn();
    controller.registerFailedTurn();
    controller.markSpeechTurnCompleted();
    expect(controller.consecutiveFailedTurns, 0);

    controller.registerFailedTurn();
    controller.exit();
    controller.enter();
    expect(controller.consecutiveFailedTurns, 0);
    expect(controller.registerFailedTurn(), MainSpeakingFailedTurnAction.retry);
  });

  test('an inactive session never retries a failed turn', () {
    final controller = MainSpeakingSessionController();
    addTearDown(controller.dispose);

    expect(controller.registerFailedTurn(), MainSpeakingFailedTurnAction.exit);
  });

  test(
    'physical MAIN cancels translation before opening the assistant',
    () async {
      final controller = MainSpeakingSessionController();
      final events = <String>[];
      controller.enter();

      final activated = await controller.interruptForMainAssistant(
        cancelCurrentAction: () async {
          events.add('cancel');
          return true;
        },
        activateAssistant: () async {
          events.add('assistant');
          return true;
        },
      );

      expect(activated, isTrue);
      expect(controller.isActive, isFalse);
      expect(events, <String>['cancel', 'assistant']);
      controller.dispose();
    },
  );

  test('does not open assistant until current capture is cancelled', () async {
    final controller = MainSpeakingSessionController();
    var assistantCalls = 0;
    var cancellationCalls = 0;
    controller.enter();

    Future<bool> interrupt() => controller.interruptForMainAssistant(
      cancelCurrentAction: () async {
        cancellationCalls += 1;
        return false;
      },
      activateAssistant: () async {
        assistantCalls += 1;
        return true;
      },
    );

    final firstActivation = await interrupt();
    final secondActivation = await interrupt();

    expect(firstActivation, isFalse);
    expect(secondActivation, isFalse);
    expect(cancellationCalls, 2);
    expect(assistantCalls, 0);
    expect(controller.isActive, isTrue);
    controller.dispose();
  });

  test(
    'inactive speaking mode ignores a MAIN assistant interruption',
    () async {
      final controller = MainSpeakingSessionController();
      addTearDown(controller.dispose);
      var cancellationCalls = 0;
      var assistantCalls = 0;

      final activated = await controller.interruptForMainAssistant(
        cancelCurrentAction: () async {
          cancellationCalls++;
          return true;
        },
        activateAssistant: () async {
          assistantCalls++;
          return true;
        },
      );

      expect(activated, isFalse);
      expect(cancellationCalls, 0);
      expect(assistantCalls, 0);
      expect(controller.state, MainSpeakingSessionState.inactive);
    },
  );

  test(
    'closing a session during cancellation does not open assistant',
    () async {
      final controller = MainSpeakingSessionController();
      final cancellation = Completer<bool>();
      var assistantCalls = 0;
      controller.enter();

      final pending = controller.interruptForMainAssistant(
        cancelCurrentAction: () => cancellation.future,
        activateAssistant: () async {
          assistantCalls++;
          return true;
        },
      );

      controller.dispose();
      cancellation.complete(true);

      expect(await pending, isFalse);
      expect(assistantCalls, 0);
    },
  );

  test('MAIN interrupts recording, processing, and playback states', () async {
    final states = <MainSpeakingSessionState>[
      MainSpeakingSessionState.recording,
      MainSpeakingSessionState.processing,
      MainSpeakingSessionState.playing,
    ];

    for (final state in states) {
      final controller = MainSpeakingSessionController();
      final events = <String>[];
      controller.enter();
      controller.synchronize(
        isRecording: state == MainSpeakingSessionState.recording,
        isBusy: state == MainSpeakingSessionState.processing,
        isPlaying: state == MainSpeakingSessionState.playing,
      );

      final activated = await controller.interruptForMainAssistant(
        cancelCurrentAction: () async {
          events.add('cancel');
          return true;
        },
        activateAssistant: () async {
          events.add('assistant');
          return true;
        },
      );

      expect(activated, isTrue, reason: '$state');
      expect(controller.state, MainSpeakingSessionState.inactive);
      expect(events, <String>['cancel', 'assistant']);
      controller.dispose();
    }
  });
}
