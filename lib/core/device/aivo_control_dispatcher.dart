import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/audio_diagnostics.dart';
import 'active_learning_module.dart';
import 'aiv0_ble_control.dart';
import 'main_button_coordinator.dart';

enum AivoControlSource {
  ble,
  androidMediaKey,
  iosRemoteCommand,
  virtualButton,
  simulation,
}

enum AivoControlIntent {
  assistantOrResume,
  pauseCurrent,
  previousItem,
  nextItem,
  replayCurrent,
  noAppAction,
}

enum AivoControlStatus {
  accepted,
  ignored,
  unavailable,
  duplicate,
  busy,
  failed,
}

enum AivoCapability { untested, waiting, received, notReceived }

class AivoControlInput {
  const AivoControlInput({
    required this.source,
    required this.button,
    required this.gesture,
    required this.occurredAt,
    this.sequence,
    this.deviceId,
    this.uptimeMilliseconds,
    this.rawPayload = '',
    this.protocol = 'unknown',
    this.actionable = false,
    this.duplicate = false,
  });

  factory AivoControlInput.fromBle(Aiv0ButtonEvent event) => AivoControlInput(
    source: switch (event.transportSource) {
      'androidMediaKey' => AivoControlSource.androidMediaKey,
      'iosRemoteCommand' => AivoControlSource.iosRemoteCommand,
      _ => AivoControlSource.ble,
    },
    button: event.button,
    gesture: event.gesture,
    occurredAt: event.receivedAt,
    sequence: event.sequence,
    deviceId: event.deviceId,
    uptimeMilliseconds: event.uptimeMilliseconds,
    rawPayload: event.rawDescription ?? event.rawHex,
    protocol: event.isObservedH20Packet
        ? 'observedV1'
        : event.isDraftPacket
        ? 'draft'
        : 'unknown',
    actionable: event.isActionable,
    duplicate: event.isDuplicate,
  );

  final AivoControlSource source;
  final Aiv0Button button;
  final Aiv0ButtonGesture gesture;
  final DateTime occurredAt;
  final int? sequence;
  final int? uptimeMilliseconds;
  final String? deviceId;
  final String rawPayload;
  final String protocol;
  final bool actionable;
  final bool duplicate;
  bool get isPhysical =>
      source != AivoControlSource.virtualButton &&
      source != AivoControlSource.simulation;
}

abstract final class AivoControlIntentMapper {
  static AivoControlIntent map(Aiv0Button button, Aiv0ButtonGesture gesture) =>
      switch ((button, gesture)) {
        (Aiv0Button.main, Aiv0ButtonGesture.shortPress) =>
          AivoControlIntent.assistantOrResume,
        (Aiv0Button.main, Aiv0ButtonGesture.longPress) =>
          AivoControlIntent.pauseCurrent,
        (Aiv0Button.volumeUp, Aiv0ButtonGesture.longPress) =>
          AivoControlIntent.previousItem,
        (Aiv0Button.volumeDown, Aiv0ButtonGesture.longPress) =>
          AivoControlIntent.nextItem,
        (Aiv0Button.power, Aiv0ButtonGesture.shortPress) =>
          AivoControlIntent.replayCurrent,
        _ => AivoControlIntent.noAppAction,
      };
}

class AivoControlRecord {
  const AivoControlRecord({
    required this.input,
    required this.intent,
    required this.status,
    required this.before,
    required this.after,
    required this.platform,
  });
  final AivoControlInput input;
  final AivoControlIntent intent;
  final AivoControlStatus status;
  final String before;
  final String after;
  final String platform;
  String get logLine =>
      '${input.occurredAt.toIso8601String()} platform=$platform '
      'source=${input.source.name} button=${input.button.name} gesture=${input.gesture.name} '
      'protocol=${input.protocol} seq=${input.sequence ?? "-"} raw=$safeRawPayload '
      'intent=${intent.name} result=${status.name} state=$before->$after';

  String get safeRawPayload {
    if (input.source == AivoControlSource.ble) {
      return RegExp(r'^(?:[0-9A-Fa-f]{2}(?: |$))*$').hasMatch(input.rawPayload)
          ? input.rawPayload
          : '[redacted]';
    }
    if (!input.isPhysical) return '';
    final tokens = input.rawPayload.split(' ');
    const commands = {
      'play',
      'pause',
      'togglePlayPause',
      'nextTrack',
      'previousTrack',
      'stop',
      'next',
      'previous',
      'playPause',
      'headsetHook',
      'fastForward',
      'rewind',
      'volumeUp',
      'volumeDown',
    };
    return tokens
        .where(
          (token) =>
              RegExp(
                r'^(keyCode|action|repeatCount|holdDurationMs)=-?\d+$',
              ).hasMatch(token) ||
              token.startsWith('command=') &&
                  commands.contains(token.substring(8)),
        )
        .join(' ');
  }
}

/// Single business dispatcher; native only reports observed input. Keeps no
/// recordings, transcripts, tokens, or device identifiers in exported logs.
class AivoControlDispatcher extends ChangeNotifier {
  AivoControlDispatcher({
    required this.registry,
    required this.onMain,
    required this.onPause,
    this.onContextChanged,
    this.canResume,
    this.canExecute,
    this.onModuleHandled,
    this.platform = 'unknown',
    this.operationTimeout = const Duration(seconds: 5),
    this.heldGestureTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ActiveLearningModuleRegistry registry;
  final MainButtonAction onMain;
  final MainButtonAction onPause;
  final bool Function()? canResume;
  final bool Function()? canExecute;
  final VoidCallback? onModuleHandled;
  final Future<void> Function(bool learningActive, bool diagnosticsActive)?
  onContextChanged;
  final String platform;
  final Duration operationTimeout;
  final Duration heldGestureTimeout;
  final DateTime Function() _now;
  final List<AivoControlRecord> _history = [];
  final Map<String, DateTime> _seen = {};
  final Map<
    (AivoControlSource, String?, Aiv0Button),
    ({int? sequence, DateTime startedAt})
  >
  _heldGestures = {};
  final Map<String, AivoCapability> _capabilities = {};
  final Map<String, Timer> _probes = {};
  bool diagnosticsActive = false;
  bool executeTests = false;
  bool _busy = false;
  int _busyTicket = 0;
  bool _disposed = false;
  int _generation = 0;

  List<AivoControlRecord> get history => List.unmodifiable(_history);
  String get state => registry.hasActiveModule
      ? registry.isActiveModulePaused
            ? 'paused'
            : 'active'
      : 'idle';
  static String capabilityKey(Aiv0Button button, Aiv0ButtonGesture gesture) =>
      '${button.name}:${gesture.name}';
  AivoCapability capability(Aiv0Button button, Aiv0ButtonGesture gesture) =>
      _capabilities[capabilityKey(button, gesture)] ?? AivoCapability.untested;

  void beginProbe(Aiv0Button button, Aiv0ButtonGesture gesture) {
    if (_disposed) return;
    final key = capabilityKey(button, gesture);
    _probes.remove(key)?.cancel();
    _capabilities[key] = AivoCapability.waiting;
    _probes[key] = Timer(const Duration(seconds: 8), () {
      if (_disposed) return;
      _capabilities[key] = AivoCapability.notReceived;
      _probes.remove(key);
      notifyListeners();
    });
    notifyListeners();
  }

  void clearLog() {
    if (_disposed) return;
    _history.clear();
    notifyListeners();
  }

  String exportLog() =>
      _history.reversed.map((entry) => entry.logLine).join('\n');

  Future<void> setDiagnosticsActive(bool active) async {
    if (_disposed) return;
    diagnosticsActive = active;
    executeTests = false;
    notifyListeners();
    await syncNativeContext();
  }

  void setExecuteTests(bool value) {
    if (_disposed) return;
    executeTests = value;
    notifyListeners();
  }

  Future<void> syncNativeContext() async {
    if (_disposed) return;
    try {
      await onContextChanged?.call(registry.hasActiveModule, diagnosticsActive);
    } catch (_) {
      /* Diagnostics cannot block learning if a bridge is unavailable. */
    }
  }

  Future<AivoControlStatus> simulate(
    Aiv0Button button,
    Aiv0ButtonGesture gesture,
  ) => dispatch(
    AivoControlInput(
      source: AivoControlSource.simulation,
      button: button,
      gesture: gesture,
      occurredAt: DateTime.now(),
      protocol: 'simulation',
      actionable: true,
    ),
  );

  Future<AivoControlStatus> dispatch(AivoControlInput input) async {
    if (_disposed) return AivoControlStatus.ignored;
    final intent = AivoControlIntentMapper.map(input.button, input.gesture);
    final before = state;
    final diagnosticOperation = AudioDiagnostics.nextId();
    AudioDiagnostics.event('aivo.dispatch.received', {
      'operation': diagnosticOperation,
      'dispatcherGeneration': _generation,
      'ownerGeneration': registry.diagnosticOwnerGeneration,
      'source': input.source.name,
      'button': input.button.name,
      'gesture': input.gesture.name,
      'sequence': input.sequence,
      'intent': intent.name,
      'actionable': input.actionable,
      'duplicate': input.duplicate,
    });
    AivoControlStatus finish(AivoControlStatus status) {
      AudioDiagnostics.event('aivo.dispatch.completed', {
        'operation': diagnosticOperation,
        'dispatcherGeneration': _generation,
        'ownerGeneration': registry.diagnosticOwnerGeneration,
        'intent': intent.name,
        'status': status.name,
        'activeKind': registry.activeKind?.name,
        'paused': registry.isActiveModulePaused,
      });
      if (!_disposed) {
        _history.insert(
          0,
          AivoControlRecord(
            input: input,
            intent: intent,
            status: status,
            before: before,
            after: state,
            platform: platform,
          ),
        );
        _history.sort(
          (a, b) => b.input.occurredAt.compareTo(a.input.occurredAt),
        );
        if (_history.length > 80) _history.removeRange(80, _history.length);
        notifyListeners();
      }
      return status;
    }

    if (input.duplicate) return finish(AivoControlStatus.duplicate);
    final heldGestureResult = _handleHeldGesture(input);
    if (heldGestureResult != null) return finish(heldGestureResult);
    if (input.isPhysical && input.sequence != null) {
      final now = _now();
      _seen.removeWhere(
        (_, at) => now.difference(at) > const Duration(seconds: 3),
      );
      final key =
          '${input.source.name}:${input.deviceId}:${input.button.name}:${input.sequence}:${input.uptimeMilliseconds}:${input.gesture.name}';
      if (_seen.containsKey(key)) return finish(AivoControlStatus.duplicate);
      _seen[key] = now;
      if (_seen.length > 256) _seen.remove(_seen.keys.first);
    }
    if (input.isPhysical &&
        input.actionable &&
        input.button != Aiv0Button.unknown &&
        input.gesture != Aiv0ButtonGesture.unknown) {
      final key = capabilityKey(input.button, input.gesture);
      _probes.remove(key)?.cancel();
      _capabilities[key] = AivoCapability.received;
    }
    if (!input.actionable ||
        intent == AivoControlIntent.noAppAction ||
        ((diagnosticsActive || input.source == AivoControlSource.simulation) &&
            !executeTests)) {
      return finish(AivoControlStatus.ignored);
    }
    if (!(canExecute?.call() ?? true)) {
      return finish(AivoControlStatus.unavailable);
    }
    if (_busy && intent != AivoControlIntent.pauseCurrent) {
      return finish(AivoControlStatus.busy);
    }
    final ticket = ++_generation;
    _busy = true;
    _busyTicket = ticket;
    try {
      final result = await _execute(
        input,
        intent,
        ticket,
      ).timeout(operationTimeout);
      return finish(ticket == _generation ? result : AivoControlStatus.ignored);
    } on TimeoutException {
      if (ticket == _generation) ++_generation;
      return finish(AivoControlStatus.busy);
    } catch (_) {
      return finish(AivoControlStatus.failed);
    } finally {
      // A superseded operation must not release the newer pause operation.
      if (_busyTicket == ticket) _busy = false;
    }
  }

  AivoControlStatus? _handleHeldGesture(AivoControlInput input) {
    if (!input.isPhysical ||
        !input.actionable ||
        input.button == Aiv0Button.unknown) {
      return null;
    }
    final now = _now();
    // Missing RELEASE must not permanently disable a source after reconnect.
    // Also expire on a clock rollback rather than extending the quarantine.
    _heldGestures.removeWhere((_, held) {
      final age = now.difference(held.startedAt);
      return age.isNegative || age >= heldGestureTimeout;
    });
    final key = (input.source, input.deviceId, input.button);
    final held = _heldGestures[key];
    if (input.gesture == Aiv0ButtonGesture.release) {
      _heldGestures.remove(key);
      return AivoControlStatus.ignored;
    }
    final sameGesture =
        held != null &&
        (input.sequence == null ||
            held.sequence == null ||
            input.sequence == held.sequence);
    if (sameGesture) {
      if (input.gesture == Aiv0ButtonGesture.shortPress) {
        // Some firmware appends SHORT to LONG. Do not undo the pause by
        // treating this as a fresh request to resume the lesson.
        return AivoControlStatus.ignored;
      }
      if (input.gesture == Aiv0ButtonGesture.longPress) {
        return AivoControlStatus.duplicate;
      }
    }
    if (input.gesture == Aiv0ButtonGesture.longPress) {
      _heldGestures[key] = (sequence: input.sequence, startedAt: now);
      if (_heldGestures.length > 32) {
        _heldGestures.remove(_heldGestures.keys.first);
      }
    } else if (input.gesture == Aiv0ButtonGesture.shortPress) {
      // A new sequence proves that this is a separate physical gesture even
      // when an accessory never emits RELEASE.
      _heldGestures.remove(key);
    }
    return null;
  }

  Future<AivoControlStatus> _execute(
    AivoControlInput input,
    AivoControlIntent intent,
    int ticket,
  ) async {
    final mainInput = MainButtonInputEvent(
      source: input.isPhysical ? MainButtonSource.ble : MainButtonSource.screen,
      gesture: input.gesture == Aiv0ButtonGesture.longPress
          ? MainButtonGesture.longPress
          : MainButtonGesture.shortPress,
      sequence: input.sequence,
    );
    if (intent == AivoControlIntent.pauseCurrent) {
      if (registry.hasActiveModule &&
          registry.isActiveModulePaused &&
          (canResume?.call() ?? true)) {
        return AivoControlStatus.ignored;
      }
      AudioDiagnostics.event('aivo.dispatch.main_pause', {
        'dispatcherGeneration': ticket,
        'ownerGeneration': registry.diagnosticOwnerGeneration,
      });
      return _mainResult(await onPause(mainInput));
    }
    if (intent == AivoControlIntent.assistantOrResume) {
      AudioDiagnostics.event('aivo.dispatch.main_question_requested', {
        'dispatcherGeneration': ticket,
        'ownerGeneration': registry.diagnosticOwnerGeneration,
        'activeKind': registry.activeKind?.name,
      });
      return _mainResult(await onMain(mainInput));
    }
    if (!registry.hasActiveModule) return AivoControlStatus.unavailable;
    final owner = registry.controller;
    final paused = await registry.pauseForMainAssistant(
      canContinue: () => ticket == _generation,
    );
    if (!paused ||
        ticket != _generation ||
        !identical(owner, registry.controller)) {
      return AivoControlStatus.busy;
    }
    final result = await registry.execute(switch (intent) {
      AivoControlIntent.previousItem => ActiveLearningCommand.previousItem,
      AivoControlIntent.nextItem => ActiveLearningCommand.nextItem,
      _ => ActiveLearningCommand.replayCurrent,
    });
    if (_disposed ||
        ticket != _generation ||
        !identical(owner, registry.controller)) {
      return AivoControlStatus.ignored;
    }
    if (result.wasHandled) onModuleHandled?.call();
    return _moduleResult(result);
  }

  static AivoControlStatus _mainResult(MainButtonActionResult result) =>
      switch (result) {
        MainButtonActionResult.accepted => AivoControlStatus.accepted,
        MainButtonActionResult.busy => AivoControlStatus.busy,
        MainButtonActionResult.ignored => AivoControlStatus.ignored,
      };
  static AivoControlStatus _moduleResult(ActiveLearningCommandResult result) =>
      switch (result.status) {
        ActiveLearningCommandStatus.handled => AivoControlStatus.accepted,
        ActiveLearningCommandStatus.unavailable =>
          AivoControlStatus.unavailable,
        ActiveLearningCommandStatus.busy => AivoControlStatus.busy,
      };
  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    for (final timer in _probes.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

class AivoControlScope extends InheritedNotifier<AivoControlDispatcher> {
  const AivoControlScope({
    required AivoControlDispatcher controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static AivoControlDispatcher? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AivoControlScope>()?.notifier;
}
