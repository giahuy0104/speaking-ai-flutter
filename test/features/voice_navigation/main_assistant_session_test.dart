import 'dart:async';

import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/session/app_flow_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_assistant_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'external translation handoff stays cancelled after a newer MAIN starts',
    () {
      final harness = _SessionHarness(module: _FakeActiveModule());
      addTearDown(harness.dispose);
      final oldHandoff = harness.session.captureCancellationGuard();
      harness.session.setExternalActivation(true);
      expect(oldHandoff(), isTrue);
      harness.session.cancelForNavigation();
      final newHandoff = harness.session.captureCancellationGuard();
      harness.session.setExternalActivation(true);
      expect(oldHandoff(), isFalse);
      expect(newHandoff(), isTrue);
      if (oldHandoff()) harness.session.setExternalActivation(false);
      expect(harness.session.isActivationPending, isTrue);
    },
  );
  test(
    'cancel during preparation cannot pause or activate a stale MAIN',
    () async {
      final module = _FakeActiveModule();
      final harness = _SessionHarness(module: module);
      addTearDown(harness.dispose);
      final oldPreparation = Completer<bool>();
      final newPreparation = Completer<bool>();
      var voiceCalls = 0;
      Future<bool> activate(Completer<bool> preparation) =>
          harness.session.activate(
            startupReady: true,
            voiceAccessEnabled: true,
            conversationBusy: false,
            assistantFlowBusy: false,
            canContinue: () => true,
            prepareActivation: () => preparation.future,
            activateVoice:
                ({required activeLearning, activeLearningKind}) async {
                  voiceCalls++;
                  return true;
                },
          );
      final oldActivation = activate(oldPreparation);
      expect(harness.session.isActivationPending, isTrue);
      expect(module.pauseCount, 0);
      harness.session.cancelForNavigation();
      final newActivation = activate(newPreparation);
      oldPreparation.complete(true);
      expect(await oldActivation, isFalse);
      expect(harness.session.isActivationPending, isTrue);
      expect(module.pauseCount, 0);
      expect(voiceCalls, 0);
      newPreparation.complete(true);
      expect(await newActivation, isTrue);
      expect(module.pauseCount, 1);
      expect(voiceCalls, 1);
      expect(harness.session.isActivationPending, isFalse);
      expect(harness.activationStates, [true, false, true, false]);
    },
  );

  for (final preparationSucceeded in <bool>[false, true]) {
    test(
      'preparation result $preparationSucceeded respects current lifecycle',
      () async {
        final module = _FakeActiveModule();
        final harness = _SessionHarness(module: module);
        addTearDown(harness.dispose);
        final preparation = Completer<bool>();
        var current = true;
        var voiceCalls = 0;
        final activation = harness.session.activate(
          startupReady: true,
          voiceAccessEnabled: true,
          conversationBusy: false,
          assistantFlowBusy: false,
          canContinue: () => current,
          prepareActivation: () => preparation.future,
          activateVoice: ({required activeLearning, activeLearningKind}) async {
            voiceCalls++;
            return true;
          },
        );
        // A false preparation must stop by itself. A true preparation must also
        // stop if the owner was disposed/navigated while the route was settling.
        if (preparationSucceeded) current = false;
        preparation.complete(preparationSucceeded);
        expect(await activation, isFalse);
        expect(module.pauseCount, 0);
        expect(voiceCalls, 0);
        expect(harness.session.isActivationPending, isFalse);
      },
    );
  }

  test(
    'Back invalidates pending MAIN takeover without resuming the exited module',
    () async {
      final gate = Completer<void>();
      final module = _FakeActiveModule()..pauseGate = gate.future;
      final harness = _SessionHarness(module: module);
      addTearDown(harness.dispose);
      var voiceCalls = 0;
      final activation = harness.session.activate(
        startupReady: true,
        voiceAccessEnabled: true,
        conversationBusy: false,
        assistantFlowBusy: false,
        canContinue: () => true,
        activateVoice: ({required activeLearning, activeLearningKind}) async {
          voiceCalls++;
          return true;
        },
      );
      harness.session.cancelForNavigation();
      gate.complete();
      expect(await activation, isFalse);
      expect(voiceCalls, 0);
      expect(harness.session.isActivationPending, isFalse);
      expect(harness.coordinator.activeModulePausedForMain, isFalse);
      expect(module.commands, isEmpty);
    },
  );
  test('rejects MAIN while conversation owns audio outside learning', () async {
    final harness = _SessionHarness();
    addTearDown(harness.dispose);
    var activationCalls = 0;

    final activated = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: true,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        activationCalls += 1;
        return true;
      },
    );

    expect(activated, isFalse);
    expect(activationCalls, 0);
    expect(harness.activationStates, isEmpty);
  });

  test('pauses learning before activating MAIN with typed context', () async {
    final module = _FakeActiveModule(kind: ActiveLearningModuleKind.vocabulary);
    final harness = _SessionHarness(module: module);
    addTearDown(harness.dispose);
    final events = <String>[];

    final activated = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: true,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        events.add('activate');
        expect(module.isPausedForMain, isTrue);
        expect(activeLearning, isTrue);
        expect(activeLearningKind, ActiveLearningModuleKind.vocabulary);
        return true;
      },
    );

    expect(activated, isTrue);
    expect(module.pauseCount, 1);
    expect(events, <String>['activate']);
    expect(harness.activationStates, <bool>[true, false]);
  });

  test(
    'failed MAIN activation keeps learning paused until a real command',
    () async {
      final module = _FakeActiveModule();
      final harness = _SessionHarness(module: module);
      addTearDown(harness.dispose);

      final activated = await harness.session.activate(
        startupReady: true,
        voiceAccessEnabled: true,
        conversationBusy: false,
        assistantFlowBusy: false,
        canContinue: () => true,
        activateVoice: ({required activeLearning, activeLearningKind}) async {
          return false;
        },
      );

      expect(activated, isFalse);
      expect(module.commands, isEmpty);
      expect(module.isPausedForMain, isTrue);
      expect(harness.coordinator.activeModulePausedForMain, isTrue);
    },
  );

  test('serializes repeated MAIN activation attempts', () async {
    final harness = _SessionHarness();
    addTearDown(harness.dispose);
    final gate = Completer<bool>();
    var activationCalls = 0;

    final first = harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: false,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) {
        activationCalls += 1;
        return gate.future;
      },
    );
    await Future<void>.delayed(Duration.zero);
    final second = await harness.session.activate(
      startupReady: true,
      voiceAccessEnabled: true,
      conversationBusy: false,
      assistantFlowBusy: false,
      canContinue: () => true,
      activateVoice: ({required activeLearning, activeLearningKind}) async {
        activationCalls += 1;
        return true;
      },
    );

    expect(second, isFalse);
    expect(activationCalls, 1);
    gate.complete(true);
    expect(await first, isTrue);
    expect(harness.activationStates, <bool>[true, false]);
  });
}

class _SessionHarness {
  _SessionHarness({_FakeActiveModule? module})
    : registry = ActiveLearningModuleRegistry() {
    if (module != null) registry.register(module);
    coordinator = AppFlowCoordinator(registry: registry);
    session = MainAssistantSession(
      appFlowCoordinator: coordinator,
      onActivationChanged: activationStates.add,
    );
  }

  final ActiveLearningModuleRegistry registry;
  late final AppFlowCoordinator coordinator;
  late final MainAssistantSession session;
  final List<bool> activationStates = <bool>[];

  void dispose() => registry.dispose();
}

class _FakeActiveModule implements ActiveLearningModuleController {
  _FakeActiveModule({this.kind = ActiveLearningModuleKind.listeningLesson});

  final ActiveLearningModuleKind kind;
  int pauseCount = 0;
  bool paused = false;
  Future<void>? pauseGate;
  final List<ActiveLearningCommand> commands = <ActiveLearningCommand>[];

  @override
  ActiveLearningModuleKind get moduleKind => kind;

  @override
  bool get isPausedForMain => paused;

  @override
  Future<void> pauseForMainAssistant() async {
    pauseCount += 1;
    paused = true;
    await pauseGate;
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
