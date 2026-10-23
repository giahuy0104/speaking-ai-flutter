import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/platform/background_learning_session.dart';
import '../../listening/data/active_listening_session_store.dart';

enum BackgroundLearningDirective { keepVoiceNavigation, pauseVoiceNavigation }

typedef BackgroundLearningDirectiveHandler =
    void Function(BackgroundLearningDirective directive);

/// Coordinates platform background eligibility and durable lesson recovery.
///
/// Feature sessions still own their prompt, capture, and progress state. This
/// coordinator only translates OS lifecycle/session events into typed keep or
/// pause decisions and restores the smallest safe listening checkpoint once.
class BackgroundLearningCoordinator {
  BackgroundLearningCoordinator({
    required BackgroundLearningSessionControl session,
    required AppLifecycleState initialLifecycleState,
    required BackgroundLearningDirectiveHandler onDirective,
    ActiveListeningSessionStore checkpointStore =
        const ActiveListeningSessionStore(),
    bool? isWeb,
    TargetPlatform? targetPlatform,
  }) : _session = session,
       _checkpointStore = checkpointStore,
       _lifecycleState = initialLifecycleState,
       _onDirective = onDirective,
       _isWeb = isWeb ?? kIsWeb,
       _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  final BackgroundLearningSessionControl _session;
  final ActiveListeningSessionStore _checkpointStore;
  final BackgroundLearningDirectiveHandler _onDirective;
  final bool _isWeb;
  final TargetPlatform _targetPlatform;

  StreamSubscription<BackgroundLearningEvent>? _subscription;
  AppLifecycleState _lifecycleState;
  bool _active = false;
  bool _starting = false;
  bool _microphoneRequiresVisibleResume = false;
  bool _checkpointHandled = false;
  bool _disposed = false;
  bool _voiceAccessEnabled = false;
  int _sessionGeneration = 0;
  Future<void>? _sessionStopOperation;

  bool get isActive => _active;
  bool get isForeground => _lifecycleState == AppLifecycleState.resumed;

  Future<void> initialize({required bool voiceAccessEnabled}) async {
    await ensureStarted(voiceAccessEnabled: voiceAccessEnabled);
  }

  Future<void> updateVoiceAccess(bool enabled) async {
    if (_disposed) return;
    _voiceAccessEnabled = enabled;
    if (enabled) {
      await ensureStarted(voiceAccessEnabled: true);
      return;
    }
    _sessionGeneration += 1;
    _active = false;
    _microphoneRequiresVisibleResume = false;
    await _stopNativeSession();
  }

  BackgroundLearningDirective handleLifecycle(
    AppLifecycleState state, {
    required bool voiceAccessEnabled,
    required bool explicitMainSessionActive,
  }) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      if (_microphoneRequiresVisibleResume) {
        _microphoneRequiresVisibleResume = false;
        _active = false;
      }
      unawaited(ensureStarted(voiceAccessEnabled: voiceAccessEnabled));
      return BackgroundLearningDirective.keepVoiceNavigation;
    }

    // Android keeps only an explicitly-started MAIN command microphone alive;
    // it never revives the old always-on wake-word loop in background.
    if (!_isWeb && _targetPlatform == TargetPlatform.android) {
      if (_active && voiceAccessEnabled && explicitMainSessionActive) {
        return BackgroundLearningDirective.keepVoiceNavigation;
      }
      return BackgroundLearningDirective.pauseVoiceNavigation;
    }

    if (state == AppLifecycleState.detached) {
      _sessionGeneration += 1;
      _active = false;
      unawaited(_stopNativeSession());
    } else if (_active && voiceAccessEnabled) {
      return BackgroundLearningDirective.keepVoiceNavigation;
    }
    return BackgroundLearningDirective.pauseVoiceNavigation;
  }

  Future<void> ensureStarted({required bool voiceAccessEnabled}) async {
    if (_disposed) return;
    _voiceAccessEnabled = voiceAccessEnabled;
    if (!voiceAccessEnabled || _active || _starting || _isWeb) {
      return;
    }
    _starting = true;
    final generation = _sessionGeneration;
    _subscription ??= _session.events.listen(_handleEvent);
    try {
      final stopping = _sessionStopOperation;
      if (stopping != null) await stopping;
      if (_disposed ||
          generation != _sessionGeneration ||
          !_voiceAccessEnabled) {
        return;
      }
      final active = await _session.start();
      if (_disposed || generation != _sessionGeneration) {
        // A late native start must not re-arm iOS capture after voice access
        // was revoked, the app detached, or this Home shell was disposed.
        if (active &&
            (!_disposed || _targetPlatform != TargetPlatform.android)) {
          await _stopNativeSession();
        }
        return;
      }
      _active = active;
      if (active) {
        _onDirective(BackgroundLearningDirective.keepVoiceNavigation);
      }
    } catch (error) {
      debugPrint('Cannot start background learning session: $error');
    } finally {
      _starting = false;
      // Enabling voice again while a revoked start is settling requests a
      // fresh native session, instead of silently losing the enable action.
      if (!_disposed &&
          generation != _sessionGeneration &&
          _voiceAccessEnabled &&
          isForeground) {
        unawaited(ensureStarted(voiceAccessEnabled: true));
      }
    }
  }

  bool canKeepMainListeningInBackground({
    required bool voiceAccessEnabled,
    required bool explicitMainSessionActive,
  }) {
    return _active && voiceAccessEnabled && explicitMainSessionActive;
  }

  Future<ActiveListeningSessionCheckpoint?> takeListeningCheckpoint({
    required bool voiceAccessEnabled,
  }) async {
    if (_checkpointHandled ||
        !voiceAccessEnabled ||
        _isWeb ||
        (_targetPlatform != TargetPlatform.android &&
            _targetPlatform != TargetPlatform.iOS) ||
        !isForeground) {
      return null;
    }
    _checkpointHandled = true;
    return _checkpointStore.read();
  }

  Future<void> clearListeningCheckpoint() => _checkpointStore.clear();

  Future<void> _stopNativeSession() {
    final previous = _sessionStopOperation;
    late final Future<void> operation;
    operation =
        (() async {
          if (previous != null) {
            await previous.catchError((Object error) {
              debugPrint('Previous background learning stop failed: $error');
            });
          }
          await _session.stop();
        })().whenComplete(() {
          if (identical(_sessionStopOperation, operation)) {
            _sessionStopOperation = null;
          }
        });
    _sessionStopOperation = operation;
    return operation;
  }

  Future<void> setActiveLearning(bool active) async {
    final session = _session;
    if (session is ActiveLearningBackgroundSessionControl) {
      await (session as ActiveLearningBackgroundSessionControl)
          .setActiveLearning(active);
    }
  }

  void _handleEvent(BackgroundLearningEvent event) {
    if (_disposed ||
        !_voiceAccessEnabled ||
        _sessionStopOperation != null ||
        (_targetPlatform == TargetPlatform.iOS &&
            _lifecycleState == AppLifecycleState.detached)) {
      return;
    }
    if (event.type == BackgroundLearningEventType.resumable) {
      _active = true;
      _microphoneRequiresVisibleResume =
          event.reason == 'microphone_requires_visible_resume';
      _onDirective(BackgroundLearningDirective.keepVoiceNavigation);
      return;
    }
    _active = false;
    _microphoneRequiresVisibleResume = false;
    _onDirective(BackgroundLearningDirective.pauseVoiceNavigation);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessionGeneration += 1;
    unawaited(_subscription?.cancel());
    if (_isWeb || _targetPlatform != TargetPlatform.android) {
      unawaited(_stopNativeSession());
    }
  }
}
