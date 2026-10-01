import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_state.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aivo_control_dispatcher.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:ai_speaking_flutter_app/core/session/app_flow_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_assistant_session.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_button_activation_policy.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/main_voice_assistant_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final source in [
    AivoControlSource.virtualButton,
    AivoControlSource.ble,
  ]) {
    test(
      '$source MAIN cannot restart an active question or microphone',
      () async {
        final harness = _MainHarness(withModule: true);
        addTearDown(harness.dispose);
        expect(await harness.press(source), AivoControlStatus.accepted);
        expect(harness.module.pauseCalls, 1);
        expect(harness.voiceStarts, 1);
        expect(harness.session.isActivationPending, isFalse);
        expect(harness.mainActive, isTrue);

        expect(await harness.press(source), AivoControlStatus.busy);
        expect(harness.voiceStarts, 1);
        expect(harness.module.pauseCalls, 1);
        expect(harness.module.commands, isEmpty);

        expect(
          await harness.press(source, gesture: Aiv0ButtonGesture.longPress),
          AivoControlStatus.accepted,
        );
        expect(harness.mainActive, isFalse);
        expect(harness.module.paused, isTrue);
        await harness.release(source);
        expect(await harness.press(source), AivoControlStatus.accepted);
        expect(harness.voiceStarts, 1);
        expect(harness.module.commands, [ActiveLearningCommand.resume]);
      },
    );
  }

  test(
    'BLE-ready iOS MAIN rejects missing HFP while screen uses phone',
    () async {
      final harness = _MainHarness(withModule: true)..h20Ready = false;
      addTearDown(harness.dispose);
      expect(
        await harness.press(AivoControlSource.ble),
        AivoControlStatus.busy,
      );
      expect(harness.connectionMessages, 1);
      expect(harness.voiceStarts, 0);
      expect(harness.module.pauseCalls, 0);
      expect(harness.selectedRoute, isNull);

      expect(
        await harness.press(AivoControlSource.virtualButton),
        AivoControlStatus.accepted,
      );
      expect(harness.selectedRoute, MainButtonAudioRoute.phoneMicrophone);
      expect(harness.voiceStarts, 1);
      expect(harness.module.pauseCalls, 1);
    },
  );

  test(
    'connected H20 uses the same selected route for both MAIN sources',
    () async {
      for (final source in [
        AivoControlSource.virtualButton,
        AivoControlSource.ble,
      ]) {
        final harness = _MainHarness();
        addTearDown(harness.dispose);
        expect(await harness.press(source), AivoControlStatus.accepted);
        expect(harness.selectedRoute, MainButtonAudioRoute.selectedHfp);
        // A later transport status change cannot change the source of this turn.
        harness.h20Ready = false;
        expect(await harness.press(source), AivoControlStatus.busy);
        expect(harness.selectedRoute, MainButtonAudioRoute.selectedHfp);
        expect(harness.voiceStarts, 1);
      }
    },
  );

  test(
    'Android physical MAIN still takes over a continuous wake listener',
    () async {
      final harness = _MainHarness(isIos: false)..h20Ready = false;
      addTearDown(harness.dispose);
      // Only explicit MAIN ownership blocks another MAIN. The Android wake
      // listener may be active without owning a MAIN command session.
      expect(harness.mainActive, isFalse);
      expect(
        await harness.press(AivoControlSource.ble),
        AivoControlStatus.accepted,
      );
      expect(harness.selectedRoute, MainButtonAudioRoute.selectedHfp);
      expect(harness.voiceStarts, 1);
      expect(harness.connectionMessages, 0);
    },
  );

  test(
    'physical LONG RELEASE SHORT rearms reused sequences through dispatcher',
    () async {
      final harness = _MainHarness();
      addTearDown(harness.dispose);
      for (var cycle = 0; cycle < 2; cycle++) {
        expect(
          await harness.press(
            AivoControlSource.ble,
            gesture: Aiv0ButtonGesture.longPress,
            sequence: 7,
          ),
          AivoControlStatus.accepted,
        );
        expect(
          await harness.press(AivoControlSource.ble, sequence: 7),
          AivoControlStatus.ignored,
        );
        await harness.release(AivoControlSource.ble, sequence: 7);
        expect(
          await harness.press(AivoControlSource.ble, sequence: 7),
          AivoControlStatus.accepted,
        );
      }
      expect(harness.voiceStarts, 2);
      expect(harness.pauseCalls, 2);
    },
  );

  testWidgets(
    'screen LONG stops while short is disabled and releases without a tap',
    (tester) async {
      final voice = _VoiceState()..mainActive = true;
      final audio = _AudioState();
      final speaking = MainSpeakingSessionController();
      addTearDown(voice.dispose);
      addTearDown(audio.dispose);
      addTearDown(speaking.dispose);
      var shortCalls = 0;
      var longCalls = 0;
      var releaseCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            floatingActionButton: MainVoiceAssistantButton(
              voiceController: voice,
              audioState: audio,
              speakingSessionController: speaking,
              isActivationPending: false,
              onPressed: () async => shortCalls++,
              onLongPressed: () async => longCalls++,
              onLongPressReleased: () async => releaseCalls++,
            ),
          ),
        ),
      );
      final button = find.byKey(const Key('main-voice-assistant-button'));
      expect(tester.widget<FloatingActionButton>(button).onPressed, isNull);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 1499));
      expect(longCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(longCalls, 1);
      await gesture.up();
      await tester.pump();
      expect(shortCalls, 0);
      expect(releaseCalls, 1);
      voice.mainActive = false;
      voice.notifyListeners();
      await tester.pump();
      await tester.tap(button);
      expect(shortCalls, 1);
      expect(longCalls, 1);
    },
  );
}

class _MainHarness {
  _MainHarness({this.isIos = true, bool withModule = false}) {
    if (withModule) registry.register(module);
    flow = AppFlowCoordinator(registry: registry);
    session = MainAssistantSession(appFlowCoordinator: flow);
    coordinator = MainButtonCoordinator(
      onScreenShortPress: _activate,
      onBleShortPress: _activate,
      onLongPress: _pause,
    );
    dispatcher = AivoControlDispatcher(
      registry: registry,
      platform: isIos ? 'iOS' : 'Android',
      canResume: () => !mainActive && !session.isActivationPending,
      onMain: coordinator.handle,
      onPause: _pause,
    );
  }

  final bool isIos;
  final registry = ActiveLearningModuleRegistry();
  final module = _Module();
  late final AppFlowCoordinator flow;
  late final MainAssistantSession session;
  late final MainButtonCoordinator coordinator;
  late final AivoControlDispatcher dispatcher;
  bool h20Ready = true;
  bool mainActive = false;
  int voiceStarts = 0;
  int pauseCalls = 0;
  int connectionMessages = 0;
  int _packetUptime = 0;
  MainButtonAudioRoute? selectedRoute;

  Future<MainButtonActionResult> _activate(MainButtonInputEvent event) async {
    if (!MainButtonActivationPolicy.canStart(
      isActivationPending: session.isActivationPending,
      isMainButtonSessionActive: mainActive,
    )) {
      return MainButtonActionResult.busy;
    }
    final route = MainButtonActivationPolicy.audioRoute(
      source: event.source,
      isNativeMobile: true,
      isIos: isIos,
      isH20Ready: h20Ready,
    );
    if (route == MainButtonAudioRoute.unavailable) {
      connectionMessages++;
      return MainButtonActionResult.busy;
    }
    selectedRoute = route;
    final activated = await session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: false,
      assistantFlowBusy: false,
      mainButtonSessionActive: mainActive,
      canContinue: () => true,
      activateVoice:
          ({required activeLearning, required activeLearningKind}) async {
            voiceStarts++;
            mainActive = true;
            return true;
          },
    );
    return activated
        ? MainButtonActionResult.accepted
        : MainButtonActionResult.busy;
  }

  Future<MainButtonActionResult> _pause(MainButtonInputEvent _) async {
    session.cancelForNavigation();
    mainActive = false;
    pauseCalls++;
    return MainButtonActionResult.accepted;
  }

  Future<AivoControlStatus> press(
    AivoControlSource source, {
    Aiv0ButtonGesture gesture = Aiv0ButtonGesture.shortPress,
    int? sequence,
  }) => dispatcher.dispatch(
    AivoControlInput(
      source: source,
      button: Aiv0Button.main,
      gesture: gesture,
      occurredAt: DateTime.now(),
      actionable: true,
      deviceId: 'H20',
      sequence: sequence,
      uptimeMilliseconds: ++_packetUptime,
    ),
  );

  Future<void> release(AivoControlSource source, {int? sequence}) async {
    if (source == AivoControlSource.virtualButton) {
      await coordinator.handle(
        const MainButtonInputEvent(
          source: MainButtonSource.screen,
          gesture: MainButtonGesture.release,
        ),
      );
    } else {
      await press(
        source,
        gesture: Aiv0ButtonGesture.release,
        sequence: sequence,
      );
    }
  }

  void dispose() {
    dispatcher.dispose();
    registry.dispose();
  }
}

class _Module implements ActiveLearningModuleController {
  bool paused = false;
  int pauseCalls = 0;
  final commands = <ActiveLearningCommand>[];
  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;
  @override
  bool get isPausedForMain => paused;
  @override
  Future<void> pauseForMainAssistant() async {
    pauseCalls++;
    paused = true;
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    commands.add(command);
    if (command == ActiveLearningCommand.resume) paused = false;
    return const ActiveLearningCommandResult.handled();
  }
}

class _VoiceState extends ChangeNotifier implements VoiceNavigationController {
  bool mainActive = false;
  @override
  bool get isMainButtonSessionActive => mainActive;
  @override
  bool get isAcknowledgingWakeWord => false;
  @override
  bool get isListening => mainActive;
  @override
  bool get isStarting => false;
  @override
  bool get isAwaitingCommand => mainActive;
  @override
  String get activeInputLabel => 'H20';
  @override
  String? get lastErrorMessage => null;
  @override
  bool get hasUnhandledLearningCommandError => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AudioState extends ChangeNotifier implements MainAssistantAudioState {
  @override
  bool get isBusy => false;
  @override
  bool get isPlaybackPlaying => false;
  @override
  bool get isPreparingMicrophone => false;
}
