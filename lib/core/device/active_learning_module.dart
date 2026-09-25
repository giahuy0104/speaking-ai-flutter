import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/audio_diagnostics.dart';

/// The small, shared command surface exposed by whichever learning module is
/// currently visible.
///
/// Detailed lesson/vocabulary scripts remain inside their owning feature. The
/// global MAIN assistant only asks the active module to pause, resume, or move
/// at well-defined boundaries.
enum ActiveLearningCommand {
  resume,
  replayCurrent,
  nextItem,
  previousItem,
  nextLesson,
  previousLesson,
  restart,
  vocabularyParentAdded,
  vocabularyPracticeAgain,
  vocabularyStars,
  vocabularyLatest,
  vocabularyAll,
  stop,
  exitToHome,
}

enum ActiveLearningModuleKind { listeningLesson, vocabulary }

/// Read-only navigation context published by a learning owner. MAIN consumes
/// this snapshot; playback, attempts and persistence remain in that owner.
enum ActiveLearningVoiceNode {
  core,
  song,
  challenge,
  review,
  today,
  todayAfterEnVi,
  parent,
  star,
  vocabularyMenu,
  parentAlternatives,
  starAlternatives,
  reviewAlternatives,
  todayEnd,
  blockEnd,
  listEnd,
}

abstract interface class ActiveLearningVoiceContext {
  ActiveLearningVoiceNode get mainVoiceNode;
  String get mainVoicePrompt;
}

/// Completion nodes may carry dynamic lesson/level numbers. The owning module
/// resolves those slots using the same choices displayed on screen.
abstract interface class ActiveLearningVoiceSelectionContext {
  bool get isMainVoiceChoice;
  ActiveLearningCommand? resolveMainVoiceChoice(String transcript);
}

enum ActiveLearningCommandStatus { handled, unavailable, busy }

class ActiveLearningCommandResult {
  const ActiveLearningCommandResult._(this.status, this.spokenReply);

  const ActiveLearningCommandResult.handled({String? spokenReply})
    : this._(ActiveLearningCommandStatus.handled, spokenReply);

  const ActiveLearningCommandResult.unavailable({String? spokenReply})
    : this._(ActiveLearningCommandStatus.unavailable, spokenReply);

  const ActiveLearningCommandResult.busy({String? spokenReply})
    : this._(ActiveLearningCommandStatus.busy, spokenReply);

  final ActiveLearningCommandStatus status;
  final String? spokenReply;

  bool get wasHandled => status == ActiveLearningCommandStatus.handled;
}

abstract interface class ActiveLearningModuleController {
  ActiveLearningModuleKind get moduleKind;

  /// Whether the visible learning activity is currently paused by MAIN.
  bool get isPausedForMain;

  /// Stops audio/recording immediately but preserves the exact learning
  /// position so MAIN can ask for a command without destroying the route.
  Future<void> pauseForMainAssistant();

  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  );
}

/// One microphone owner and one visible learning owner at a time.
///
/// Learning routes can temporarily stack (for example, the review route sits
/// above the practice route). The last registered route receives MAIN commands;
/// removing it restores the route immediately below it.
class ActiveLearningModuleRegistry extends ChangeNotifier {
  ActiveLearningModuleRegistry({
    Duration operationTimeout = const Duration(seconds: 3),
  }) : _operationTimeout = operationTimeout;

  final Duration _operationTimeout;
  final List<_ActiveLearningModuleRegistration> _registrations =
      <_ActiveLearningModuleRegistration>[];
  bool _notificationScheduled = false;
  int _diagnosticOwnerGeneration = 0;

  ActiveLearningModuleController? get controller =>
      _registrations.lastOrNull?.controller;
  bool get hasActiveModule => controller != null;
  bool get isActiveModulePaused => controller?.isPausedForMain ?? false;
  ActiveLearningModuleKind? get activeKind => controller?.moduleKind;
  int get diagnosticOwnerGeneration => _diagnosticOwnerGeneration;

  Object register(ActiveLearningModuleController controller) {
    final token = Object();
    _registrations.add(
      _ActiveLearningModuleRegistration(controller: controller, token: token),
    );
    _diagnosticOwnerGeneration += 1;
    AudioDiagnostics.event('active_learning.owner.registered', {
      ..._diagnosticOwner(controller),
      'ownerGeneration': _diagnosticOwnerGeneration,
      'registrationDepth': _registrations.length,
    });
    _notifySafely();
    return token;
  }

  void unregister(Object token) {
    final index = _registrations.indexWhere(
      (registration) => identical(registration.token, token),
    );
    if (index < 0) {
      return;
    }
    final wasActive = index == _registrations.length - 1;
    final removed = _registrations[index].controller;
    _registrations.removeAt(index);
    if (wasActive) {
      _diagnosticOwnerGeneration += 1;
      AudioDiagnostics.event('active_learning.owner.unregistered', {
        ..._diagnosticOwner(removed),
        'ownerGeneration': _diagnosticOwnerGeneration,
        'nextOwnerId': controller == null
            ? null
            : identityHashCode(controller!),
        'registrationDepth': _registrations.length,
      });
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (_notificationScheduled) {
      return;
    }
    _notificationScheduled = true;
    scheduleMicrotask(() {
      _notificationScheduled = false;
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  Future<bool> pauseForMainAssistant({bool Function()? canContinue}) async {
    // A lesson can replace its intro/practice/review route while MAIN is being
    // pressed. Pausing only the controller captured before that transition
    // leaves the newly visible route playing, and the app then rejects MAIN as
    // busy. Follow the top registration until the visible owner is stable.
    var remainingAttempts = _registrations.length + 1;
    final operation = AudioDiagnostics.nextId();
    while (remainingAttempts > 0) {
      if (canContinue != null && !canContinue()) {
        AudioDiagnostics.event('active_learning.pause.cancelled', {
          'operation': operation,
          'ownerGeneration': _diagnosticOwnerGeneration,
          'reason': 'caller_cancelled',
        });
        return false;
      }
      remainingAttempts -= 1;
      final active = controller;
      if (active == null) {
        AudioDiagnostics.event('active_learning.pause.unavailable', {
          'operation': operation,
          'ownerGeneration': _diagnosticOwnerGeneration,
        });
        return false;
      }
      final ownerGeneration = _diagnosticOwnerGeneration;
      AudioDiagnostics.event('active_learning.pause.requested', {
        ..._diagnosticOwner(active),
        'operation': operation,
        'ownerGeneration': ownerGeneration,
      });
      try {
        await active.pauseForMainAssistant().timeout(_operationTimeout);
      } on TimeoutException {
        // Module state is changed synchronously before native media cleanup.
        // Accept that paused state and let obsolete native callbacks drain in
        // the background instead of permanently disabling physical MAIN.
        final accepted =
            identical(active, controller) && active.isPausedForMain;
        AudioDiagnostics.event('active_learning.pause.timed_out', {
          ..._diagnosticOwner(active),
          'operation': operation,
          'ownerGeneration': ownerGeneration,
          'acceptedPausedState': accepted,
        });
        return accepted;
      } catch (error) {
        AudioDiagnostics.event('active_learning.pause.failed', {
          ..._diagnosticOwner(active),
          'operation': operation,
          'ownerGeneration': ownerGeneration,
          'errorType': error.runtimeType.toString(),
        });
        return false;
      }
      if (canContinue != null && !canContinue()) {
        AudioDiagnostics.event('active_learning.pause.cancelled', {
          ..._diagnosticOwner(active),
          'operation': operation,
          'ownerGeneration': ownerGeneration,
          'reason': 'caller_cancelled_after_pause',
        });
        return false;
      }
      if (identical(active, controller)) {
        AudioDiagnostics.event('active_learning.pause.completed', {
          ..._diagnosticOwner(active),
          'operation': operation,
          'ownerGeneration': ownerGeneration,
        });
        return true;
      }
      AudioDiagnostics.event('active_learning.pause.owner_changed', {
        ..._diagnosticOwner(active),
        'operation': operation,
        'ownerGeneration': ownerGeneration,
        'nextOwnerGeneration': _diagnosticOwnerGeneration,
        'nextOwnerId': controller == null
            ? null
            : identityHashCode(controller!),
      });
    }
    return controller?.isPausedForMain ?? false;
  }

  Future<ActiveLearningCommandResult> execute(
    ActiveLearningCommand command,
  ) async {
    final active = controller;
    final operation = AudioDiagnostics.nextId();
    final ownerGeneration = _diagnosticOwnerGeneration;
    if (active == null) {
      AudioDiagnostics.event('active_learning.command.unavailable', {
        'operation': operation,
        'ownerGeneration': ownerGeneration,
        'command': command.name,
      });
      return const ActiveLearningCommandResult.unavailable();
    }
    AudioDiagnostics.event('active_learning.command.started', {
      ..._diagnosticOwner(active),
      'operation': operation,
      'ownerGeneration': ownerGeneration,
      'command': command.name,
    });
    try {
      final result = await active
          .handleMainCommand(command)
          .timeout(_operationTimeout);
      AudioDiagnostics.event('active_learning.command.completed', {
        ..._diagnosticOwner(active),
        'operation': operation,
        'ownerGeneration': ownerGeneration,
        'currentOwnerGeneration': _diagnosticOwnerGeneration,
        'sameOwner': identical(active, controller),
        'command': command.name,
        'status': result.status.name,
      });
      return result;
    } on TimeoutException {
      // The command may still be completing its prompt/native handoff. Do not
      // overlay that valid flow with a second, unrelated spoken busy prompt.
      AudioDiagnostics.event('active_learning.command.timed_out', {
        ..._diagnosticOwner(active),
        'operation': operation,
        'ownerGeneration': ownerGeneration,
        'currentOwnerGeneration': _diagnosticOwnerGeneration,
        'command': command.name,
      });
      return const ActiveLearningCommandResult.busy();
    } catch (error) {
      AudioDiagnostics.event('active_learning.command.failed', {
        ..._diagnosticOwner(active),
        'operation': operation,
        'ownerGeneration': ownerGeneration,
        'command': command.name,
        'errorType': error.runtimeType.toString(),
      });
      return const ActiveLearningCommandResult.busy();
    }
  }

  Map<String, Object?> _diagnosticOwner(
    ActiveLearningModuleController active,
  ) => <String, Object?>{
    'ownerId': identityHashCode(active),
    'ownerKind': active.moduleKind.name,
    'node': active is ActiveLearningVoiceContext
        ? (active as ActiveLearningVoiceContext).mainVoiceNode.name
        : null,
    'paused': active.isPausedForMain,
  };

  /// Stops the visible activity before applying a hardware-style command.
  ///
  /// Virtual lesson controls use this path today. The physical AIV0 buttons
  /// can map to the same logical commands later without duplicating media or
  /// microphone cancellation rules.
  Future<ActiveLearningCommandResult> interruptAndExecute(
    ActiveLearningCommand command,
  ) async {
    final activeBeforePause = controller;
    if (activeBeforePause == null) {
      return const ActiveLearningCommandResult.unavailable();
    }
    final paused = await pauseForMainAssistant();
    if (!paused || !identical(activeBeforePause, controller)) {
      return const ActiveLearningCommandResult.busy();
    }
    return execute(command);
  }
}

class _ActiveLearningModuleRegistration {
  const _ActiveLearningModuleRegistration({
    required this.controller,
    required this.token,
  });

  final ActiveLearningModuleController controller;
  final Object token;
}

class ActiveLearningModuleScope
    extends InheritedNotifier<ActiveLearningModuleRegistry> {
  const ActiveLearningModuleScope({
    required ActiveLearningModuleRegistry registry,
    required super.child,
    this.onNavigationExit,
    super.key,
  }) : super(notifier: registry);

  final VoidCallback? onNavigationExit;

  static void notifyNavigationExit(BuildContext context) => context
      .getInheritedWidgetOfExactType<ActiveLearningModuleScope>()
      ?.onNavigationExit
      ?.call();

  static ActiveLearningModuleRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ActiveLearningModuleScope>()
      ?.notifier;

  /// Reads the registry without subscribing. Lifecycle callbacks cannot create
  /// inherited-widget dependencies, but still need to stop active media.
  static ActiveLearningModuleRegistry? read(BuildContext context) => context
      .getInheritedWidgetOfExactType<ActiveLearningModuleScope>()
      ?.notifier;
}
