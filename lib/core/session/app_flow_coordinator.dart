import '../device/active_learning_module.dart';

typedef AppFlowSpokenReply = Future<void> Function(String text);

class MainLearningPause {
  const MainLearningPause({
    required this.paused,
    required this.hasActiveModule,
    required this.activeKind,
    this.operation,
  });

  final bool paused;
  final bool hasActiveModule;
  final ActiveLearningModuleKind? activeKind;
  final ActiveLearningOperationToken? operation;

  ActiveLearningVoiceContext? get voiceContext => operation?.voiceContext;
}

/// Typed boundary between MAIN navigation and the currently visible learning
/// module.
///
/// It does not contain lesson or vocabulary business rules. Those remain in
/// the registered module and are reached only through [ActiveLearningCommand].
class AppFlowCoordinator {
  AppFlowCoordinator({required ActiveLearningModuleRegistry registry})
    : _registry = registry;

  final ActiveLearningModuleRegistry _registry;
  bool _activeModulePausedForMain = false;
  bool _resumingActiveModule = false;
  int _pauseGeneration = 0;
  ActiveLearningOperationToken? _pausedOperation;

  bool get hasActiveModule => _registry.hasActiveModule;
  bool get activeModulePausedForMain => _activeModulePausedForMain;
  ActiveLearningModuleKind? get activeKind => _registry.activeKind;

  Future<MainLearningPause> pauseForMainAssistant() async {
    final hadActiveModule = _registry.hasActiveModule;
    var kind = _registry.activeKind;
    if (!hadActiveModule) {
      _pausedOperation = null;
      return MainLearningPause(
        paused: false,
        hasActiveModule: false,
        activeKind: kind,
      );
    }

    final generation = _pauseGeneration;
    final paused = await _registry.pauseForMainAssistant(
      canContinue: () => generation == _pauseGeneration,
    );
    if (generation != _pauseGeneration) {
      return const MainLearningPause(
        paused: false,
        hasActiveModule: false,
        activeKind: null,
      );
    }
    _activeModulePausedForMain = paused;
    final operation = paused ? _registry.captureOperation() : null;
    final stableActiveModule =
        operation != null &&
        _registry.isOperationCurrent(operation) &&
        _registry.isActiveModulePaused;
    _activeModulePausedForMain = stableActiveModule;
    _pausedOperation = stableActiveModule ? operation : null;
    kind = stableActiveModule ? operation.moduleKind : null;
    return MainLearningPause(
      paused: _activeModulePausedForMain,
      hasActiveModule: stableActiveModule,
      activeKind: kind,
      operation: _pausedOperation,
    );
  }

  bool isPauseCurrent(MainLearningPause pause) {
    final operation = pause.operation;
    return pause.paused &&
        operation != null &&
        identical(operation, _pausedOperation) &&
        _activeModulePausedForMain &&
        _registry.isOperationCurrent(operation);
  }

  Future<ActiveLearningCommandResult> execute(
    ActiveLearningCommand command, {
    AppFlowSpokenReply? onUnhandledReply,
  }) async {
    ActiveLearningCommandResult result;
    final operation = _activeModulePausedForMain ? _pausedOperation : null;
    if (_activeModulePausedForMain &&
        (operation == null || !_registry.isOperationCurrent(operation))) {
      forgetPausedModule();
      return const ActiveLearningCommandResult.unavailable();
    }
    try {
      result = await _registry.execute(command, operation: operation);
    } catch (_) {
      result = const ActiveLearningCommandResult.busy(
        spokenReply: 'HOMI chưa thực hiện được. Bạn thử lại nhé.',
      );
    }
    if (result.wasHandled) {
      _activeModulePausedForMain = false;
      _pausedOperation = null;
    } else if (operation != null && !_registry.isOperationCurrent(operation)) {
      forgetPausedModule();
    } else {
      final reply = result.spokenReply?.trim();
      if (reply != null && reply.isNotEmpty) {
        await onUnhandledReply?.call(reply);
      }
    }
    return result;
  }

  Future<void> resumeAfterMainAssistant() async {
    if (!_activeModulePausedForMain || _resumingActiveModule) return;
    _resumingActiveModule = true;
    try {
      final result = await execute(ActiveLearningCommand.resume);
      if (result.wasHandled ||
          !_registry.hasActiveModule ||
          !_registry.isActiveModulePaused) {
        _activeModulePausedForMain = false;
      }
    } catch (_) {
      // Keep the paused marker so a later assistant state change can retry.
    } finally {
      _resumingActiveModule = false;
    }
  }

  void forgetPausedModule() {
    _pauseGeneration++;
    _activeModulePausedForMain = false;
    _pausedOperation = null;
  }
}
