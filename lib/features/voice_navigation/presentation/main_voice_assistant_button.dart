import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/main_assistant_audio_state.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/device/active_learning_module.dart';
import '../application/main_button_activation_policy.dart';
import '../application/main_speaking_session_controller.dart';
import '../application/voice_navigation_controller.dart';
import 'homi_assistant_bubble.dart';

class MainVoiceAssistantButton extends StatelessWidget {
  const MainVoiceAssistantButton({
    required this.voiceController,
    required this.audioState,
    this.activeLearningRegistry,
    required this.speakingSessionController,
    required this.isActivationPending,
    required this.onPressed,
    required this.onLongPressed,
    required this.onLongPressReleased,
    super.key,
  });

  final VoiceNavigationController voiceController;
  final MainAssistantAudioState audioState;
  final ActiveLearningModuleRegistry? activeLearningRegistry;
  final MainSpeakingSessionController speakingSessionController;
  final bool isActivationPending;
  final Future<void> Function() onPressed;
  final Future<void> Function() onLongPressed;
  final Future<void> Function() onLongPressReleased;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        voiceController,
        audioState,
        speakingSessionController,
        ?activeLearningRegistry,
      ]),
      builder: (context, _) {
        final speakingState = speakingSessionController.state;
        final isSpeakingMode = speakingSessionController.isActive;
        final canInterruptCollection =
            activeLearningRegistry != null &&
            MainButtonActivationPolicy.canInterruptVocabularyPlayback(
              isAndroid:
                  !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
              registry: activeLearningRegistry!,
            );
        final canActivate =
            MainButtonActivationPolicy.canStart(
              isActivationPending: isActivationPending,
              isMainButtonSessionActive:
                  voiceController.isMainButtonSessionActive,
              replaceActiveSession: canInterruptCollection,
            ) &&
            (isSpeakingMode ||
                canInterruptCollection ||
                (!audioState.isBusy && !audioState.isPlaybackPlaying));
        final microphoneError = voiceController.lastErrorMessage;
        final error =
            !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.iOS &&
                microphoneError != null
            ? voiceController.lastError
            : null;
        final showInterruptionGuidance =
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            error is StreamingSpeechInputException &&
            error.code == 'AUDIO_SESSION_INTERRUPTED' &&
            microphoneError != null;
        final commandError = voiceController.hasUnhandledLearningCommandError;
        final label = isSpeakingMode
            ? switch (speakingState) {
                MainSpeakingSessionState.ready => 'Đang chuẩn bị...',
                MainSpeakingSessionState.recording => 'Đang nghe...',
                MainSpeakingSessionState.processing =>
                  audioState.isPreparingMicrophone
                      ? 'Đang chuẩn bị...'
                      : 'Đang dịch...',
                MainSpeakingSessionState.playing => 'Đang phát...',
                MainSpeakingSessionState.inactive => 'Main',
              }
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAcknowledgingWakeWord
            ? 'HOMI đang nói...'
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isListening
            ? 'Đang nghe...'
            : voiceController.isMainButtonSessionActive &&
                  microphoneError != null
            ? commandError
                  ? 'Lệnh chưa xong'
                  : 'Đang thử lại mic...'
            : voiceController.isMainButtonSessionActive &&
                  (voiceController.isStarting ||
                      voiceController.isAwaitingCommand)
            ? 'Đang chuẩn bị mic...'
            : microphoneError != null
            ? commandError
                  ? 'Lệnh chưa xong'
                  : 'Thử lại mic'
            : 'Main';
        // Mirrors the label cascade above so each label has its own look.
        final activeVisual = isSpeakingMode
            ? switch (speakingState) {
                MainSpeakingSessionState.ready => HomiBubbleVisual.preparing,
                MainSpeakingSessionState.recording =>
                  HomiBubbleVisual.listening,
                MainSpeakingSessionState.processing =>
                  audioState.isPreparingMicrophone
                      ? HomiBubbleVisual.preparing
                      : HomiBubbleVisual.translating,
                MainSpeakingSessionState.playing => HomiBubbleVisual.playing,
                MainSpeakingSessionState.inactive => HomiBubbleVisual.idle,
              }
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isAcknowledgingWakeWord
            ? HomiBubbleVisual.homiSpeaking
            : voiceController.isMainButtonSessionActive &&
                  voiceController.isListening
            ? HomiBubbleVisual.listening
            : voiceController.isMainButtonSessionActive &&
                  microphoneError != null
            ? commandError
                  ? HomiBubbleVisual.commandError
                  : HomiBubbleVisual.retrying
            : voiceController.isMainButtonSessionActive &&
                  (voiceController.isStarting ||
                      voiceController.isAwaitingCommand)
            ? HomiBubbleVisual.preparing
            : microphoneError != null
            ? commandError
                  ? HomiBubbleVisual.commandError
                  : HomiBubbleVisual.micError
            : HomiBubbleVisual.idle;
        final visual = activeVisual == HomiBubbleVisual.idle && !canActivate
            ? HomiBubbleVisual.busy
            : activeVisual;
        final showLabel =
            visual != HomiBubbleVisual.idle && visual != HomiBubbleVisual.busy;
        final microphoneStatus = microphoneError == null
            ? '${voiceController.activeInputLabel}: $label'
            : '$microphoneError Bấm HOMI để thử lại.';

        final mainControl = Semantics(
          button: true,
          label: canActivate
              ? isSpeakingMode
                    ? 'Main, dừng phiên dịch và mở HOMI'
                    : canInterruptCollection
                    ? 'Main, dừng âm thanh bộ từ vựng và gọi HOMI'
                    : microphoneError == null
                    ? 'Main, gọi HOMI để chọn tính năng'
                    : microphoneStatus
              : '$microphoneStatus Vui lòng chờ.',
          child: RawGestureDetector(
            // STOP remains available while the short-press bubble is disabled.
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 1500),
                    ),
                    (recognizer) {
                      recognizer.onLongPress = () => unawaited(onLongPressed());
                      recognizer.onLongPressEnd = (_) =>
                          unawaited(onLongPressReleased());
                      recognizer.onLongPressCancel = () =>
                          unawaited(onLongPressReleased());
                    },
                  ),
            },
            child: Tooltip(
              message: microphoneStatus,
              // A long-press tooltip would claim LONG after 500 ms, before
              // MAIN's 1.5-second STOP gesture can win the gesture arena.
              triggerMode: TooltipTriggerMode.manual,
              child: HomiAssistantBubble(
                key: const Key('main-voice-assistant-button'),
                visual: visual,
                label: showLabel ? label : null,
                onPressed: canActivate ? () => unawaited(onPressed()) : null,
              ),
            ),
          ),
        );
        if (!showInterruptionGuidance) return mainControl;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
                  0.0,
                  320.0,
                ),
              ),
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      microphoneError,
                      key: const Key('main-audio-interruption-guidance'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            mainControl,
          ],
        );
      },
    );
  }
}
