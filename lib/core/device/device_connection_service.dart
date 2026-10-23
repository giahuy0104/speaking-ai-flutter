import 'dart:async';

import '../../domain/device/device_connection.dart';
import 'device_connection_diagnostics.dart';

/// Owns one connection round. The onboarding pilot has no new background
/// timer: existing native recovery and the app's 15s/60s policy are preserved.
/// Completion means verified MAIN + associated HFP, never merely system bond.
class DeviceConnectionService {
  DeviceConnectionService({
    required DeviceConnectionPort port,
    Future<void> Function(Duration)? delay,
    Duration? timeout,
    DeviceConnectionDiagnostics? diagnostics,
  }) : diagnostics = diagnostics ?? DeviceConnectionDiagnostics(),
       _port = port,
       _delay = delay ?? Future<void>.delayed,
       _timeout = timeout ?? Duration(seconds: port.android ? 75 : 45) {
    _state = DeviceConnectionState(snapshot: port.snapshot);
    _subscription = port.changes.listen((_) => refresh());
  }
  final DeviceConnectionDiagnostics diagnostics;
  final DeviceConnectionPort _port;
  final Future<void> Function(Duration) _delay;
  final Duration _timeout;
  final _states = StreamController<DeviceConnectionState>.broadcast();
  late final StreamSubscription<void> _subscription;
  late DeviceConnectionState _state;
  Future<bool>? _pending;
  Future<void>? _cancelling;
  Completer<void>? _cancelled;
  Completer<DeviceSelection?>? _selection;
  String? _selectionMainId;
  int _generation = 0;
  bool _disposed = false;
  DeviceConnectionState get state => _state;
  Stream<DeviceConnectionState> get states => _states.stream;

  void _publish(
    DeviceStage stage, {
    DeviceIssue? issue,
    List<DeviceMicrophone> microphones = const [],
  }) {
    if (_disposed) return;
    final next = DeviceConnectionState(
      stage: stage,
      snapshot: _port.snapshot,
      issue: issue,
      attempt: _generation,
      microphones: List.unmodifiable(microphones),
    );
    // refresh() runs on every port change; skip republishing an unchanged
    // state so listeners only hear about real transitions.
    if (next == _state) return;
    _state = next;
    diagnostics.state('service', next);
    _states.add(_state);
  }

  /// Read-only pairing inventory for entering/resuming onboarding. It never
  /// selects a microphone, starts a scan, or changes retry preferences.
  Future<void> refreshAudioPairing() async {
    if (_disposed) return;
    await _port.refreshAudioPairing();
    refresh();
  }

  void refresh() {
    if (_disposed) return;
    final snapshot = _port.snapshot;
    if (_selection != null &&
        (!snapshot.mainReady || snapshot.mainId != _selectionMainId)) {
      _selection!.complete(null);
      _selection = null;
    }
    if (_state.busy) {
      _publish(
        _state.stage,
        issue: _state.issue,
        microphones: _state.microphones,
      );
    } else {
      _publish(
        snapshot.ready
            ? DeviceStage.ready
            : _state.stage == DeviceStage.ready
            ? DeviceStage.incomplete
            : _state.stage,
        issue: snapshot.ready
            ? null
            : _state.stage == DeviceStage.ready
            ? (snapshot.mainReady
                  ? DeviceIssue.audioUnavailable
                  : DeviceIssue.mainUnavailable)
            : _state.issue,
      );
    }
  }

  Future<bool> connect({
    bool interactive = true,
    bool chooseMicrophone = false,
  }) {
    if (_disposed) return Future.value(false);
    final running = _pending;
    if (running != null) return running;
    final token = ++_generation;
    final cancelled = Completer<void>();
    _cancelled = cancelled;
    diagnostics.event(token, 'attempt.start', {
      'interactive': interactive,
      'chooseMicrophone': chooseMicrophone,
      'timeoutMs': _timeout.inMilliseconds,
      'platform': _port.android ? 'android' : 'ios',
    });
    final operation = diagnostics.run(
      token,
      () => _run(token, cancelled, interactive, chooseMicrophone),
    );
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
      if (identical(_cancelled, cancelled)) _cancelled = null;
    });
  }

  bool _current(int token) => !_disposed && token == _generation;
  void _check(int token) {
    if (!_current(token)) throw const _Cancelled();
  }

  Future<T> _step<T>(int token, Future<T> Function() action) async {
    _check(token);
    final result = await action();
    _check(token);
    return result;
  }

  Future<bool> _run(
    int token,
    Completer<void> cancelled,
    bool interactive,
    bool chooseMicrophone,
  ) async {
    try {
      await _cancelling;
      _check(token);
      final ready = await Future.any<bool>([
        _connect(token, interactive, chooseMicrophone),
        cancelled.future.then((_) => false),
      ]).timeout(_timeout);
      diagnostics.event(token, 'attempt.complete', {'ready': ready});
      return ready;
    } on _Cancelled {
      diagnostics.event(token, 'attempt.stale');
      return false;
    } on TimeoutException {
      diagnostics.event(token, 'attempt.timeout');
      if (_current(token)) {
        final cancellation = cancel();
        final cancelledGeneration = _generation;
        await cancellation;
        if (_current(cancelledGeneration)) {
          _publish(DeviceStage.failed, issue: DeviceIssue.timedOut);
        }
      }
      return false;
    } catch (error) {
      diagnostics.event(token, 'attempt.error', {
        'type': error.runtimeType.toString(),
      });
      if (_current(token)) {
        final cancellation = cancel();
        final cancelledGeneration = _generation;
        await cancellation;
        if (_current(cancelledGeneration)) {
          _publish(DeviceStage.failed, issue: DeviceIssue.transportFailure);
        }
      }
      return false;
    }
  }

  Future<bool> _connect(
    int token,
    bool interactive,
    bool chooseMicrophone,
  ) async {
    _publish(DeviceStage.checkingAccess);
    final issue = await _step(
      token,
      () => _port.prepareAccess(interactive: interactive),
    );
    if (issue != null) {
      _publish(DeviceStage.incomplete, issue: issue);
      return false;
    }
    if (interactive) await _step(token, _port.resumeAutomaticConnection);
    final wasMainReady = _port.snapshot.mainReady;
    _publish(DeviceStage.connectingMain);
    if (!wasMainReady) {
      await _step(token, () => _port.connectMain(interactive: interactive));
    }
    await _step(token, _port.refreshAudioPairing);
    if (!_port.snapshot.mainReady) {
      // Audio is present but MAIN is missing. This identifies a partial
      // connection, not proof that HFP caused the BLE discovery failure.
      _publish(
        DeviceStage.incomplete,
        issue: _port.snapshot.audioConnected
            ? DeviceIssue.audioBlocksMain
            : DeviceIssue.mainUnavailable,
      );
      return false;
    }
    if (_port.snapshot.ready && !chooseMicrophone) {
      _publish(DeviceStage.ready);
      return true;
    }
    if (interactive && wasMainReady && !_port.snapshot.audioReady) {
      await _step(token, _port.pairConnectedMain);
    }
    _publish(DeviceStage.preparingAudio);
    final delays = _port.android
        ? const [0, 350, 650, 900, 1200, 1600]
        : const [0, 600, 600];
    if (!chooseMicrophone) {
      for (final milliseconds in delays) {
        if (milliseconds > 0) {
          await _step(
            token,
            () => _delay(Duration(milliseconds: milliseconds)),
          );
        }
        if (!_port.snapshot.mainReady) break;
        await _step(token, _port.autoSelectAudio);
        if (_port.snapshot.ready) {
          _publish(DeviceStage.ready);
          return true;
        }
      }
    }
    if (!_port.snapshot.mainReady) {
      _publish(DeviceStage.incomplete, issue: DeviceIssue.mainUnavailable);
      return false;
    }
    if (interactive) {
      final mainId = _port.snapshot.mainId;
      final devices = await _step(token, _port.findMicrophones);
      if (!_port.snapshot.mainReady || mainId != _port.snapshot.mainId) {
        _publish(DeviceStage.incomplete, issue: DeviceIssue.mainUnavailable);
        return false;
      }
      // Android can only route a connected microphone. Without one, end as
      // audioUnavailable so onboarding guides turning HOMI audio on.
      if (_port.android
          ? devices.any((d) => d.connected)
          : devices.isNotEmpty) {
        final selection = Completer<DeviceSelection?>();
        _selection = selection;
        _selectionMainId = mainId;
        _publish(DeviceStage.choosingMicrophone, microphones: devices);
        final chosen = await _step(token, () => selection.future);
        if (identical(_selection, selection)) _selection = null;
        if (chosen == null ||
            !_port.snapshot.mainReady ||
            mainId != _port.snapshot.mainId) {
          _publish(
            DeviceStage.incomplete,
            issue: _port.snapshot.mainReady
                ? DeviceIssue.selectionRequired
                : DeviceIssue.mainUnavailable,
          );
          return false;
        }
        _publish(DeviceStage.preparingAudio);
        await _step(token, () => _port.selectMicrophone(chosen));
        // HFP negotiation may drop MAIN. Only reconnect the verified identity
        // through the existing adapter; never consider audio alone ready.
        if (!_port.snapshot.mainReady) {
          await _step(token, () => _port.connectMain(interactive: false));
        }
      }
    }
    final ready = _port.snapshot.ready;
    _publish(
      ready ? DeviceStage.ready : DeviceStage.incomplete,
      issue: ready
          ? null
          : _port.snapshot.mainReady
          ? DeviceIssue.audioUnavailable
          : DeviceIssue.mainUnavailable,
    );
    return ready;
  }

  void selectMicrophone(int attempt, DeviceSelection? selection) {
    if (!_current(attempt) || _selection == null) return;
    if (selection != null) {
      final matching = _state.microphones.where(
        (d) => d.id == selection.device.id,
      );
      if (matching.isEmpty ||
          (_port.android && !matching.first.connected) ||
          (matching.first.needsConfirmation && !selection.confirmAssociation)) {
        return;
      }
    }
    _selection!.complete(selection);
    _selection = null;
  }

  Future<void> cancel() {
    if (_disposed) return Future.value();
    diagnostics.event(_generation, 'attempt.cancel');
    diagnostics.inherit(_generation + 1, _generation);
    ++_generation;
    _cancelled?.complete();
    _cancelled = null;
    _selection?.complete(null);
    _selection = null;
    _pending = null;
    _publish(DeviceStage.cancelled);
    return _cancelling ??= _port.cancelAttempt().whenComplete(
      () => _cancelling = null,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (_pending != null) await cancel();
    _disposed = true;
    await _subscription.cancel();
    await _port.dispose();
    await _states.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
