import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_connection_presentation.dart';
import '../../../app/learning_rail_metrics.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/scenic_app_header.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/device_connection_coordinator.dart';
import '../../../l10n/display_language.dart';
import '../../../presentation/device/device_ble_picker_flow.dart';
import '../../../presentation/device/device_hfp_picker_flow.dart';
import '../domain/conversation_models.dart';
import 'conversation_controller.dart';
import 'widgets/homi_hero_3d.dart';
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
    this.connectionCoordinator,
    this.resumeForegroundAudio,
    this.audioInterruptionGeneration,
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
  final DeviceConnectionCoordinator? connectionCoordinator;
  final Future<bool> Function()? resumeForegroundAudio;
  final int Function()? audioInterruptionGeneration;
  final bool Function()? isDeviceConnectionReady;
  final bool sessionActive;
  final bool isStoppingSession;
  final Future<void> Function()? onStopSession;
  final Key? speakActionKey;
  final Key? resultPanelKey;
  final Key? historyButtonKey;
  final Key? settingsButtonKey;

  static const double headerHeight = ScenicAppHeader.height;
  static const double railHeight = LearningRailMetrics.collapsedHeight;
  static const double railWidth = LearningRailMetrics.collapsedWidth;

  /// Room the hero band keeps besides HOMI: 4 px top margin, the wave row
  /// and an 8 px gap.
  static const double _heroBandExtras = 4 + VoiceHero.mobileWaveBoxHeight + 8;

  /// Home's rails sit level with HOMI and end a little before half the
  /// screen, leaving the lower part to the study card.
  static double railTop(Size screen, double safeTop) =>
      math.max(safeTop + headerHeight + 24, screen.height * 0.45 - railHeight);

  /// On phones HOMI and the wave fill at least this band, which ends just
  /// below the rails, so the study card always has the full width.
  static double heroBandHeight(Size screen, double safeTop) =>
      railTop(screen, safeTop) + railHeight + 8 - (safeTop + headerHeight);

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

/// Round mint "translate" button for the header. The badge shows the target
/// language; tapping opens a list of every target.
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

  void _onPressed() {
    if (!widget.enabled) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              context.tr(
                'Chờ HOMI xong việc rồi đổi ngôn ngữ nhé',
                '请等 HOMI 完成后再切换语言',
              ),
            ),
          ),
        );
      return;
    }
    _menu.isOpen ? _menu.close() : _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navy = isDark ? AppColors.darkPrimary : AppColors.primaryNavy;
    final mint = isDark ? AppColors.darkMint : AppColors.success;
    final menuWidth = (MediaQuery.sizeOf(context).width - 40)
        .clamp(0.0, 236.0)
        .toDouble();
    return MenuAnchor(
      controller: _menu,
      // Right-align the list under the 52 px button.
      alignmentOffset: Offset(-(menuWidth - 52), 8),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? AppColors.darkSurfaceRaised : Colors.white,
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: const WidgetStatePropertyAll(Color(0x400B2C66)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Text(
                  context.tr('Dịch tiếng Việt sang', '把越南语翻译成'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDark ? AppColors.darkMuted : AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final language in TranslationOutputLanguage.values)
                _languageOption(language, isDark: isDark, navy: navy),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) {
        final open = controller.isOpen;
        return Semantics(
          button: true,
          enabled: widget.enabled,
          label: context.tr(
            'Dịch sang ${widget.selected.label}. Bấm để đổi ngôn ngữ',
            '翻译成${widget.selected.label}，点击切换语言',
          ),
          child: Tooltip(
            message: context.tr('Đổi ngôn ngữ dịch', '切换翻译语言'),
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.6,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const Key('translation-output-language'),
                  customBorder: const CircleBorder(),
                  onTap: _onPressed,
                  child: SizedBox.square(
                    dimension: 52,
                    // Two tilted letter tiles: "Aa" for Vietnamese behind,
                    // the target language in front.
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned(
                          left: 2,
                          top: 2,
                          child: _LetterTile(
                            text: 'Aa',
                            angle: -0.21,
                            fontSize: 12,
                            alignTop: true,
                            textColor: widget.enabled
                                ? AppColors.accentPink
                                : theme.disabledColor,
                            colors: const <Color>[
                              Colors.white,
                              Color(0xFFFFEEF2),
                            ],
                            edge: const Color(0xFFF6C9D4),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: _LetterTile(
                            text: widget.selected.badge,
                            angle: 0.14,
                            fontSize: 14,
                            textColor: widget.enabled
                                ? AppColors.primaryNavy
                                : theme.disabledColor,
                            colors: widget.enabled
                                ? const <Color>[
                                    Color(0xFFEAFFF7),
                                    Color(0xFFC8F0DF),
                                  ]
                                : const <Color>[
                                    Color(0xFFF2F4F7),
                                    Color(0xFFE1E5EB),
                                  ],
                            edge: widget.enabled
                                ? const Color(0xFFA9DCC6)
                                : const Color(0xFFCDD3DC),
                            ring: open ? mint : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    final mint = isDark ? AppColors.darkMint : AppColors.success;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? (isDark ? AppColors.darkSurfaceStrong : AppColors.mintSoft)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('translation-language-${language.apiValue}'),
          onTap: widget.enabled
              ? () {
                  _menu.close();
                  widget.onSelected(language);
                }
              : null,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? mint
                          : (isDark
                                ? AppColors.darkSurface
                                : const Color(0xFFF1F5FB)),
                    ),
                    child: Text(
                      language.badge,
                      style: TextStyle(
                        color: selected
                            ? (isDark ? AppColors.darkSurface : Colors.white)
                            : navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      language.label,
                      maxLines: 2,
                      style: TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, color: mint, size: 20),
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

/// One tilted, raised letter tile of the language button.
class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.text,
    required this.angle,
    required this.fontSize,
    required this.textColor,
    required this.colors,
    required this.edge,
    this.alignTop = false,
    this.ring,
  });

  final String text;
  final double angle;
  final double fontSize;
  final Color textColor;
  final List<Color> colors;

  /// Solid bottom edge that gives the tile its thickness.
  final Color edge;

  /// The back tile shows its letters near the top, above the front tile.
  final bool alignTop;

  /// Focus ring shown while the language list is open.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 30,
        height: 32,
        alignment: alignTop ? Alignment.topCenter : Alignment.center,
        padding: EdgeInsets.only(top: alignTop ? 3 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(color: edge, offset: const Offset(0, 3)),
            const BoxShadow(
              color: Color(0x1F142451),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
            if (ring case final color?)
              BoxShadow(color: color.withValues(alpha: 0.35), spreadRadius: 3),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationScreenState extends State<ConversationScreen> {
  bool _waitingForDevice = false;
  bool _connectingDevice = false;
  bool _stoppingSession = false;
  int _actionGeneration = 0;
  late DeviceHfpPickerFlow _hfpPickerFlow;
  late DeviceBlePickerFlow _blePickerFlow;

  @override
  void initState() {
    super.initState();
    _hfpPickerFlow = DeviceHfpPickerFlow(
      controller: widget.controller,
      connectionCoordinator: widget.connectionCoordinator,
    );
    _blePickerFlow = DeviceBlePickerFlow(
      controller: widget.controller,
      connectionCoordinator: widget.connectionCoordinator,
    );
  }

  @override
  void didUpdateWidget(ConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.connectionCoordinator != widget.connectionCoordinator) {
      final previousHfp = _hfpPickerFlow;
      _hfpPickerFlow = DeviceHfpPickerFlow(
        controller: widget.controller,
        connectionCoordinator: widget.connectionCoordinator,
      );
      unawaited(previousHfp.cancel());
      previousHfp.dispose();
      final previousBle = _blePickerFlow;
      _blePickerFlow = DeviceBlePickerFlow(
        controller: widget.controller,
        connectionCoordinator: widget.connectionCoordinator,
      );
      unawaited(previousBle.cancel());
      previousBle.dispose();
    }
  }

  Future<void> _openOtherScreen(VoidCallback open) async {
    if (widget.resumeForegroundAudio != null) _actionGeneration++;
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
    _hfpPickerFlow.dispose();
    _blePickerFlow.dispose();
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
    final canContinue = widget.resumeForegroundAudio != null
        ? controller.capturePrimaryActionGuard()
        : () => true;
    final audioGeneration = widget.audioInterruptionGeneration?.call();
    bool audioActionIsCurrent() =>
        canContinue() &&
        (widget.resumeForegroundAudio == null ||
            ModalRoute.of(context)?.isCurrent != false) &&
        audioGeneration == widget.audioInterruptionGeneration?.call();
    _waitingForDevice = true;
    try {
      final resumeAudio = widget.resumeForegroundAudio;
      if (resumeAudio != null && !await resumeAudio()) {
        if (mounted &&
            generation == _actionGeneration &&
            audioActionIsCurrent() &&
            identical(controller, widget.controller)) {
          controller.showHomiConnectionMessage(
            context.tr(
              'Âm thanh đang bị gián đoạn. Chờ tác vụ âm thanh kết thúc rồi thử lại.',
              '音频仍被中断。请等待当前音频任务结束后重试。',
            ),
          );
        }
        return;
      }
      if (!mounted ||
          generation != _actionGeneration ||
          !audioActionIsCurrent() ||
          !identical(controller, widget.controller)) {
        return;
      }
      final alreadyConnected =
          widget.isDeviceConnectionReady?.call() ?? controller.isHomiReady;
      if (!alreadyConnected) {
        setState(() => _connectingDevice = true);
        try {
          final power = widget.connectionCoordinator?.bluetoothPower;
          if (power != null &&
              power.state != Aiv0BluetoothAdapterState.poweredOn) {
            if (power.canRequestEnable) {
              // Android: request permission + request radio enable, then
              // keep going into the normal connect attempt below.
              await power.enable();
              if (!mounted ||
                  generation != _actionGeneration ||
                  !audioActionIsCurrent() ||
                  !identical(controller, widget.controller)) {
                return;
              }
            } else {
              // iOS can't enable the radio itself (Settings' own Bluetooth
              // panel shows the same limit -- it only offers a manual
              // recheck there).
              await _promptOpenBluetoothSettings(context);
              return;
            }
          }
          final coordinator = widget.connectionCoordinator;
          if (coordinator != null) {
            // Call the coordinator directly -- same primitive Settings' own
            // "Kết nối HOMI" button uses -- instead of
            // widget.ensureDeviceConnected, whose dialog only ever resolves
            // false on an explicit user Cancel and would never let us tell
            // "not found" apart from "cancelled".
            final connected = await coordinator.connect();
            if (!mounted ||
                generation != _actionGeneration ||
                !audioActionIsCurrent() ||
                !identical(controller, widget.controller)) {
              return;
            }
            if (!connected) {
              if (!controller.canUseAiv0Ble) {
                await _blePickerFlow.findAndConnectBle(
                  context,
                  onMessage: _showConnectionSnack,
                );
              } else if (!controller.isHomiReady) {
                await _hfpPickerFlow.findAndConnectHfp(
                  context,
                  onMessage: _showConnectionSnack,
                );
              }
              return;
            }
          } else {
            final ensureConnected = widget.ensureDeviceConnected;
            if (ensureConnected != null && !await ensureConnected()) return;
            if (!mounted ||
                generation != _actionGeneration ||
                !audioActionIsCurrent() ||
                !identical(controller, widget.controller)) {
              return;
            }
          }
        } finally {
          if (mounted) setState(() => _connectingDevice = false);
        }
      }
      if (!mounted ||
          generation != _actionGeneration ||
          !audioActionIsCurrent() ||
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

  Future<void> _promptOpenBluetoothSettings(BuildContext context) async {
    final coordinator = widget.connectionCoordinator;
    if (coordinator == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('conversation-open-bluetooth-settings-dialog'),
        icon: const Icon(Icons.bluetooth_disabled_rounded),
        title: Text(context.tr('Chưa tìm thấy HOMI', '未找到 HOMI')),
        content: Text(
          context.tr(
            'Hãy mở Bluetooth và kết nối với HOMI trong Cài đặt Bluetooth của điện thoại, sau đó quay lại thử lại.',
            '请在手机的蓝牙设置中打开蓝牙并连接 HOMI，然后返回重试。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('conversation-open-bluetooth-settings-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Hủy', '取消')),
          ),
          FilledButton(
            key: const Key('conversation-open-bluetooth-settings-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Mở Cài đặt Bluetooth', '打开蓝牙设置')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await coordinator.openBluetoothSettings();
    }
  }

  void _showConnectionSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _offlineStatusText(BuildContext context) {
    final ready = widget.offlineLanguageReady;
    if (ready == null) {
      return context.tr(
        'Đang ngoại tuyến. HOMI đang kiểm tra dữ liệu offline trên thiết bị.',
        '当前离线，正在检查设备上的离线数据。',
      );
    }
    return ready
        ? context.tr(
            'Đang ngoại tuyến. Bạn vẫn có thể nói và dịch sang ${widget.controller.outputLanguage.label}.',
            '当前离线，仍可在设备上说话并翻译成所选语言。',
          )
        : context.tr(
            'Đang ngoại tuyến. Gói nói hoặc dịch ${widget.controller.outputLanguage.label} chưa sẵn sàng; hãy kết nối Wi-Fi để chuẩn bị.',
            '当前离线，语音或所选语言的翻译模型尚未就绪；请连接 Wi-Fi 进行准备。',
          );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = MediaQuery.sizeOf(context).height < 900;
        final isMobileLayout =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);
        // Same formula Home uses to place its rails beside HOMI.
        final screenSize = MediaQuery.sizeOf(context);
        final heroBand = ConversationScreen.heroBandHeight(
          screenSize,
          MediaQuery.paddingOf(context).top,
        );
        // HOMI grows with its band (leaving room for the wave) while its
        // cloud stays inside the gap between the rails, 4 px clear of each.
        final railGap =
            screenSize.width - 2 * (ConversationScreen.railWidth + 4);
        final heroHeight = math
            .min(
              heroBand - ConversationScreen._heroBandExtras,
              railGap / (HomiHero3D.aspectRatio * HomiHero3D.cloudWidthFactor),
            )
            .clamp(140.0, 240.0);
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
                      leadingAction:
                          isMobileLayout &&
                              widget.controller.supportsTranslationTargets
                          ? _TranslationLanguageSelector(
                              selected: widget.controller.outputLanguage,
                              enabled:
                                  !widget.controller.isBusy &&
                                  !widget.controller.sentenceQueueActive,
                              onSelected: widget.controller.setOutputLanguage,
                            )
                          : null,
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
                      child: LayoutBuilder(
                        builder: (context, viewport) => Align(
                          // Phones keep HOMI right under the header; the
                          // study card takes the remaining height.
                          alignment: isMobileLayout
                              ? Alignment.topCenter
                              : Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: SingleChildScrollView(
                              key: const Key('conversation-home-scroll'),
                              padding: EdgeInsets.fromLTRB(
                                isMobileLayout ? 20 : 24,
                                isMobileLayout ? 0 : (compact ? 24 : 64),
                                isMobileLayout ? 20 : 24,
                                10,
                              ),
                              child: Column(
                                children: <Widget>[
                                  if (!isMobileLayout &&
                                      widget
                                          .controller
                                          .supportsTranslationTargets)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          Text(context.tr('Dịch sang', '翻译成')),
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
                                                  child: Text(language.label),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: isMobileLayout ? heroBand : 0,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: VoiceHero(
                                        useMobileSizing: isMobileLayout,
                                        mobileHeroHeight: heroHeight,
                                        needsDeviceConnection:
                                            needsDeviceConnection,
                                        phase: widget.controller.phase,
                                        processingStage:
                                            widget.controller.processingStage,
                                        amplitude: widget.controller.amplitude,
                                        isPreparingMicrophone: widget
                                            .controller
                                            .isPreparingMicrophone,
                                        onStop: () => unawaited(
                                          widget.controller.stopRecording(
                                            manual: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!isMobileLayout)
                                    SizedBox(height: compact ? 8 : 18),
                                  if (widget.controller.sentenceProgress !=
                                      null)
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
                                      in widget.controller.sentenceResults
                                          .where(
                                            (item) => !identical(
                                              item,
                                              widget.controller.result,
                                            ),
                                          ))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
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
                                    sectionMinHeight: isMobileLayout
                                        ? 120
                                        : 110,
                                    // Fill the space down to the main action.
                                    minCardHeight: isMobileLayout
                                        ? (viewport.maxHeight - heroBand - 18)
                                              .clamp(220.0, 560.0)
                                        : 0,
                                    result: widget.controller.result,
                                    outputLanguage:
                                        widget.controller.outputLanguage,
                                    onPlay: () => unawaited(
                                      widget.controller.playResult(),
                                    ),
                                  ),
                                  if (widget.controller.errorMessage != null ||
                                      widget.controller.transientMessage !=
                                          null) ...<Widget>[
                                    const SizedBox(height: 12),
                                    _InlineMessage(
                                      isError:
                                          widget.controller.errorMessage !=
                                          null,
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
                      isConnectingDevice: _connectingDevice,
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
