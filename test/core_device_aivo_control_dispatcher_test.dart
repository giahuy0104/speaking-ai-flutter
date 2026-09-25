import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aivo_control_dispatcher.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ActiveLearningModuleRegistry registry;
  late AivoControlDispatcher controls;
  late _Module module;
  var mainCalls = 0;
  var handledCalls = 0;
  setUp(() {
    mainCalls = 0;
    handledCalls = 0;
    registry = ActiveLearningModuleRegistry();
    module = _Module();
    controls = AivoControlDispatcher(
      registry: registry,
      platform: 'iOS',
      onModuleHandled: () => handledCalls++,
      onMain: (_) async {
        mainCalls++;
        return MainButtonActionResult.accepted;
      },
      onPause: (_) async {
        final result = await registry.execute(ActiveLearningCommand.stop);
        return result.wasHandled
            ? MainButtonActionResult.accepted
            : MainButtonActionResult.ignored;
      },
    );
  });
  tearDown(() {
    controls.dispose();
    registry.dispose();
  });

  AivoControlInput input(
    Aiv0Button button,
    Aiv0ButtonGesture gesture, {
    AivoControlSource source = AivoControlSource.virtualButton,
    int? sequence,
    String deviceId = 'test-device',
    bool actionable = true,
    String raw = '',
  }) => AivoControlInput(
    source: source,
    button: button,
    gesture: gesture,
    occurredAt: DateTime.now(),
    actionable: actionable,
    sequence: sequence,
    deviceId: deviceId,
    rawPayload: raw,
  );

  test('five proposed mappings and local-only gestures are explicit', () {
    final cases = [
      (
        Aiv0Button.main,
        Aiv0ButtonGesture.shortPress,
        AivoControlIntent.assistantOrResume,
      ),
      (
        Aiv0Button.main,
        Aiv0ButtonGesture.longPress,
        AivoControlIntent.pauseCurrent,
      ),
      (
        Aiv0Button.volumeUp,
        Aiv0ButtonGesture.longPress,
        AivoControlIntent.previousItem,
      ),
      (
        Aiv0Button.volumeDown,
        Aiv0ButtonGesture.longPress,
        AivoControlIntent.nextItem,
      ),
      (
        Aiv0Button.power,
        Aiv0ButtonGesture.shortPress,
        AivoControlIntent.replayCurrent,
      ),
      (
        Aiv0Button.volumeUp,
        Aiv0ButtonGesture.shortPress,
        AivoControlIntent.noAppAction,
      ),
      (
        Aiv0Button.volumeDown,
        Aiv0ButtonGesture.shortPress,
        AivoControlIntent.noAppAction,
      ),
      (
        Aiv0Button.power,
        Aiv0ButtonGesture.longPress,
        AivoControlIntent.noAppAction,
      ),
      (
        Aiv0Button.unknown,
        Aiv0ButtonGesture.shortPress,
        AivoControlIntent.noAppAction,
      ),
      (
        Aiv0Button.main,
        Aiv0ButtonGesture.release,
        AivoControlIntent.noAppAction,
      ),
    ];
    for (final (button, gesture, intent) in cases) {
      expect(AivoControlIntentMapper.map(button, gesture), intent);
    }
  });
  test(
    'LONG only pauses and SHORT asks MAIN before any resume command',
    () async {
      registry.register(module);
      expect(
        await controls.dispatch(
          input(Aiv0Button.main, Aiv0ButtonGesture.longPress),
        ),
        AivoControlStatus.accepted,
      );
      expect(
        await controls.dispatch(
          input(Aiv0Button.main, Aiv0ButtonGesture.longPress),
        ),
        AivoControlStatus.ignored,
      );
      expect(module.paused, isTrue);
      expect(
        await controls.dispatch(
          input(Aiv0Button.main, Aiv0ButtonGesture.shortPress),
        ),
        AivoControlStatus.accepted,
      );
      expect(module.commands, [ActiveLearningCommand.stop]);
      expect(mainCalls, 1);
    },
  );
  test(
    'physical LONG suppresses trailing SHORT until matching RELEASE',
    () async {
      registry.register(module);
      Future<AivoControlStatus> dispatch(
        Aiv0ButtonGesture gesture, {
        int? sequence = 7,
        AivoControlSource source = AivoControlSource.ble,
        String deviceId = 'test-device',
        Aiv0Button button = Aiv0Button.main,
      }) => controls.dispatch(
        input(
          button,
          gesture,
          sequence: sequence,
          source: source,
          deviceId: deviceId,
        ),
      );
      expect(
        await dispatch(Aiv0ButtonGesture.longPress),
        AivoControlStatus.accepted,
      );
      expect(
        await dispatch(Aiv0ButtonGesture.shortPress),
        AivoControlStatus.ignored,
      );
      expect(
        await dispatch(Aiv0ButtonGesture.longPress),
        AivoControlStatus.duplicate,
      );
      await dispatch(Aiv0ButtonGesture.release, deviceId: 'other-device');
      await dispatch(
        Aiv0ButtonGesture.release,
        source: AivoControlSource.androidMediaKey,
      );
      await dispatch(Aiv0ButtonGesture.release, button: Aiv0Button.volumeUp);
      expect(
        await dispatch(Aiv0ButtonGesture.shortPress),
        AivoControlStatus.ignored,
      );
      expect(module.commands, [ActiveLearningCommand.stop]);
      await dispatch(Aiv0ButtonGesture.release);
      expect(
        await dispatch(Aiv0ButtonGesture.shortPress, sequence: 8),
        AivoControlStatus.accepted,
      );
      expect(module.commands, [ActiveLearningCommand.stop]);
      expect(mainCalls, 1);
    },
  );
  test('new physical sequence rearms even when release is missing', () async {
    registry.register(module);
    await controls.dispatch(
      input(
        Aiv0Button.main,
        Aiv0ButtonGesture.longPress,
        source: AivoControlSource.ble,
        sequence: 10,
      ),
    );
    expect(
      await controls.dispatch(
        input(
          Aiv0Button.main,
          Aiv0ButtonGesture.shortPress,
          source: AivoControlSource.ble,
          sequence: 11,
        ),
      ),
      AivoControlStatus.accepted,
    );
    expect(module.commands, [ActiveLearningCommand.stop]);
    expect(mainCalls, 1);
  });
  test(
    'unsequenced held gesture expires and does not survive clock rollback',
    () async {
      controls.dispose();
      var now = DateTime(2026, 9, 19, 9);
      controls = AivoControlDispatcher(
        registry: registry,
        now: () => now,
        heldGestureTimeout: const Duration(seconds: 10),
        onMain: (_) async => MainButtonActionResult.accepted,
        onPause: (_) async => MainButtonActionResult.accepted,
      );
      final long = input(
        Aiv0Button.main,
        Aiv0ButtonGesture.longPress,
        source: AivoControlSource.ble,
      );
      final short = input(
        Aiv0Button.main,
        Aiv0ButtonGesture.shortPress,
        source: AivoControlSource.ble,
      );
      await controls.dispatch(long);
      expect(await controls.dispatch(short), AivoControlStatus.ignored);
      now = now.add(const Duration(seconds: 10));
      expect(await controls.dispatch(short), AivoControlStatus.accepted);
      await controls.dispatch(long);
      now = now.subtract(const Duration(seconds: 1));
      expect(await controls.dispatch(short), AivoControlStatus.accepted);
    },
  );
  test(
    'MAIN with no paused module invokes the existing assistant path',
    () async {
      expect(
        await controls.dispatch(
          input(Aiv0Button.main, Aiv0ButtonGesture.shortPress),
        ),
        AivoControlStatus.accepted,
      );
      expect(mainCalls, 1);
    },
  );
  test(
    'BLE and virtual equivalent inputs enter the same module command',
    () async {
      registry.register(module);
      await controls.dispatch(
        input(Aiv0Button.volumeUp, Aiv0ButtonGesture.longPress),
      );
      await controls.dispatch(
        input(
          Aiv0Button.volumeUp,
          Aiv0ButtonGesture.longPress,
          source: AivoControlSource.ble,
          sequence: 1,
        ),
      );
      expect(module.commands, [
        ActiveLearningCommand.previousItem,
        ActiveLearningCommand.previousItem,
      ]);
      expect(module.pauseCalls, 2);
    },
  );
  test(
    'duplicate sequence dispatches once and remains visible in history',
    () async {
      final event = input(
        Aiv0Button.main,
        Aiv0ButtonGesture.shortPress,
        source: AivoControlSource.ble,
        sequence: 8,
      );
      await controls.dispatch(event);
      expect(await controls.dispatch(event), AivoControlStatus.duplicate);
      expect(mainCalls, 1);
      await controls.dispatch(
        input(
          Aiv0Button.main,
          Aiv0ButtonGesture.shortPress,
          source: AivoControlSource.ble,
          sequence: 8,
          deviceId: 'second-device',
        ),
      );
      expect(mainCalls, 2);
    },
  );
  test(
    'observation mode does not execute confirmed MAIN or prove simulated buttons',
    () async {
      await controls.setDiagnosticsActive(true);
      final event = input(
        Aiv0Button.main,
        Aiv0ButtonGesture.shortPress,
        source: AivoControlSource.ble,
        raw: '01 01 07 01 FF FF 64 00 10 00 00 00',
      );
      expect(await controls.dispatch(event), AivoControlStatus.ignored);
      expect(
        controls.capability(Aiv0Button.main, Aiv0ButtonGesture.shortPress),
        AivoCapability.received,
      );
      controls.setExecuteTests(true);
      await controls.simulate(Aiv0Button.volumeUp, Aiv0ButtonGesture.longPress);
      expect(
        controls.capability(Aiv0Button.volumeUp, Aiv0ButtonGesture.longPress),
        AivoCapability.untested,
      );
      expect(mainCalls, 0);
    },
  );
  test(
    'unknown native command stays unknown and export excludes unsafe payloads',
    () async {
      await controls.dispatch(
        input(
          Aiv0Button.unknown,
          Aiv0ButtonGesture.unknown,
          source: AivoControlSource.iosRemoteCommand,
          actionable: false,
          raw: 'command=nextTrack token=secret childTranscript=hello',
        ),
      );
      expect(controls.history.single.intent, AivoControlIntent.noAppAction);
      expect(controls.exportLog(), contains('command=nextTrack'));
      expect(controls.exportLog(), isNot(contains('secret')));
      expect(controls.exportLog(), isNot(contains('hello')));
      expect(controls.exportLog(), isNot(contains('test-device')));
    },
  );
  test(
    'unknown draft packet is never interpreted with protocol flag off',
    () async {
      final event = const Aiv0DraftProtocolCodec(confirmed: false)
          .decodeButtonEvent(
            Uint8List.fromList([1, 2, 2, 0, 1, 0, 60, 0, 0, 0, 0, 0]),
          );
      expect(event.button, Aiv0Button.unknown);
      expect(
        await controls.dispatch(AivoControlInput.fromBle(event)),
        AivoControlStatus.ignored,
      );
      expect(mainCalls, 0);
    },
  );
  test('bounded RAM history and clear do not mutate lesson state', () async {
    for (var i = 0; i < 90; i++) {
      await controls.dispatch(
        input(Aiv0Button.unknown, Aiv0ButtonGesture.unknown),
      );
    }
    expect(controls.history, hasLength(80));
    controls.clearLog();
    expect(controls.history, isEmpty);
    expect(module.commands, isEmpty);
  });
  for (final command in [ActiveLearningCommand.nextItem]) {
    test(
      'obsolete $command completion cannot clear newer MAIN ownership',
      () async {
        registry.register(module);
        module.paused = command == ActiveLearningCommand.resume;
        module.commandGate = Completer<void>();
        module.gatedCommand = command;
        final pending = controls.dispatch(
          input(
            command == ActiveLearningCommand.resume
                ? Aiv0Button.main
                : Aiv0Button.volumeDown,
            command == ActiveLearningCommand.resume
                ? Aiv0ButtonGesture.shortPress
                : Aiv0ButtonGesture.longPress,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await controls.dispatch(
          input(Aiv0Button.main, Aiv0ButtonGesture.longPress),
        );
        module.commandGate!.complete();
        expect(await pending, AivoControlStatus.ignored);
        expect(handledCalls, 0);
      },
    );
  }
  test(
    'pause overtakes pending navigation and stale command never starts',
    () async {
      registry.register(module);
      module.pauseGate = Completer<void>();
      final next = controls.dispatch(
        input(Aiv0Button.volumeDown, Aiv0ButtonGesture.longPress),
      );
      await Future<void>.delayed(Duration.zero);
      // Pending pause cleanup must not make a second LONG toggle back to play.
      final pause = controls.dispatch(
        input(Aiv0Button.main, Aiv0ButtonGesture.longPress),
      );
      await pause;
      module.pauseGate!.complete();
      await next;
      expect(module.commands, isEmpty);
      expect(module.paused, isTrue);
    },
  );
  test(
    'unavailable navigation is returned without creating an assistant turn',
    () async {
      expect(
        await controls.dispatch(
          input(Aiv0Button.power, Aiv0ButtonGesture.shortPress),
        ),
        AivoControlStatus.unavailable,
      );
      expect(mainCalls, 0);
    },
  );
  testWidgets(
    'capability timeout means not received this run, not unsupported',
    (tester) async {
      controls.beginProbe(Aiv0Button.power, Aiv0ButtonGesture.shortPress);
      expect(
        controls.capability(Aiv0Button.power, Aiv0ButtonGesture.shortPress),
        AivoCapability.waiting,
      );
      await tester.pump(const Duration(seconds: 8));
      expect(
        controls.capability(Aiv0Button.power, Aiv0ButtonGesture.shortPress),
        AivoCapability.notReceived,
      );
    },
  );
}

class _Module implements ActiveLearningModuleController {
  bool paused = false;
  int pauseCalls = 0;
  Completer<void>? pauseGate;
  Completer<void>? commandGate;
  ActiveLearningCommand? gatedCommand;
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
    await pauseGate?.future;
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    commands.add(command);
    paused = command == ActiveLearningCommand.stop;
    if (command == gatedCommand) await commandGate?.future;
    return const ActiveLearningCommandResult.handled();
  }
}
