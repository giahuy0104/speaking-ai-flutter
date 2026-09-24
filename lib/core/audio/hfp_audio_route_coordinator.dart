import 'dart:async';

import 'audio_input.dart';
import 'audio_diagnostics.dart';
import 'hfp_audio_control.dart';

class HfpAudioRouteToken {
  const HfpAudioRouteToken({
    required this.id,
    required this.generation,
    required this.owner,
  });

  final int id;
  final int generation;
  final String owner;

  @override
  bool operator ==(Object other) =>
      other is HfpAudioRouteToken &&
      other.id == id &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(id, generation);
}

/// Optional ownership capability exposed by a scoped HFP control.
abstract interface class HfpAudioRouteLeaseControl {
  HfpAudioRouteToken? get activeAudioRouteToken;

  /// Drops this Dart owner after a native recognizer has assumed ownership of
  /// the already-open route. It deliberately does not close SCO/HFP.
  Future<void> handoffAudioRoute();
}

/// Explicit output changes must not inherit the short H20 handoff window.
abstract interface class HfpImmediateRouteReleaseControl {
  Future<void> stopAudioRouteImmediately();
}

/// One process-level writer for the native HFP/SCO route.
///
/// Each feature receives a [ScopedHfpAudioControl]. The first scope opens the
/// native route and the final scope closes it, so disposing an older feature
/// cannot tear down a newer feature's microphone or playback route.
class HfpAudioRouteCoordinator {
  HfpAudioRouteCoordinator(
    this._delegate, {
    this.handoffGrace = Duration.zero,
    this.revalidateOnAcquire = false,
  });

  final HfpAudioControl _delegate;
  final Duration handoffGrace;
  final bool revalidateOnAcquire;
  Timer? _idleReleaseTimer;
  bool _retainedForHandoff = false;
  int _idleReleaseGeneration = 0;
  final Map<int, HfpAudioRouteToken> _active = <int, HfpAudioRouteToken>{};
  Future<void> _operationTail = Future<void>.value();
  int _nextId = 0;
  int _generation = 0;
  int _connectionGeneration = 0;
  bool _disposed = false;

  HfpAudioControl createScope(String owner) =>
      ScopedHfpAudioControl._(this, owner.trim().isEmpty ? 'unknown' : owner);

  Future<HfpAudioRouteToken> _acquire(String owner) {
    final connectionGeneration = _connectionGeneration;
    return _serialize(() async {
      _ensureActive();
      if (connectionGeneration != _connectionGeneration) {
        throw const HfpAudioException('Lượt âm thanh đã dừng.');
      }
      _cancelIdleRelease();
      try {
        if (_active.isEmpty ||
            revalidateOnAcquire ||
            !_delegate.status.routeActive) {
          await _delegate.startAudioRoute();
        }
      } catch (_) {
        if (_retainedForHandoff && _active.isEmpty) {
          _retainedForHandoff = false;
          await _delegate.stopAudioRoute().catchError((Object _) {});
        }
        rethrow;
      }
      if (connectionGeneration != _connectionGeneration) {
        throw const HfpAudioException('Lượt âm thanh đã dừng.');
      }
      _retainedForHandoff = false;
      final token = HfpAudioRouteToken(
        id: ++_nextId,
        generation: ++_generation,
        owner: owner,
      );
      _active[token.id] = token;
      return token;
    });
  }

  Future<bool> _revalidate(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return false;
      }
      await _delegate.startAudioRoute();
      return true;
    });
  }

  Future<void> _release(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return;
      }
      _active.remove(token.id);
      if (_active.isEmpty) {
        if (handoffGrace > Duration.zero) {
          _retainedForHandoff = true;
          final generation = ++_idleReleaseGeneration;
          _idleReleaseTimer?.cancel();
          AudioDiagnostics.event('hfp.handoff.retained', {
            'owner': token.owner,
            'graceMs': handoffGrace.inMilliseconds,
          });
          _idleReleaseTimer = Timer(handoffGrace, () {
            unawaited(
              _serialize(() async {
                if (_disposed ||
                    generation != _idleReleaseGeneration ||
                    _active.isNotEmpty) {
                  return;
                }
                _idleReleaseTimer = null;
                _retainedForHandoff = false;
                AudioDiagnostics.event('hfp.handoff.expired');
                await _delegate.stopAudioRoute();
              }).catchError((Object error) {
                AudioDiagnostics.event('hfp.handoff.release_failed', {
                  'type': error.runtimeType.toString(),
                });
              }),
            );
          });
        } else {
          await _delegate.stopAudioRoute();
        }
      }
    });
  }

  Future<void> _handoff(HfpAudioRouteToken token) {
    return _serialize(() async {
      if (_disposed || _active[token.id] != token) {
        return;
      }
      _active.remove(token.id);
      // Native Apple Speech/HFP has already opened and retained its own owner.
      // Closing here would recreate the prompt-to-micro route gap.
    });
  }

  Future<void> _flushIdleRelease() => _serialize(() async {
    if (_disposed || _active.isNotEmpty || !_retainedForHandoff) return;
    _cancelIdleRelease();
    _retainedForHandoff = false;
    await _delegate.stopAudioRoute();
  });

  Future<void> _connect(HfpAudioDevice device) => _serialize(() async {
    _ensureActive();
    await _delegate.connect(device);
  });

  Future<void> disconnect() {
    _connectionGeneration += 1;
    return _serialize(() async {
      _cancelIdleRelease();
      _retainedForHandoff = false;
      _active.clear();
      if (!_disposed) {
        await _delegate.disconnect();
      }
    });
  }

  void _cancelIdleRelease() {
    ++_idleReleaseGeneration;
    _idleReleaseTimer?.cancel();
    _idleReleaseTimer = null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _operationTail.then<T>((_) => action());
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('HFP audio route coordinator has been disposed.');
    }
  }

  Future<void> dispose() {
    return _serialize(() async {
      if (_disposed) {
        return;
      }
      _disposed = true;
      _cancelIdleRelease();
      final hadActiveRoute = _active.isNotEmpty || _retainedForHandoff;
      _retainedForHandoff = false;
      _active.clear();
      if (hadActiveRoute) {
        await _delegate.stopAudioRoute().catchError((Object _) {});
      }
      await _delegate.dispose();
    });
  }
}

class ScopedHfpAudioControl
    implements
        HfpAudioControl,
        HfpAudioRouteLeaseControl,
        HfpImmediateRouteReleaseControl {
  ScopedHfpAudioControl._(this._coordinator, this.owner);

  final HfpAudioRouteCoordinator _coordinator;
  final String owner;
  HfpAudioRouteToken? _token;
  bool _disposed = false;
  Future<void> _scopeOperationTail = Future<void>.value();
  int _requestGeneration = 0;

  HfpAudioControl get _delegate => _coordinator._delegate;

  @override
  HfpAudioRouteToken? get activeAudioRouteToken => _token;

  @override
  bool get usesBrowserAudioInput => _delegate.usesBrowserAudioInput;

  @override
  BluetoothAudioStatus get status => _delegate.status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _delegate.statusChanges;

  @override
  Future<void> initialize() => _delegate.initialize();

  @override
  Future<List<HfpAudioDevice>> findDevices() => _delegate.findDevices();

  @override
  Future<void> connect(HfpAudioDevice device) => _coordinator._connect(device);

  @override
  Future<void> disconnect() {
    _requestGeneration += 1;
    final disconnecting = _coordinator.disconnect();
    return _serializeScope(() async {
      _token = null;
      await disconnecting;
    });
  }

  @override
  Future<void> startAudioRoute() {
    final generation = _requestGeneration;
    return _serializeScope(() async {
      if (_disposed) {
        throw StateError('Scoped HFP audio control has been disposed.');
      }
      if (generation != _requestGeneration) {
        throw const HfpAudioException('Lượt âm thanh đã dừng.');
      }
      final token = _token;
      if (token != null) {
        if (await _coordinator._revalidate(token)) {
          if (_disposed || generation != _requestGeneration) {
            throw const HfpAudioException('Lượt âm thanh đã dừng.');
          }
          return;
        }
        _token = null;
      }
      _token = await _coordinator._acquire(owner);
      if (_disposed || generation != _requestGeneration) {
        // stop/dispose may arrive before native SCO confirms. The queued stop
        // releases this token; never let the stale caller start playback/capture.
        throw const HfpAudioException('Lượt âm thanh đã dừng.');
      }
    });
  }

  @override
  Future<void> stopAudioRoute() {
    _requestGeneration += 1;
    return _serializeScope(() async {
      final token = _token;
      _token = null;
      if (token != null) {
        await _coordinator._release(token);
      }
    });
  }

  @override
  Future<void> stopAudioRouteImmediately() async {
    await stopAudioRoute();
    // A different live owner is never torn down. Only the idle handoff lease
    // is flushed before the explicit phone-output preparation continues.
    await _coordinator._flushIdleRelease();
  }

  Future<void> _serializeScope(Future<void> Function() action) {
    final operation = _scopeOperationTail.then((_) => action());
    _scopeOperationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  @override
  Future<void> handoffAudioRoute() => _serializeScope(() async {
    final token = _token;
    _token = null;
    if (token != null) {
      await _coordinator._handoff(token);
    }
  });

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stopAudioRoute();
  }
}
