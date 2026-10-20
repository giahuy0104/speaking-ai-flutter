import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_connection_presentation.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/scenic_app_header.dart';
import '../../../l10n/display_language.dart';
import '../domain/conversation_models.dart';
import 'conversation_controller.dart';
import 'widgets/result_panel.dart';
import 'widgets/speak_action_bar.dart';
import 'widgets/voice_hero.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.controller,
    required this.onOpenHistory,
    required this.onOpenSettings,
    this.ensureDeviceConnected,
    this.sessionActive = false,
    this.isStoppingSession = false,
    this.onStopSession,
    this.speakActionKey,
    this.resultPanelKey,
    this.historyButtonKey,
    this.settingsButtonKey,
    super.key,
  });

  final ConversationController controller;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final Future<bool> Function()? ensureDeviceConnected;
  final bool sessionActive;
  final bool isStoppingSession;
  final Future<void> Function()? onStopSession;
  final Key? speakActionKey;
  final Key? resultPanelKey;
  final Key? historyButtonKey;
  final Key? settingsButtonKey;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _waitingForDevice = false;
  bool _stoppingSession = false;
  int _actionGeneration = 0;

  Future<void> _openOtherScreen(VoidCallback open) async {
    if (widget.controller.sentenceQueueActive) {
      await widget.controller.cancelCurrentMainAction();
    }
    if (mounted) open();
  }

  @override
  void dispose() {
    if (widget.controller.sentenceQueueActive) {
      unawaited(widget.controller.cancelCurrentMainAction());
    }
    super.dispose();
  }

  Future<void> _stopSession() async {
    final stop = widget.onStopSession;
    if (stop == null || _stoppingSession || widget.isStoppingSession) return;
    _actionGeneration++;
    setState(() => _stoppingSession = true);
    try {
      await stop();
    } finally {
      if (mounted) setState(() => _stoppingSession = false);
    }
  }

  Future<void> _onPrimaryAction() async {
    if (_stoppingSession || widget.isStoppingSession) return;
    final controller = widget.controller;
    if (controller.phase == ConversationPhase.recording) {
      await controller.onPrimaryAction();
      return;
    }
    if (_waitingForDevice) return;
    final generation = _actionGeneration;
    _waitingForDevice = true;
    try {
      final ensureConnected = widget.ensureDeviceConnected;
      if (ensureConnected != null && !await ensureConnected()) return;
      if (!mounted ||
          generation != _actionGeneration ||
          !identical(controller, widget.controller) ||
          controller.phase == ConversationPhase.recording ||
          controller.phase == ConversationPhase.processing) {
        return;
      }
      await controller.onPrimaryAction();
    } finally {
      _waitingForDevice = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).height < 900;
        return DisplayLanguageScope(
          language: widget.controller.displayLanguage,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LearningScenery(
              overlayOpacity: 0.025,
              child: SafeArea(
                bottom: true,
                child: Column(
                  children: <Widget>[
                    ScenicAppHeader(
                      isReady: widget.controller.isH20Ready,
                      connectionState: widget.controller.h20ConnectionState(),
                      onHistory: () =>
                          unawaited(_openOtherScreen(widget.onOpenHistory)),
                      onSettings: () =>
                          unawaited(_openOtherScreen(widget.onOpenSettings)),
                      historyButtonKey: widget.historyButtonKey,
                      settingsButtonKey: widget.settingsButtonKey,
                    ),
                    HomiConnectionNotice(
                      status: HomiConnectionPresentation.from(
                        widget.controller.h20ConnectionState(),
                        isReady: widget.controller.isH20Ready,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SingleChildScrollView(
                            key: const Key('conversation-home-scroll'),
                            padding: EdgeInsets.fromLTRB(
                              24,
                              compact ? 8 : 28,
                              24,
                              10,
                            ),
                            child: Column(
                              children: <Widget>[
                                VoiceHero(
                                  phase: widget.controller.phase,
                                  processingStage:
                                      widget.controller.processingStage,
                                  amplitude: widget.controller.amplitude,
                                  isPreparingMicrophone:
                                      widget.controller.isPreparingMicrophone,
                                  onStop: () => unawaited(
                                    widget.controller.stopRecording(
                                      manual: true,
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 8 : 18),
                                if (widget.controller.sentenceProgress != null)
                                  Text(widget.controller.sentenceProgress!),
                                if (widget.controller.sentenceQueueActive)
                                  TextButton.icon(
                                    onPressed: () => unawaited(
                                      widget.controller
                                          .cancelCurrentMainAction(),
                                    ),
                                    icon: const Icon(Icons.stop),
                                    label: const Text('Dừng phát'),
                                  ),
                                for (final previous
                                    in widget.controller.sentenceResults.where(
                                      (item) => !identical(
                                        item,
                                        widget.controller.result,
                                      ),
                                    ))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      '${previous.vietnameseText}\n'
                                      '${previous.englishText}',
                                    ),
                                  ),
                                if (widget
                                    .controller
                                    .sentenceResults
                                    .isNotEmpty)
                                  const Text(
                                    'Nghe lại áp dụng cho câu đang hiển thị '
                                    'bên dưới, sau khi hàng đợi dừng.',
                                  ),
                                ResultPanel(
                                  key: widget.resultPanelKey,
                                  result: widget.controller.result,
                                  onPlay: () =>
                                      unawaited(widget.controller.playResult()),
                                ),
                                if (widget.controller.errorMessage != null ||
                                    widget.controller.transientMessage !=
                                        null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  _InlineMessage(
                                    isError:
                                        widget.controller.errorMessage != null,
                                    isConnectionReady:
                                        widget.controller.transientMessage ==
                                        ConversationController
                                            .connectionReadyMessage,
                                    message:
                                        widget.controller.errorMessage ??
                                        widget.controller.transientMessage!,
                                    onDismiss: widget.controller.clearMessage,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if ((widget.sessionActive ||
                            widget.isStoppingSession ||
                            _stoppingSession) &&
                        widget.onStopSession != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Builder(
                          builder: (context) {
                            final stopping =
                                _stoppingSession || widget.isStoppingSession;
                            return OutlinedButton.icon(
                              key: const Key('conversation-stop-session'),
                              onPressed: stopping
                                  ? null
                                  : () => unawaited(_stopSession()),
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(
                                stopping
                                    ? context.tr('Đang dừng phiên…', '正在结束对话…')
                                    : context.tr('Dừng phiên', '结束对话'),
                              ),
                            );
                          },
                        ),
                      ),
                    SpeakActionBar(
                      key: widget.speakActionKey,
                      phase: widget.controller.phase,
                      processingStage: widget.controller.processingStage,
                      isPreparingMicrophone:
                          widget.controller.isPreparingMicrophone,
                      onPressed: () => unawaited(_onPrimaryAction()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.isError,
    required this.isConnectionReady,
    required this.message,
    required this.onDismiss,
  });

  final bool isError;
  final bool isConnectionReady;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isError
        ? theme.colorScheme.error
        : (isDark
              ? theme.colorScheme.onTertiaryContainer
              : AppColors.primaryNavy);
    final localizedMessage = isConnectionReady
        ? context.tr(
            ConversationController.connectionReadyMessage,
            'HOMI 设备已连接，准备好一起学习啦！',
          )
        : context.trKnown(message);
    return Semantics(
      liveRegion: true,
      label: localizedMessage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: isError
              ? theme.colorScheme.errorContainer
              : (isDark
                    ? theme.colorScheme.tertiaryContainer
                    : isConnectionReady
                    ? AppColors.mintSoft
                    : AppColors.lavender),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : isConnectionReady
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: color,
              size: 21,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localizedMessage,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
            if (!isConnectionReady)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                tooltip: context.tr('Ẩn thông báo', '隐藏通知'),
              ),
          ],
        ),
      ),
    );
  }
}
