import '../../../core/device/active_learning_module.dart';
import '../../../core/session/app_flow_coordinator.dart';

typedef MainAssistantActivation =
    Future<bool> Function({
      required bool activeLearning,
      required ActiveLearningModuleKind? activeLearningKind,
    });

/// Owns the activation boundary of the fixed MAIN assistant.
///
/// Gesture decoding, speech recognition, prompts, and feature business logic
/// remain in their existing components. This session only serializes takeover
/// and coordinates pause/resume with [AppFlowCoordinator].
class MainAssistantSession {
  MainAssistantSession({
    required AppFlowCoordinator appFlowCoordinator,
    void Function(bool pending)? onActivationChanged,
  }) : _appFlowCoordinator = appFlowCoordinator,
       _onActivationChanged = onActivationChanged;

  final AppFlowCoordinator _appFlowCoordinator;
  final void Function(bool pending)? _onActivationChanged;
  bool _activationPending = false;
  int _generation = 0;

  void cancelForNavigation() {
    _generation++;
    _appFlowCoordinator.forgetPausedModule();
    _setActivationPending(false);
  }

  bool get isActivationPending => _activationPending;

  /// Guards external MAIN handoffs which await recorder/route cleanup before
  /// entering the assistant. A later pause/navigation cancels that handoff.
  bool Function() captureCancellationGuard() {
    final generation = _generation;
    return () => generation == _generation;
  }

  void setExternalActivation(bool pending) => _setActivationPending(pending);

  Future<bool> activate({
    required bool startupReady,
    required bool voiceAccessEnabled,
    required bool conversationBusy,
    required bool assistantFlowBusy,
    required bool Function() canContinue,
    required MainAssistantActivation activateVoice,
    Future<bool> Function()? prepareActivation,
  }) async {
    if (!startupReady ||
        !voiceAccessEnabled ||
        _activationPending ||
        assistantFlowBusy) {
      return false;
    }

    final hadActiveModule = _appFlowCoordinator.hasActiveModule;
    if (!hadActiveModule && conversationBusy) return false;

    final generation = ++_generation;
    _setActivationPending(true);
    try {
      if (generation != _generation || !canContinue()) return false;
      if (prepareActivation != null) {
        final prepared = await prepareActivation();
        if (!prepared || generation != _generation || !canContinue()) {
          return false;
        }
      }
      final pause = await _appFlowCoordinator.pauseForMainAssistant();
      if (generation != _generation || !canContinue()) return false;
      final activated = await activateVoice(
        activeLearning: pause.hasActiveModule,
        activeLearningKind: pause.activeKind,
      );
      if (generation != _generation) return false;
      if (!activated && pause.paused) {
        await _appFlowCoordinator.resumeAfterMainAssistant();
      }
      return activated;
    } finally {
      if (generation == _generation) _setActivationPending(false);
    }
  }

  void _setActivationPending(bool pending) {
    if (_activationPending == pending) return;
    _activationPending = pending;
    _onActivationChanged?.call(pending);
  }
}
