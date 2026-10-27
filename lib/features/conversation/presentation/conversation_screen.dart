import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.isOffline = false,
    this.offlineLanguageReady,
    this.ensureDeviceConnected,
    this.isDeviceConnectionReady,
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
  final bool isOffline;
  final bool? offlineLanguageReady;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenSettings;
  final Future<bool> Function()? ensureDeviceConnected;
  final bool Function()? isDeviceConnectionReady;
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

class _TranslationLanguageSelector extends StatefulWidget {
  const _TranslationLanguageSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final TranslationOutputLanguage selected;
  final bool enabled;
  final ValueChanged<TranslationOutputLanguage> onSelected;

  @override
  State<_TranslationLanguageSelector> createState() =>
      _TranslationLanguageSelectorState();
}

class _TranslationLanguageSelectorState
    extends State<_TranslationLanguageSelector> {
  final MenuController _menu = MenuController();

  @override
  void didUpdateWidget(_TranslationLanguageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_menu.isOpen &&
        (!widget.enabled || widget.selected != oldWidget.selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen) _menu.close();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navy = isDark ? AppColors.darkPrimary : AppColors.primaryNavy;
    final stacked = MediaQuery.textScalerOf(context).scale(17) > 23;
    final menuWidth = (MediaQuery.sizeOf(context).width - 56)
        .clamp(0.0, 220.0)
        .toDouble();
    final languages = TranslationOutputLanguage.values;
    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(4, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? AppColors.darkSurfaceRaised : Colors.white,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: const WidgetStatePropertyAll(Color(0x260B2C66)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
            ),
          ),
        ),
      ),
      menuChildren: <Widget>[
        SizedBox(
          key: const Key('translation-language-menu'),
          width: menuWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (
                var row = 0;
                row < (languages.length + 1) ~/ 2;
                row++
              ) ...<Widget>[
                if (row > 0) const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (var column = 0; column < 2; column++) ...<Widget>[
                      if (column > 0) const SizedBox(width: 6),
                      Expanded(
                        child: row * 2 + column < languages.length
                            ? _languageOption(
                                languages[row * 2 + column],
                                isDark: isDark,
                                navy: navy,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
      builder: (context, controller, _) {
        final label = Text(
          context.tr('Dịch sang', '翻译成'),
          style: TextStyle(
            color: navy,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        );
        final pill = Material(
          color: isDark ? AppColors.darkSurfaceRaised : Colors.white,
          borderRadius: BorderRadius.circular(25),
          child: InkWell(
            key: const Key('translation-output-language'),
            onTap: widget.enabled
                ? () =>
                      controller.isOpen ? controller.close() : controller.open()
                : null,
            borderRadius: BorderRadius.circular(25),
            child: Container(
              height: stacked ? 68 : 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark
                      ? AppColors.darkOutline
                      : const Color(0xFF9CECCE),
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.translate_rounded,
                    color: isDark ? AppColors.darkMint : AppColors.mint,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  if (stacked)
                    Expanded(
                      child: Text(
                        widget.selected.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: widget.enabled ? navy : theme.disabledColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Text(
                      widget.selected.label,
                      style: TextStyle(
                        color: widget.enabled ? navy : theme.disabledColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: navy,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        );
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              label,
              const SizedBox(height: 6),
              SizedBox(width: menuWidth, child: pill),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[label, const SizedBox(width: 10), pill],
        );
      },
    );
  }

  Widget _languageOption(
    TranslationOutputLanguage language, {
    required bool isDark,
    required Color navy,
  }) {
    final selected = language == widget.selected;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? (isDark ? AppColors.darkSurfaceStrong : AppColors.mintSoft)
            : (isDark ? AppColors.darkSurface : const Color(0xFFF3F6FC)),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('translation-language-${language.apiValue}'),
          onTap: widget.enabled
              ? () {
                  _menu.close();
                  widget.onSelected(language);
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        language.label,
                        maxLines: 1,
                        style: TextStyle(
                          color: navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle_rounded, color: navy, size: 21),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

  String _offlineStatusText(BuildContext context) {
    final ready = widget.offlineLanguageReady;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      if (widget.controller.outputLanguage !=
          TranslationOutputLanguage.english) {
        return context.tr(
          'Bạn đang ngoại tuyến. Ngôn ngữ này cần Internet; hãy kết nối mạng rồi thử lại nhé.',
          '当前处于离线状态。此语言需要网络连接，请联网后重试。',
        );
      }
      if (ready == null) {
        return context.tr(
          'Bạn đang ngoại tuyến. HOMI đang kiểm tra dữ liệu trên thiết bị.',
          '当前处于离线状态。HOMI 正在检查设备上的数据。',
        );
      }
      return ready
          ? context.tr(
              'Bạn đang ngoại tuyến. HOMI vẫn có thể nghe và dịch tiếng Anh trên thiết bị.',
              '当前处于离线状态。HOMI 仍可在设备上识别语音并翻译成英语。',
            )
          : context.tr(
              'Bạn đang ngoại tuyến. Nói và dịch tiếng Anh chưa sẵn sàng trên thiết bị; hãy kết nối mạng rồi thử lại nhé.',
              '当前处于离线状态。设备上的英语语音和翻译尚未就绪，请联网后重试。',
            );
    }
    if (ready == null) {
      return context.tr(
        'Đang ngoại tuyến. HOMI đang kiểm tra dữ liệu offline trên thiết bị.',
        '当前离线，正在检查设备上的离线数据。',
      );
    }
    return ready
        ? context.tr(
            'Đang ngoại tuyến. Bạn vẫn có thể nói và dịch sang tiếng Anh.',
            '当前离线，仍可在设备上说话并翻译成英语。',
          )
        : context.tr(
            'Đang ngoại tuyến. Gói nói và dịch tiếng Anh chưa sẵn sàng; HOMI sẽ tải khi có Wi-Fi.',
            '当前离线，英语语音和翻译包尚未就绪；连接 Wi-Fi 后会自动下载。',
          );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).height < 900;
        final mobileLanguageMenu =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);
        final needsDeviceConnection =
            widget.ensureDeviceConnected != null &&
            !(widget.isDeviceConnectionReady?.call() ??
                widget.controller.isHomiReady);
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
                      isReady: widget.controller.isHomiReady,
                      connectionState: widget.controller.homiConnectionState(),
                      onHistory: () =>
                          unawaited(_openOtherScreen(widget.onOpenHistory)),
                      onSettings: () =>
                          unawaited(_openOtherScreen(widget.onOpenSettings)),
                      historyButtonKey: widget.historyButtonKey,
                      settingsButtonKey: widget.settingsButtonKey,
                    ),
                    HomiConnectionNotice(
                      status: HomiConnectionPresentation.from(
                        widget.controller.homiConnectionState(),
                        isReady: widget.controller.isHomiReady,
                      ),
                    ),
                    if (widget.isOffline)
                      Padding(
                        key: const Key('conversation-offline-status'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(Icons.wifi_off_rounded, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _offlineStatusText(context),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
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
                              compact ? 24 : 64,
                              24,
                              10,
                            ),
                            child: Column(
                              children: <Widget>[
                                if (widget
                                    .controller
                                    .supportsTranslationTargets)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: mobileLanguageMenu
                                        ? _TranslationLanguageSelector(
                                            selected: widget
                                                .controller
                                                .outputLanguage,
                                            enabled:
                                                !widget.controller.isBusy &&
                                                !widget
                                                    .controller
                                                    .sentenceQueueActive,
                                            onSelected: widget
                                                .controller
                                                .setOutputLanguage,
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Text(
                                                context.tr('Dịch sang', '翻译成'),
                                              ),
                                              const SizedBox(width: 12),
                                              DropdownButton<
                                                TranslationOutputLanguage
                                              >(
                                                key: const Key(
                                                  'translation-output-language',
                                                ),
                                                value: widget
                                                    .controller
                                                    .outputLanguage,
                                                onChanged:
                                                    widget.controller.isBusy ||
                                                        widget
                                                            .controller
                                                            .sentenceQueueActive
                                                    ? null
                                                    : (language) {
                                                        if (language != null) {
                                                          widget.controller
                                                              .setOutputLanguage(
                                                                language,
                                                              );
                                                        }
                                                      },
                                                items: [
                                                  for (final language
                                                      in TranslationOutputLanguage
                                                          .values)
                                                    DropdownMenuItem(
                                                      value: language,
                                                      child: Text(
                                                        language.label,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                  ),
                                VoiceHero(
                                  needsDeviceConnection: needsDeviceConnection,
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
                                      '${previous.displayedTranslation}',
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
                                  outputLanguage:
                                      widget.controller.outputLanguage,
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
                      needsDeviceConnection: needsDeviceConnection,
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
