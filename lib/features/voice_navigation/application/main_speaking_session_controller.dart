import 'dart:async';

import 'package:flutter/foundation.dart';

enum MainSpeakingSessionState {
  inactive,
  ready,
  recording,
  processing,
  playing,
}

enum MainSpeakingNoSpeechAction { retry, exit }

enum MainSpeakingFailedTurnAction { retry, exit }

/// Tracks the context-sensitive Main button while the child practices speech.
///
/// The ten-second timeout only runs while Main is waiting to start a new turn.
/// Recording, translation and result playback always suspend the timeout.
class MainSpeakingSessionController extends ChangeNotifier {
  MainSpeakingSessionController({
    this.idleTimeout = const Duration(seconds: 10),
  });

  /// Failed turns in a row (backend unclear speech, an offline fallback whose
  /// device voice failed, ...) that re-open the microphone before the session
  /// gives up. Failures are usually transient, so they get more room than a
  /// silent child, but a broken route or model must not loop forever.
  static const maxFailedTurnRetries = 2;

  final Duration idleTimeout;

  Timer? _idleTimer;
  MainSpeakingSessionState _state = MainSpeakingSessionState.inactive;
  int _consecutiveNoSpeechTurns = 0;
  int _consecutiveFailedTurns = 0;
  bool _disposed = false;

  MainSpeakingSessionState get state => _state;
  bool get isActive => _state != MainSpeakingSessionState.inactive;
  bool get isReady => _state == MainSpeakingSessionState.ready;
  int get consecutiveNoSpeechTurns => _consecutiveNoSpeechTurns;
  int get consecutiveFailedTurns => _consecutiveFailedTurns;

  void enter() {
    if (_disposed) {
      return;
    }
    _consecutiveNoSpeechTurns = 0;
    _consecutiveFailedTurns = 0;
    _setState(MainSpeakingSessionState.ready, restartReadyTimeout: true);
  }

  void exit() {
    if (_disposed) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = null;
    _consecutiveNoSpeechTurns = 0;
    _consecutiveFailedTurns = 0;
    _setState(MainSpeakingSessionState.inactive);
  }

  /// Ends hands-free translation at the physical MAIN boundary, discards the
  /// current turn, then opens the normal assistant menu in that strict order.
  Future<bool> interruptForMainAssistant({
    required Future<bool> Function() cancelCurrentAction,
    required Future<bool> Function() activateAssistant,
  }) async {
    if (_disposed || !isActive) {
      return false;
    }
    final cancelled = await cancelCurrentAction();
    if (_disposed || !cancelled) {
      return false;
    }
    exit();
    return activateAssistant();
  }

  /// The first silent continuous turn gets one child-friendly retry. A second
  /// consecutive silent turn exits the hands-free session.
  MainSpeakingNoSpeechAction registerNoSpeechTurn() {
    if (_disposed || !isActive) {
      return MainSpeakingNoSpeechAction.exit;
    }
    _consecutiveNoSpeechTurns += 1;
    return _consecutiveNoSpeechTurns == 1
        ? MainSpeakingNoSpeechAction.retry
        : MainSpeakingNoSpeechAction.exit;
  }

  /// A turn that ended in an error re-opens the microphone up to
  /// [maxFailedTurnRetries] times in a row, then exits the session.
  MainSpeakingFailedTurnAction registerFailedTurn() {
    if (_disposed || !isActive) {
      return MainSpeakingFailedTurnAction.exit;
    }
    _consecutiveFailedTurns += 1;
    return _consecutiveFailedTurns <= maxFailedTurnRetries
        ? MainSpeakingFailedTurnAction.retry
        : MainSpeakingFailedTurnAction.exit;
  }

  void markSpeechTurnCompleted() {
    _consecutiveNoSpeechTurns = 0;
    _consecutiveFailedTurns = 0;
  }

  void synchronize({
    required bool isRecording,
    required bool isBusy,
    required bool isPlaying,
  }) {
    if (_disposed || !isActive) {
      return;
    }
    final nextState = isRecording
        ? MainSpeakingSessionState.recording
        : isPlaying
        ? MainSpeakingSessionState.playing
        : isBusy
        ? MainSpeakingSessionState.processing
        : MainSpeakingSessionState.ready;
    if (nextState == _state) {
      return;
    }
    _setState(
      nextState,
      restartReadyTimeout: nextState == MainSpeakingSessionState.ready,
    );
  }

  void _setState(
    MainSpeakingSessionState nextState, {
    bool restartReadyTimeout = false,
  }) {
    if (_state == nextState && !restartReadyTimeout) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = null;
    _state = nextState;
    if (restartReadyTimeout && nextState == MainSpeakingSessionState.ready) {
      _idleTimer = Timer(idleTimeout, () {
        _idleTimer = null;
        if (_disposed || _state != MainSpeakingSessionState.ready) {
          return;
        }
        _state = MainSpeakingSessionState.inactive;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    super.dispose();
  }
}
