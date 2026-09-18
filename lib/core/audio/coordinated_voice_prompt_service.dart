import 'dart:async';

import 'audio_turn_coordinator.dart';
import 'audio_diagnostics.dart';
import 'hfp_audio_control.dart';
import 'voice_prompt_service_base.dart';

/// Adds process-wide prompt ownership without changing the platform prompt
/// implementation or its public contract.
class CoordinatedVoicePromptService
    implements
        VoicePromptService,
        AuthoredPromptBudgetProvider,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  CoordinatedVoicePromptService({
    required VoicePromptService delegate,
    required AudioTurnCoordinator coordinator,
    required AudioTurnOwner owner,
    HfpAudioControl? selectedOutputRoute,
  }) : _delegate = delegate,
       _coordinator = coordinator,
       _owner = owner,
       _selectedOutputRoute = selectedOutputRoute;

  final VoicePromptService _delegate;
  final AudioTurnCoordinator _coordinator;
  final AudioTurnOwner _owner;
  // A dedicated coordinator scope, supplied only for Android native prompts.
  // A connected HFP-only headset is not a media output until SCO is confirmed.
  final HfpAudioControl? _selectedOutputRoute;
  AudioTurnCancellation _pendingCancellation = AudioTurnCancellation();
  AudioTurnLease? _activeLease;
  Future<void> Function()? _releaseActiveRoute;
  bool _disposed = false;

  @override
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  }) async {
    final delegate = _delegate;
    return !_disposed && delegate is AuthoredPromptBudgetProvider
        ? (delegate as AuthoredPromptBudgetProvider).authoredPromptBudget(
            text,
            locale: locale,
          )
        : null;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) => _runPrompt(
    () => _selectedOutputRoute == null
        ? _delegate.speak(text, locale: locale)
        : _delegate.speakAndWait(text, locale: locale),
  );

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      _runPrompt(() => _delegate.speakAndWait(text, locale: locale));

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => _runPrompt(() {
    final delegate = _delegate;
    return delegate is PhoneSpeakerVoicePromptService
        ? (delegate as PhoneSpeakerVoicePromptService)
              .speakAndWaitOnPhoneSpeaker(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  }, useSelectedRoute: false);

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => _runPrompt(() {
    final delegate = _delegate;
    return delegate is SelectedMediaOutputVoicePromptService
        ? (delegate as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  });

  @override
  Future<void> playSpeechReadyCue() => _runPrompt(() {
    AudioDiagnostics.event('cue.delegate', {'owner': _owner.name});
    final delegate = _delegate;
    return delegate is SpeechReadyCuePlayer
        ? (delegate as SpeechReadyCuePlayer).playSpeechReadyCue()
        : Future<void>.value();
  });

  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) => _runPrompt(() {
    final delegate = _delegate;
    if (delegate is StyledMediaOutputVoicePromptService) {
      return (delegate as StyledMediaOutputVoicePromptService)
          .speakAndWaitStyled(
            text,
            locale: locale,
            speechRate: speechRate,
            pitch: pitch,
          );
    }
    return delegate is SelectedMediaOutputVoicePromptService
        ? (delegate as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  });

  Future<void> _runPrompt(
    Future<void> Function() action, {
    bool useSelectedRoute = true,
  }) async {
    if (_disposed) {
      return;
    }
    final cancellation = _pendingCancellation;
    final diagnosticId = AudioDiagnostics.nextId();
    final diagnosticFields = <String, Object?>{
      'operation': diagnosticId,
      'owner': _owner.name,
    };
    AudioDiagnostics.event('prompt.lease.request', diagnosticFields);
    final lease = await _coordinator.acquire(
      owner: _owner,
      mode: AudioTurnMode.promptPlayback,
      cancellation: cancellation,
    );
    if (_disposed || cancellation.isCancelled) {
      await lease.release();
      return;
    }
    _activeLease = lease;
    AudioDiagnostics.event('prompt.lease.acquired', diagnosticFields);
    Future<void> Function()? releaseRoute;
    StreamSubscription<dynamic>? routeSubscription;
    HfpAudioException? routeLoss;
    Future<void>? routeLossStop;
    try {
      final route = useSelectedRoute ? _selectedOutputRoute : null;
      if (route != null) {
        await route.initialize();
        if (_disposed || cancellation.isCancelled) return;
        final status = route.status;
        if (status.isBridgeSupported &&
            (status.deviceId != null || status.isConnected)) {
          Future<void>? release;
          releaseRoute = () => release ??= route.stopAudioRoute();
          _releaseActiveRoute = releaseRoute;
          AudioDiagnostics.event(
            'prompt.route.start.request',
            diagnosticFields,
          );
          await route.startAudioRoute();
          AudioDiagnostics.event(
            'prompt.route.start.completed',
            diagnosticFields,
          );
          if (_disposed || cancellation.isCancelled) return;
          void checkSelectedRoute() {
            if (routeLoss != null || cancellation.isCancelled) return;
            if (!route.status.routeActive || !route.status.isConnected) {
              routeLoss = const HfpAudioException(
                'Đường âm thanh H20 đã ngắt. Hãy kết nối lại để tiếp tục.',
              );
              // Also invalidates a prompt still loading its authored asset,
              // before there is any native player for the bridge to stop.
              routeLossStop = _delegate.stop();
            }
          }

          routeSubscription = route.statusChanges.listen(
            (_) => checkSelectedRoute(),
          );
          checkSelectedRoute();
          if (routeLoss != null) throw routeLoss!;
        }
      }
      if (_disposed || cancellation.isCancelled) return;
      AudioDiagnostics.event('prompt.delegate.start', diagnosticFields);
      await action();
      AudioDiagnostics.event('prompt.delegate.completed', diagnosticFields);
      if (routeLoss != null) throw routeLoss!;
    } catch (_) {
      AudioDiagnostics.event('prompt.failed', diagnosticFields);
      if (!_disposed && !cancellation.isCancelled) rethrow;
    } finally {
      // Finish this exact scope before granting another audio turn. An old
      // prompt's finally/stop must never release a newer prompt's HFP route.
      try {
        await routeSubscription?.cancel();
        try {
          await routeLossStop;
        } finally {
          AudioDiagnostics.event(
            'prompt.route.release.request',
            diagnosticFields,
          );
          await releaseRoute?.call();
          AudioDiagnostics.event(
            'prompt.route.release.completed',
            diagnosticFields,
          );
        }
      } finally {
        if (identical(_releaseActiveRoute, releaseRoute)) {
          _releaseActiveRoute = null;
        }
        if (identical(_activeLease, lease)) {
          _activeLease = null;
        }
        await lease.release();
        AudioDiagnostics.event('prompt.lease.released', diagnosticFields);
      }
    }
  }

  @override
  Future<String?> beginMainTurn() async {
    final delegate = _delegate;
    return delegate is MainTurnVoicePromptService
        ? (delegate as MainTurnVoicePromptService).beginMainTurn()
        : null;
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    final delegate = _delegate;
    if (delegate is MainTurnVoicePromptService) {
      await (delegate as MainTurnVoicePromptService).endMainTurn(
        reason,
        turnId: turnId,
      );
    }
  }

  @override
  Future<void> stop() async {
    _pendingCancellation.cancel();
    _pendingCancellation = AudioTurnCancellation();
    final lease = _activeLease;
    final releaseRoute = _releaseActiveRoute;
    _activeLease = null;
    _releaseActiveRoute = null;
    try {
      if (lease != null && lease.isCurrent) {
        await _delegate.stop();
      }
    } finally {
      try {
        await releaseRoute?.call();
      } finally {
        await lease?.release();
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
  }
}
