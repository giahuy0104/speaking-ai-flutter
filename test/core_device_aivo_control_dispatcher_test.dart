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
  var canResume = true;
  setUp(() {
    mainCalls = 0;
    handledCalls = 0;
    canResume = true;
    registry = ActiveLearningModuleRegistry();
    module = _Module();
    controls = AivoControlDispatcher(
      registry: registry,
      platform: 'iOS',
      canResume: () => canResume,
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
    'LONG only pauses, SHORT resumes once instead of starting assistant',
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
      expect(module.commands, [
        ActiveLearningCommand.stop,
        ActiveLearningCommand.resume,
      ]);
      expect(mainCalls, 0);
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
      expect(module.commands, [
        ActiveLearningCommand.stop,
        ActiveLearningCommand.resume,
      ]);
      expect(mainCalls, 0);
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
    expect(module.commands, [
      ActiveLearningCommand.stop,
      ActiveLearningCommand.resume,
    ]);
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
  test('observed HM-D001 packets reach the active lesson commands', () async {
    registry.register(module);
    const codec = Aiv0DraftProtocolCodec(confirmed: false);
    for (final raw in <List<int>>[
      <int>[1, 4, 2, 0, 0x1E, 0, 79, 0, 0x82, 0x7B, 0x0C, 0],
      <int>[1, 3, 2, 0, 0x1F, 0, 79, 0, 0xFC, 0x97, 0x0C, 0],
      <int>[1, 1, 2, 0, 0x20, 0, 79, 0, 0, 0xA0, 0x0C, 0],
      <int>[1, 1, 1, 0, 0x21, 0, 79, 0, 0, 0xB0, 0x0C, 0],
      <int>[1, 2, 1, 0, 0x29, 0, 0x47, 0, 0xF1, 0x60, 0x36, 0],
    ]) {
      final event = codec.decodeButtonEvent(Uint8List.fromList(raw));
      expect(
        await controls.dispatch(AivoControlInput.fromBle(event)),
        AivoControlStatus.accepted,
      );
    }
    expect(module.commands, <ActiveLearningCommand>[
      ActiveLearningCommand.nextItem,
      ActiveLearningCommand.previousItem,
      ActiveLearningCommand.stop,
      ActiveLearningCommand.resume,
      ActiveLearningCommand.replayCurrent,
    ]);
    expect(mainCalls, 0);
  });
  test(
    'observed H20 item packets cannot play lesson audio while MAIN owns speech',
    () async {
      registry.register(module);
      module.paused = true;
      canResume = false;
      const codec = Aiv0DraftProtocolCodec(confirmed: false);
      for (final raw in <List<int>>[
        <int>[1, 4, 2, 0, 0x1E, 0, 79, 0, 0x82, 0x7B, 0x0C, 0],
        <int>[1, 3, 2, 0, 0x1F, 0, 79, 0, 0xFC, 0x97, 0x0C, 0],
        <int>[1, 2, 1, 0, 0x29, 0, 0x47, 0, 0xF1, 0x60, 0x36, 0],
      ]) {
        final event = codec.decodeButtonEvent(Uint8List.fromList(raw));
        expect(
          await controls.dispatch(AivoControlInput.fromBle(event)),
          AivoControlStatus.busy,
        );
        expect(
          controls.capability(event.button, event.gesture),
          AivoCapability.received,
        );
      }
      expect(module.commands, isEmpty);
      expect(module.pauseCalls, 0);
      expect(module.paused, isTrue);
      expect(handledCalls, 0);
      expect(mainCalls, 0);
    },
  );
  for (final (button, gesture, command) in [
    (
      Aiv0Button.volumeUp,
      Aiv0ButtonGesture.longPress,
      ActiveLearningCommand.previousItem,
    ),
    (
      Aiv0Button.volumeDown,
      Aiv0ButtonGesture.longPress,
      ActiveLearningCommand.nextItem,
    ),
    (
      Aiv0Button.power,
      Aiv0ButtonGesture.shortPress,
      ActiveLearningCommand.replayCurrent,
    ),
  ]) {
    test('$command waits for MAIN then remains available after STOP', () async {
      registry.register(module);
      module.paused = true;
      canResume = false;
      expect(
        await controls.dispatch(input(button, gesture)),
        AivoControlStatus.busy,
      );
      expect(module.commands, isEmpty);
      canResume = true;
      expect(
        await controls.dispatch(input(button, gesture)),
        AivoControlStatus.accepted,
      );
      expect(module.commands, [command]);
      expect(module.paused, isFalse);
      expect(handledCalls, 1);
      expect(mainCalls, 0);
    });
  }
  test(
    'MAIN starting during item cleanup blocks the pending playback command',
    () async {
      registry.register(module);
      module.pauseGate = Completer<void>();
      final pending = controls.dispatch(
        input(Aiv0Button.volumeDown, Aiv0ButtonGesture.longPress),
      );
      await Future<void>.delayed(Duration.zero);
      expect(module.pauseCalls, 1);
      canResume = false;
      module.pauseGate!.complete();
      expect(await pending, AivoControlStatus.busy);
      expect(module.commands, isEmpty);
      expect(module.paused, isTrue);
      expect(handledCalls, 0);
    },
  );
  test('H20 STOP remains available while MAIN owns a paused lesson', () async {
    registry.register(module);
    module.paused = true;
    canResume = false;
    expect(
      await controls.dispatch(
        input(Aiv0Button.main, Aiv0ButtonGesture.longPress),
      ),
      AivoControlStatus.accepted,
    );
    expect(module.commands, [ActiveLearningCommand.stop]);
  });
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
  for (final command in [
    ActiveLearningCommand.resume,
    ActiveLearningCommand.nextItem,
  ]) {
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
