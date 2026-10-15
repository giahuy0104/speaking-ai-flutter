import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/scenic_app_header.dart';
import '../../../l10n/display_language.dart';
import '../domain/conversation_models.dart';
import 'conversation_controller.dart';
import 'widgets/result_panel.dart';
import 'widgets/speak_action_bar.dart';
import 'widgets/translation_voice_picker.dart';
import 'widgets/voice_hero.dart';

class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    required this.controller,
    required this.onOpenHistory,
    required this.onOpenSettings,
    this.speakActionKey,
    this.resultPanelKey,
    this.historyButtonKey,
    this.settingsButtonKey,
    super.key,
  });

  final ConversationController controller;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final Key? speakActionKey;
  final Key? resultPanelKey;
  final Key? historyButtonKey;
  final Key? settingsButtonKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).height < 900;
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LearningScenery(
              overlayOpacity: 0.025,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: <Widget>[
                    ScenicAppHeader(
                      isReady: controller.isInputAvailable,
                      onHistory: onOpenHistory,
                      onSettings: onOpenSettings,
                      historyButtonKey: historyButtonKey,
                      settingsButtonKey: settingsButtonKey,
                    ),
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.android)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 24, top: 4),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: <Widget>[
                              Builder(
                                builder: (localizedContext) =>
                                    PopupMenuButton<TranslationOutputLanguage>(
                                      key: const Key(
                                        'translation-output-language-button',
                                      ),
                                      enabled: !controller.isBusy,
                                      tooltip: localizedContext.tr(
                                        'Chọn ngôn ngữ dịch ra',
                                        '选择翻译目标语言',
                                      ),
                                      onSelected: controller
                                          .setTranslationOutputLanguage,
                                      itemBuilder: (context) => [
                                        for (final language
                                            in TranslationOutputLanguage.values)
                                          PopupMenuItem<
                                            TranslationOutputLanguage
                                          >(
                                            value: language,
                                            child: Text(
                                              context.tr(
                                                language.vietnameseName,
                                                language.chineseName,
                                              ),
                                            ),
                                          ),
                                      ],
                                      child: Chip(
                                        avatar: const Icon(
                                          Icons.translate_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          localizedContext.tr(
                                            'Dịch ra: ${controller.outputLanguage.vietnameseName}',
                                            '译成：${controller.outputLanguage.chineseName}',
                                          ),
                                        ),
                                      ),
                                    ),
                              ),
                              if (controller.outputLanguage ==
                                      TranslationOutputLanguage.japanese ||
                                  controller.outputLanguage ==
                                      TranslationOutputLanguage.korean ||
                                  controller.outputLanguage ==
                                      TranslationOutputLanguage.french)
                                TranslationVoicePicker(
                                  language: controller.outputLanguage,
                                  controller: controller,
                                ),
                            ],
                          ),
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
                                  phase: controller.phase,
                                  processingStage: controller.processingStage,
                                  amplitude: controller.amplitude,
                                  isPreparingMicrophone:
                                      controller.isPreparingMicrophone,
                                  onStop: () => unawaited(
                                    controller.stopRecording(manual: true),
                                  ),
                                ),
                                SizedBox(height: compact ? 8 : 18),
                                ResultPanel(
                                  key: resultPanelKey,
                                  result: controller.result,
                                  outputLanguage: controller.outputLanguage,
                                  onPlay: () =>
                                      unawaited(controller.playResult()),
                                ),
                                if (controller.errorMessage != null ||
                                    controller.transientMessage !=
                                        null) ...<Widget>[
                                  const SizedBox(height: 12),
                                  _InlineMessage(
                                    isError: controller.errorMessage != null,
                                    message:
                                        controller.errorMessage ??
                                        controller.transientMessage!,
                                    onDismiss: controller.clearMessage,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SpeakActionBar(
                      key: speakActionKey,
                      phase: controller.phase,
                      processingStage: controller.processingStage,
                      isPreparingMicrophone: controller.isPreparingMicrophone,
                      onPressed: () => unawaited(controller.onPrimaryAction()),
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
    required this.message,
    required this.onDismiss,
  });

  final bool isError;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isError
        ? theme.colorScheme.error
        : (isDark ? theme.colorScheme.onTertiaryContainer : AppColors.ink);
    final localizedMessage = context.trKnown(message);
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
                    : AppColors.lavender),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isError
                  ? Icons.error_outline_rounded
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
