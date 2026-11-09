import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/background_learning_session.dart';

final nativeAudioFocus = NativeAudioFocus();

/// Process-wide OS focus, independent of the exclusive logical audio-turn queue.
/// A lesson or MAIN can keep a lease while individual players hand off to capture.
class NativeAudioFocus {
  NativeAudioFocus({
    MethodChannel channel = const MethodChannel('ailingo_background_learning'),
    BackgroundLearningSessionControl? session,
    bool? isAndroid,
  }) : _channel = channel,
       _session = session ?? sharedBackgroundLearningSession,
       _isAndroid =
           isAndroid ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final BackgroundLearningSessionControl _session;
  final bool _isAndroid;
  final _interruptions = StreamController<void>.broadcast(sync: true);
  StreamSubscription<BackgroundLearningEvent>? _subscription;
  int _generation = 0;
  int _sequence = 0;

  Stream<void> get interruptions => _interruptions.stream;

  void _listen() {
    _subscription ??= _session.events.listen((event) {
      if (event.type == BackgroundLearningEventType.resumable) return;
      _generation++;
      _interruptions.add(null);
    });
  }

  Future<NativeAudioFocusLease> acquire(
    String owner, {
    bool transientExclusive = false,
  }) async {
    _listen();
    final generation = _generation;
    final id = 'dart:$owner:${++_sequence}';
    var native = false;
    if (_isAndroid) {
      try {
        final granted = await _channel.invokeMethod<bool>('acquireAudioFocus', {
          'ownerId': id,
          'transientExclusive': transientExclusive,
        });
        if (granted == false) {
          throw PlatformException(
            code: 'AUDIO_FOCUS_DENIED',
            message:
                'Âm thanh đang được ứng dụng khác sử dụng. Bạn nhấn MAIN để thử lại.',
          );
        }
        native = granted == true;
      } on MissingPluginException {
        // Allows desktop/tests and older native hosts to use their own session.
      }
    }
    final lease = NativeAudioFocusLease._(this, id, generation, native);
    if (!lease.isCurrent) {
      await lease.release();
      lease.requireCurrent();
    }
    return lease;
  }

  Future<void> _release(String id, bool native) async {
    if (!native) return;
    try {
      await _channel.invokeMethod<void>('releaseAudioFocus', {'ownerId': id});
    } on MissingPluginException {
      // Native host has already detached.
    } on PlatformException {
      // Cleanup must not replace the original interruption error.
    }
  }

  Future<void> dispose() async {
    _generation++;
    await _subscription?.cancel();
    await _interruptions.close();
  }
}

class NativeAudioFocusLease {
  NativeAudioFocusLease._(this._owner, this.id, this._generation, this._native);
  final NativeAudioFocus _owner;
  final String id;
  final int _generation;
  final bool _native;
  bool _released = false;

  bool get isCurrent => !_released && _owner._generation == _generation;

  void requireCurrent() {
    if (!isCurrent) {
      throw PlatformException(
        code: 'AUDIO_FOCUS_LOST',
        message: 'Phiên âm thanh đã bị gián đoạn. Bạn nhấn MAIN để tiếp tục.',
      );
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _owner._release(id, _native);
  }
}
