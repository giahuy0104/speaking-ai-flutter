import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/bluetooth_power_panel.dart';
import '../../../core/device/bluetooth_power_controller.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import '../../../app/homi_bluetooth_icon.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';
import 'ios_startup_setup_screen.dart';

enum _ParentSetupStep { privacy, profile, permissions }

/// Mandatory parent/teacher setup shown before a child learning session starts.
class StartupSetupScreen extends StatefulWidget {
  const StartupSetupScreen({
    required this.profileLoading,
    required this.permissionRequestInProgress,
    required this.privacyConfigurationComplete,
    required this.privacyConsentGranted,
    required this.limitedModeSelected,
    required this.microphoneGranted,
    required this.bluetoothRequired,
    required this.bluetoothGranted,
    required this.h20BleConnected,
    required this.h20HfpConfigured,
    required this.selectedAge,
    required this.aiSubprocessors,
    required this.dataRetentionSummary,
    required this.onGrantPrivacyConsent,
    required this.onContinueWithoutVoice,
    required this.onRetryPermissions,
    required this.onSetupH20,
    required this.onAgeSelected,
    required this.onCompleteSetup,
    this.bluetoothPower,
    this.onCheckPermissions,
    this.onCancelH20Setup,
    this.allowPhoneMicFallback = false,
    this.allowBleOnlySetup = false,
    this.androidOfflineEnglishModelOptionAvailable = false,
    this.androidOfflineEnglishModelDownloadAllowed = false,
    this.onAndroidOfflineEnglishModelDownloadChanged,
    this.onChooseH20Microphone,
    this.h20DeviceName,
    this.privacyPolicyUri,
    this.termsUri,
    this.supportUri,
    this.permissionError,
    super.key,
  });

  final BluetoothPowerController? bluetoothPower;
  final Future<void> Function()? onCancelH20Setup;
  final bool profileLoading;
  final bool permissionRequestInProgress;
  final bool privacyConfigurationComplete;
  final bool privacyConsentGranted;
  final bool limitedModeSelected;
  final bool microphoneGranted;
  final bool bluetoothRequired;
  final bool bluetoothGranted;
  final bool h20BleConnected;
  final bool h20HfpConfigured;
  final bool allowPhoneMicFallback;
  final bool allowBleOnlySetup;
  final int? selectedAge;
  final String aiSubprocessors;
  final String dataRetentionSummary;
  final String? h20DeviceName;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;
  final Future<void> Function() onGrantPrivacyConsent;
  final Future<void> Function() onContinueWithoutVoice;
  final VoidCallback onRetryPermissions;
  final Future<void> Function()? onCheckPermissions;
  final Future<bool> Function() onSetupH20;
  final Future<bool> Function()? onChooseH20Microphone;
  final ValueChanged<int> onAgeSelected;
  final Future<void> Function() onCompleteSetup;
  final bool androidOfflineEnglishModelOptionAvailable;
  final bool androidOfflineEnglishModelDownloadAllowed;
  final Future<void> Function(bool)?
  onAndroidOfflineEnglishModelDownloadChanged;
  final String? permissionError;

  @override
  State<StartupSetupScreen> createState() => _StartupSetupScreenState();
}

class _StartupSetupScreenState extends State<StartupSetupScreen>
    with WidgetsBindingObserver {
  _ParentSetupStep _step = _ParentSetupStep.privacy;
  bool _adultRoleConfirmed = false;
  late bool _legalReviewCompleted;
  bool _legalAccepted = false;
  bool _legalReviewOpen = false;
  bool _h20SetupRequested = false;
  bool _permissionCheckInProgress = false;
  bool _permissionsCheckedOnce = false;
  bool _choiceInProgress = false;
  bool _connectionInProgress = false;
  int _connectionGeneration = 0;

  bool get _privacyChoiceMade =>
      widget.privacyConsentGranted || widget.limitedModeSelected;

  bool get _canUseBluetooth => widget.bluetoothPower?.canConnect ?? true;

  bool get _bluetoothAvailable =>
      widget.bluetoothPower == null ||
      (widget.bluetoothPower!.hasChecked &&
          widget.bluetoothPower!.state == Aiv0BluetoothAdapterState.poweredOn);

  bool get _h20Ready =>
      _bluetoothAvailable && widget.h20BleConnected && widget.h20HfpConfigured;

  bool get _bleOnlySetupAccepted =>
      widget.allowBleOnlySetup && widget.h20BleConnected;

  bool get _canComplete =>
      widget.limitedModeSelected ||
      (widget.microphoneGranted &&
          (!widget.bluetoothRequired ||
              (widget.bluetoothGranted &&
                  (_h20Ready ||
                      widget.allowPhoneMicFallback ||
                      _bleOnlySetupAccepted))));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _legalReviewCompleted = widget.privacyConsentGranted;
    widget.bluetoothPower?.addListener(_onBluetoothPowerChanged);
  }

  @override
  void didUpdateWidget(StartupSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bluetoothPower != widget.bluetoothPower) {
      oldWidget.bluetoothPower?.removeListener(_onBluetoothPowerChanged);
      widget.bluetoothPower?.addListener(_onBluetoothPowerChanged);
    }
    if (!oldWidget.privacyConsentGranted && widget.privacyConsentGranted) {
      _legalReviewCompleted = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _step == _ParentSetupStep.permissions &&
        !_connectionInProgress) {
      unawaited(_checkPermissions());
    }
  }

  Future<void> _checkPermissions() async {
    final check = widget.onCheckPermissions;
    if (check == null ||
        _permissionCheckInProgress ||
        widget.permissionRequestInProgress ||
        widget.limitedModeSelected) {
      return;
    }
    setState(() => _permissionCheckInProgress = true);
    try {
      await check();
    } finally {
      if (mounted) {
        setState(() {
          _permissionCheckInProgress = false;
          _permissionsCheckedOnce = true;
        });
      }
    }
  }

  void _onBluetoothPowerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_connectionInProgress) {
      unawaited(widget.onCancelH20Setup?.call());
    }
    widget.bluetoothPower?.removeListener(_onBluetoothPowerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return IosStartupSetupScreen(
        profileLoading: widget.profileLoading,
        permissionRequestInProgress: widget.permissionRequestInProgress,
        privacyConfigurationComplete: widget.privacyConfigurationComplete,
        privacyConsentGranted: widget.privacyConsentGranted,
        limitedModeSelected: widget.limitedModeSelected,
        microphoneGranted: widget.microphoneGranted,
        bluetoothRequired: widget.bluetoothRequired,
        bluetoothGranted: widget.bluetoothGranted,
        h20BleConnected: widget.h20BleConnected,
        h20HfpConfigured: widget.h20HfpConfigured,
        selectedAge: widget.selectedAge,
        aiSubprocessors: widget.aiSubprocessors,
        dataRetentionSummary: widget.dataRetentionSummary,
        onGrantPrivacyConsent: widget.onGrantPrivacyConsent,
        onContinueWithoutVoice: widget.onContinueWithoutVoice,
        onRetryPermissions: widget.onRetryPermissions,
        onSetupH20: widget.onSetupH20,
        onAgeSelected: widget.onAgeSelected,
        onCompleteSetup: widget.onCompleteSetup,
        allowPhoneMicFallback: widget.allowPhoneMicFallback,
        allowBleOnlySetup: widget.allowBleOnlySetup,
        androidOfflineEnglishModelOptionAvailable:
            widget.androidOfflineEnglishModelOptionAvailable,
        androidOfflineEnglishModelDownloadAllowed:
            widget.androidOfflineEnglishModelDownloadAllowed,
        onAndroidOfflineEnglishModelDownloadChanged:
            widget.onAndroidOfflineEnglishModelDownloadChanged,
        onChooseH20Microphone: widget.onChooseH20Microphone,
        h20DeviceName: widget.h20DeviceName,
        privacyPolicyUri: widget.privacyPolicyUri,
        termsUri: widget.termsUri,
        supportUri: widget.supportUri,
        permissionError: widget.permissionError,
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        overlayOpacity: 0.025,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: <Widget>[
                  _SetupHeader(
                    stepNumber: _step.index + 1,
                    totalSteps: _ParentSetupStep.values.length,
                    canGoBack: _step.index > 0,
                    onBack: _goBack,
                  ),
                  Expanded(
                    child: switch (_step) {
                      _ParentSetupStep.privacy => _buildPrivacyStep(theme),
                      _ParentSetupStep.profile => _buildProfileStep(theme),
                      _ParentSetupStep.permissions => _buildPermissionsStep(
                        theme,
                      ),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyStep(ThemeData theme) {
    final consentLabelStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      foregroundColor: theme.colorScheme.onSurface,
    );
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-privacy-step'),
      title: context.tr('Cùng bé bắt đầu\nvới HOMI', '和孩子一起开始 HOMI'),
      subtitle: context.tr(
        'Thiết lập vài bước để bé học và luyện nói mỗi ngày.',
        '简单设置，让孩子每天学习和练习说话。',
      ),
      hero: const _MascotHero(height: 208),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.mic_rounded, color: AppColors.mint),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr(
                    'HOMI cần xử lý, gửi và lưu dữ liệu giọng nói để hỗ trợ bé học.',
                    'HOMI 需要处理、发送和保存语音数据来帮助孩子学习。',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ConsentRow(
            checkbox: Checkbox(
              key: const Key('startup-confirm-adult-role'),
              value: _adultRoleConfirmed,
              semanticLabel: context.tr(
                'Tôi là phụ huynh, người giám hộ hoặc giáo viên',
                '我是家长、监护人或老师',
              ),
              onChanged: widget.profileLoading
                  ? null
                  : (value) =>
                        setState(() => _adultRoleConfirmed = value ?? false),
            ),
            label: TextButton(
              style: consentLabelStyle,
              onPressed: widget.profileLoading
                  ? null
                  : () => setState(
                      () => _adultRoleConfirmed = !_adultRoleConfirmed,
                    ),
              child: Text(
                context.tr(
                  'Tôi là phụ huynh, người giám hộ hoặc giáo viên',
                  '我是家长、监护人或老师',
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          _ConsentRow(
            checkbox: Checkbox(
              key: const Key('startup-accept-legal'),
              value: _legalAccepted,
              semanticLabel: context.tr(
                'Đồng ý điều khoản và quyền riêng tư',
                '同意条款和隐私政策',
              ),
              onChanged: widget.profileLoading
                  ? null
                  : (_) => unawaited(_showLegalReview()),
            ),
            label: TextButton(
              key: const Key('startup-review-legal'),
              onPressed: widget.profileLoading ? null : _showLegalReview,
              style: consentLabelStyle,
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: <InlineSpan>[
                    TextSpan(text: context.tr('Tôi đồng ý với ', '我同意')),
                    TextSpan(
                      text: context.tr(
                        'Điều khoản và quyền riêng tư',
                        '条款和隐私政策',
                      ),
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            helper: Text(
              _legalAccepted && !_legalReviewCompleted
                  ? context.tr(
                      'Vui lòng đọc nội dung để tiếp tục.',
                      '请阅读内容后继续。',
                    )
                  : context.tr(
                      'Nhấn vào liên kết để xem chi tiết.',
                      '点击链接查看详情。',
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!widget.privacyConfigurationComplete) ...<Widget>[
            const SizedBox(height: 12),
            const _WarningBox(
              text:
                  'Bản build chưa cấu hình đầy đủ URL pháp lý, nhà cung cấp hoặc thời hạn lưu. Chế độ giọng nói đang bị khóa.',
            ),
          ],
        ],
      ),
      footer: <Widget>[
        if (!_privacyChoiceMade) ...<Widget>[
          FilledButton(
            key: const Key('startup-grant-privacy-consent'),
            onPressed:
                !_adultRoleConfirmed ||
                    !_legalAccepted ||
                    !_legalReviewCompleted ||
                    widget.profileLoading ||
                    !widget.privacyConfigurationComplete
                ? null
                : _grantConsentAndContinue,
            child: Text(context.tr('Đồng ý và tiếp tục', '同意并继续')),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('startup-continue-without-voice'),
            onPressed:
                !_adultRoleConfirmed ||
                    !_legalReviewCompleted ||
                    widget.profileLoading
                ? null
                : _chooseLimitedMode,
            child: Text(context.tr('Tiếp tục không dùng giọng nói', '不使用语音继续')),
          ),
        ] else
          _PrimaryNextButton(
            onPressed:
                _adultRoleConfirmed &&
                    (!widget.privacyConsentGranted || _legalAccepted)
                ? _goNext
                : null,
          ),
      ],
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-profile-step'),
      title: context.tr('Bé đang ở độ tuổi nào?', '孩子多大了？'),
      subtitle: context.tr(
        'HOMI chọn chủ đề và cách hướng dẫn phù hợp.',
        'HOMI 会选择适合孩子的主题和指导方式。',
      ),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final optionWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final catalog in listeningCatalogs)
                    SizedBox(
                      width: optionWidth,
                      child: _ProfileAgeOption(
                        key: ValueKey('startup-age-${catalog.id}'),
                        label: context.tr(
                          '${catalog.startAge}–${catalog.endAge} tuổi',
                          '${catalog.startAge}–${catalog.endAge} 岁',
                        ),
                        selected:
                            widget.selectedAge != null &&
                            widget.selectedAge! >= catalog.startAge &&
                            widget.selectedAge! <= catalog.endAge,
                        onPressed: () => widget.onAgeSelected(catalog.startAge),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _InfoBox(
            icon: Icons.tune_rounded,
            text: context.tr(
              'Bạn có thể đổi nhóm tuổi trong Cài đặt phụ huynh.',
              '您可以在家长设置中更改年龄组。',
            ),
          ),
        ],
      ),
      footer: <Widget>[
        _PrimaryNextButton(
          onPressed: widget.selectedAge == null ? null : _goNext,
        ),
      ],
    );
  }

  Widget _buildPermissionsStep(ThemeData theme) {
    if (widget.limitedModeSelected) {
      return _SetupStepLayout(
        key: const ValueKey<String>('startup-limited-step'),
        title: context.tr('Sẵn sàng bắt đầu', '准备开始'),
        subtitle: context.tr(
          'HOMI sẽ mở bài học ở chế độ không dùng giọng nói.',
          'HOMI 将以不使用语音的模式打开课程。',
        ),
        panel: _InfoBox(
          icon: Icons.mic_off_outlined,
          text: context.tr(
            'Trẻ vẫn xem và nghe được bài học. Phụ huynh có thể bật giọng nói sau trong Cài đặt.',
            '孩子仍可观看和收听课程。家长可以稍后在设置中启用语音。',
          ),
        ),
        footer: <Widget>[
          FilledButton.icon(
            key: const Key('startup-confirm-age'),
            onPressed: widget.onCompleteSetup,
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: Text(context.tr('Bắt đầu bài học', '开始课程')),
          ),
        ],
      );
    }

    if (_permissionCheckInProgress && !_permissionsCheckedOnce) {
      return _SetupStepLayout(
        title: context.tr('Đang kiểm tra quyền', '正在检查权限'),
        subtitle: context.tr('Vui lòng đợi trong giây lát.', '请稍候。'),
        panel: const Center(
          child: CircularProgressIndicator(
            key: Key('startup-checking-permissions'),
          ),
        ),
        footer: <Widget>[_continueWithoutVoiceAction()],
      );
    }

    if (_connectionInProgress ||
        widget.bluetoothPower?.state == Aiv0BluetoothAdapterState.unsupported) {
      return _buildDeviceConnectionStep(theme);
    }
    final permissionsGranted =
        widget.microphoneGranted &&
        (!widget.bluetoothRequired || widget.bluetoothGranted);
    if (permissionsGranted) return _buildDeviceConnectionStep(theme);
    final power = widget.bluetoothPower;
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-permissions-step'),
      title: context.tr('Cấp quyền cho HOMI', '授予 HOMI 权限'),
      subtitle: context.tr(
        'Để nghe bé nói và tìm thiết bị ở gần.',
        '以听取孩子的声音并查找附近设备。',
      ),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _MascotHero(),
          const SizedBox(height: 16),
          _PermissionRow(
            icon: Icons.mic_rounded,
            label: context.tr('Micro', '麦克风'),
            description: context.tr('Để nhận biết lời bé nói', '识别孩子的声音'),
            granted: widget.microphoneGranted,
            waiting:
                widget.profileLoading || widget.permissionRequestInProgress,
          ),
          if (widget.bluetoothRequired) ...<Widget>[
            const SizedBox(height: 12),
            _PermissionRow(
              icon: Icons.bluetooth_rounded,
              label: context.tr('Thiết bị ở gần', '附近设备'),
              description: context.tr('Để tìm và kết nối HOMI', '查找并连接 HOMI'),
              granted: widget.bluetoothGranted,
              waiting:
                  widget.profileLoading || widget.permissionRequestInProgress,
            ),
            // Keep adapter refresh and blocked-permission help, without offering
            // a second permission or power action alongside the primary footer.
            if (power != null)
              BluetoothPowerPanel(
                controller: power,
                compact: true,
                permissionsOnly: true,
              ),
          ],
          if (widget.permissionError != null) ...<Widget>[
            const SizedBox(height: 12),
            _InfoBox(
              icon: Icons.info_outline_rounded,
              text: widget.permissionError!,
            ),
          ],
        ],
      ),
      footer: <Widget>[
        FilledButton(
          key: const Key('startup-request-permissions'),
          onPressed: widget.profileLoading || widget.permissionRequestInProgress
              ? null
              : widget.onRetryPermissions,
          child: Text(
            widget.permissionRequestInProgress
                ? context.tr('Đang yêu cầu quyền…', '正在请求权限…')
                : widget.microphoneGranted || widget.bluetoothGranted
                ? context.tr('Cấp quyền còn thiếu', '授予剩余权限')
                : context.tr('Cấp quyền và tiếp tục', '授权并继续'),
          ),
        ),
        const SizedBox(height: 12),
        _continueWithoutVoiceAction(),
      ],
    );
  }

  Widget _buildDeviceConnectionStep(ThemeData theme) {
    final power = widget.bluetoothPower;
    final unavailable = !_bluetoothAvailable;
    final poweredOff = power?.state == Aiv0BluetoothAdapterState.poweredOff;
    final partial =
        _bluetoothAvailable &&
        (widget.h20BleConnected || widget.h20HfpConfigured) &&
        !_h20Ready;
    final failed = _h20SetupRequested && !partial && !_h20Ready;
    final title = _connectionInProgress
        ? context.tr('Đang tìm HOMI', '正在查找 HOMI')
        : unavailable
        ? poweredOff
              ? context.tr('Bật Bluetooth', '开启蓝牙')
              : context.tr('Kiểm tra Bluetooth', '检查蓝牙')
        : _h20Ready
        ? context.tr('HOMI đã sẵn sàng!', 'HOMI 已准备就绪！')
        : partial
        ? context.tr('Còn một bước kết nối', '还差一步连接')
        : failed
        ? context.tr('Chưa tìm thấy HOMI', '尚未找到 HOMI')
        : context.tr('Kết nối HOMI', '连接 HOMI');
    final subtitle = _connectionInProgress
        ? context.tr('Giữ thiết bị gần điện thoại.', '请将设备放在手机附近。')
        : unavailable
        ? context.tr('Để tìm và kết nối với HOMI.', '以查找并连接 HOMI。')
        : _h20Ready
        ? context.tr('Cùng bé bắt đầu bài học đầu tiên.', '和孩子一起开始第一课。')
        : partial
        ? widget.h20BleConnected
              ? context.tr('HOMI đang chờ kết nối micro.', 'HOMI 正在等待麦克风连接。')
              : context.tr(
                  'HOMI đang chờ kết nối nút MAIN.',
                  'HOMI 正在等待 MAIN 按钮连接。',
                )
        : failed
        ? context.tr(
            'Kiểm tra thiết bị đã bật và đặt gần điện thoại.',
            '请确认设备已开启并放在手机附近。',
          )
        : context.tr('Bật HOMI và đặt gần điện thoại.', '开启 HOMI 并放在手机附近。');
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-device-step'),
      title: title,
      subtitle: subtitle,
      titleAlternatives: [
        context.tr('Đang tìm HOMI', '正在查找 HOMI'),
        context.tr('Kiểm tra Bluetooth', '检查蓝牙'),
        context.tr('HOMI đã sẵn sàng!', 'HOMI 已准备就绪！'),
        context.tr('Còn một bước kết nối', '还差一步连接'),
        context.tr('Chưa tìm thấy HOMI', '尚未找到 HOMI'),
      ],
      subtitleAlternatives: [
        context.tr(
          'Kiểm tra thiết bị đã bật và đặt gần điện thoại.',
          '请确认设备已开启并放在手机附近。',
        ),
        context.tr('HOMI đang chờ kết nối nút MAIN.', 'HOMI 正在等待 MAIN 按钮连接。'),
        context.tr('Cùng bé bắt đầu bài học đầu tiên.', '和孩子一起开始第一课。'),
      ],
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KeyedSubtree(
            key: const Key('startup-device-hero'),
            child: _MascotHero(
              connection: !unavailable,
              ready: _h20Ready && !_connectionInProgress,
            ),
          ),
          const SizedBox(height: 18),
          IndexedStack(
            key: const Key('startup-device-status-panel'),
            alignment: Alignment.topCenter,
            index: _connectionInProgress ? 1 : (_h20Ready || partial ? 2 : 0),
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (power != null)
                    BluetoothPowerPanel(controller: power, compact: true),
                  if (!unavailable) ...<Widget>[
                    const SizedBox(height: 12),
                    _ConnectionStatusRow(
                      label: context.tr('Thiết bị HOMI', 'HOMI 设备'),
                      mainControl: true,
                      connected: false,
                    ),
                  ],
                ],
              ),
              _ConnectionProgress(active: _connectionInProgress),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ConnectionStatusRow(
                    key: const Key('startup-main-status'),
                    label: context.tr('Nút MAIN', 'MAIN 按钮'),
                    mainControl: true,
                    connected: widget.h20BleConnected,
                  ),
                  const SizedBox(height: 8),
                  _ConnectionStatusRow(
                    key: const Key('startup-microphone-status'),
                    label: context.tr('Micro HOMI', 'HOMI 麦克风'),
                    connected: widget.h20HfpConfigured,
                  ),
                ],
              ),
            ],
          ),
          if (!_connectionInProgress) ...<Widget>[
            if (_canComplete && !_h20Ready && _canUseBluetooth)
              TextButton(
                key: const Key('startup-setup-h20'),
                onPressed: _choiceInProgress ? null : _setupH20,
                child: Text(context.tr('Kết nối HOMI', '连接 HOMI')),
              ),
            if (widget.allowPhoneMicFallback &&
                !widget.h20HfpConfigured &&
                widget.onChooseH20Microphone != null) ...<Widget>[
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('startup-choose-h20-microphone'),
                onPressed: _choiceInProgress || !_canUseBluetooth
                    ? null
                    : _chooseH20Microphone,
                icon: const Icon(Icons.headset_mic_rounded),
                label: Text(context.tr('Chọn micro HOMI', '选择 HOMI 麦克风')),
              ),
            ],
            if (widget.allowPhoneMicFallback && !_h20Ready) ...<Widget>[
              const SizedBox(height: 12),
              const _InfoBox(
                icon: Icons.phone_iphone_rounded,
                text:
                    'Bạn có thể bắt đầu bằng micro iPhone. HOMI sẽ tiếp tục tìm thiết bị sau.',
              ),
            ],
          ],
        ],
      ),
      footer: <Widget>[
        _StableActionSlot(
          labels: [
            context.tr('Kết nối HOMI', '连接 HOMI'),
            context.tr('Kết nối lại', '重新连接'),
            context.tr('Đang kết nối…', '正在连接…'),
            context.tr('Bắt đầu bài học', '开始课程'),
          ],
          child: _connectionInProgress
              ? FilledButton(
                  key: const Key('startup-connection-waiting'),
                  onPressed: null,
                  child: Text(context.tr('Đang kết nối…', '正在连接…')),
                )
              : _canComplete && !_h20Ready
              ? FilledButton(
                  key: const Key('startup-confirm-age'),
                  onPressed: _choiceInProgress || _permissionCheckInProgress
                      ? null
                      : widget.onCompleteSetup,
                  child: Text(context.tr('Bắt đầu bài học', '开始课程')),
                )
              : !_canComplete && _bluetoothAvailable
              ? FilledButton(
                  key: const Key('startup-setup-h20'),
                  onPressed:
                      _choiceInProgress ||
                          !_canUseBluetooth ||
                          _permissionCheckInProgress
                      ? null
                      : _setupH20,
                  child: Text(
                    partial
                        ? context.tr('Kết nối lại', '重新连接')
                        : failed
                        ? context.tr('Thử lại', '重试')
                        : context.tr('Kết nối HOMI', '连接 HOMI'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        _StableActionSlot(
          labels: [
            context.tr('Tiếp tục không dùng giọng nói', '不使用语音继续'),
            context.tr('Bắt đầu bài học', '开始课程'),
            context.tr('Hủy tìm kiếm', '取消查找'),
          ],
          child: _connectionInProgress
              ? OutlinedButton(
                  key: const Key('startup-cancel-connection'),
                  onPressed: widget.onCancelH20Setup == null
                      ? null
                      : _cancelConnection,
                  child: Text(context.tr('Hủy tìm kiếm', '取消查找')),
                )
              : _h20Ready
              ? FilledButton(
                  key: const Key('startup-confirm-age'),
                  onPressed: _choiceInProgress || _permissionCheckInProgress
                      ? null
                      : widget.onCompleteSetup,
                  child: Text(context.tr('Bắt đầu bài học', '开始课程')),
                )
              : _continueWithoutVoiceAction(),
        ),
      ],
    );
  }

  Widget _continueWithoutVoiceAction() => OutlinedButton(
    key: const Key('startup-continue-without-voice-after-consent'),
    onPressed: _choiceInProgress || widget.permissionRequestInProgress
        ? null
        : _continueWithoutVoiceHere,
    child: Text(context.tr('Tiếp tục không dùng giọng nói', '不使用语音继续')),
  );

  Future<void> _continueWithoutVoiceHere() async {
    if (_choiceInProgress || widget.permissionRequestInProgress) return;
    setState(() => _choiceInProgress = true);
    try {
      // Keep the selected age and current parent step. The existing callback
      // switches to limited mode; it never selects the phone microphone.
      await widget.onContinueWithoutVoice();
    } finally {
      if (mounted) setState(() => _choiceInProgress = false);
    }
  }

  Future<void> _grantConsentAndContinue() async {
    await widget.onGrantPrivacyConsent();
    if (mounted && widget.privacyConfigurationComplete) {
      setState(() => _step = _ParentSetupStep.profile);
    }
  }

  Future<void> _chooseLimitedMode() async {
    await widget.onContinueWithoutVoice();
    if (mounted) {
      setState(() => _step = _ParentSetupStep.profile);
    }
  }

  Future<void> _setupH20() async {
    if (!_canUseBluetooth || _choiceInProgress) return;
    final generation = ++_connectionGeneration;
    setState(() {
      _choiceInProgress = true;
      _connectionInProgress = true;
      _h20SetupRequested = true;
    });
    try {
      await widget.onSetupH20().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      if (mounted && generation == _connectionGeneration) {
        await widget.onCancelH20Setup?.call();
      }
    } catch (_) {
      // The settled UI offers retry; never claim success from a callback alone.
    } finally {
      if (mounted && generation == _connectionGeneration) {
        setState(() {
          _choiceInProgress = false;
          _connectionInProgress = false;
        });
      }
    }
  }

  Future<void> _cancelConnection() async {
    if (!_connectionInProgress) return;
    ++_connectionGeneration;
    setState(() {
      _connectionInProgress = false;
      _h20SetupRequested = false;
    });
    try {
      await widget.onCancelH20Setup?.call();
    } catch (_) {
      // The cancelled UI generation must not be revived by a native error.
    } finally {
      if (mounted) setState(() => _choiceInProgress = false);
    }
  }

  Future<void> _chooseH20Microphone() async {
    final choose = widget.onChooseH20Microphone;
    if (choose == null) return;
    setState(() {
      _choiceInProgress = true;
      _h20SetupRequested = true;
    });
    try {
      await choose().timeout(
        const Duration(seconds: 20),
        onTimeout: () => false,
      );
    } finally {
      if (mounted) setState(() => _choiceInProgress = false);
    }
  }

  void _goNext() {
    if (_step.index < _ParentSetupStep.values.length - 1) {
      setState(() => _step = _ParentSetupStep.values[_step.index + 1]);
      if (_step == _ParentSetupStep.permissions) {
        unawaited(_checkPermissions());
      }
    }
  }

  void _goBack() {
    if (_connectionInProgress) unawaited(_cancelConnection());
    if (_step.index > 0) {
      setState(() => _step = _ParentSetupStep.values[_step.index - 1]);
    }
  }

  Future<void> _showLegalReview() async {
    if (_legalReviewOpen) return;
    _legalReviewOpen = true;
    try {
      final reviewed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        builder: (context) => _LegalReviewSheet(
          aiSubprocessors: widget.aiSubprocessors,
          dataRetentionSummary: widget.dataRetentionSummary,
          privacyPolicyUri: widget.privacyPolicyUri,
          termsUri: widget.termsUri,
          supportUri: widget.supportUri,
          onOpenPrivacyPolicy: () => _openLegalPage(
            widget.privacyPolicyUri,
            'Chính sách quyền riêng tư',
          ),
          onOpenTerms: () =>
              _openLegalPage(widget.termsUri, 'Điều khoản sử dụng'),
          onOpenSupport: () => _openLegalPage(widget.supportUri, 'Hỗ trợ'),
        ),
      );
      if (reviewed == true && mounted) {
        setState(() {
          _legalReviewCompleted = true;
          _legalAccepted = true;
        });
      }
    } finally {
      _legalReviewOpen = false;
    }
  }

  Future<void> _openLegalPage(Uri? uri, String label) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }
}

class _LegalReviewSheet extends StatefulWidget {
  const _LegalReviewSheet({
    required this.aiSubprocessors,
    required this.dataRetentionSummary,
    required this.privacyPolicyUri,
    required this.termsUri,
    required this.supportUri,
    required this.onOpenPrivacyPolicy,
    required this.onOpenTerms,
    required this.onOpenSupport,
  });

  final String aiSubprocessors;
  final String dataRetentionSummary;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenSupport;

  @override
  State<_LegalReviewSheet> createState() => _LegalReviewSheetState();
}

class _LegalReviewSheetState extends State<_LegalReviewSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateReachedEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateReachedEnd());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateReachedEnd)
      ..dispose();
    super.dispose();
  }

  void _updateReachedEnd() {
    if (!_scrollController.hasClients || _reachedEnd) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0 || position.extentAfter <= 20) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.9;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Điều khoản và quyền riêng tư',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('startup-close-legal'),
                  onPressed: () => Navigator.of(context).pop(false),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const Key('startup-legal-scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Cuộn đến cuối nội dung để xác nhận đã đọc.'),
                    const SizedBox(height: 12),
                    Text(
                      'Thông tin phụ huynh cần biết',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'HOMI chỉ bắt đầu thu, xử lý, gửi và lưu dữ liệu giọng nói sau khi phụ huynh chủ động đồng ý và cấp quyền micro.',
                    ),
                    const SizedBox(height: 20),
                    const _LegalSection(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Dữ liệu được xử lý',
                      text:
                          'Giọng nói/audio khi dùng tính năng nói; nội dung đã nhận dạng; nhóm tuổi đã chọn; lịch sử tương tác; mã cài đặt và chẩn đoán kỹ thuật cần thiết để vận hành bài học.',
                    ),
                    const SizedBox(height: 18),
                    const _LegalSection(
                      icon: Icons.school_outlined,
                      title: 'Mục đích sử dụng',
                      text:
                          'Nhận dạng lời nói, dịch nội dung, tạo phản hồi và giọng đọc, lưu bản ghi/lịch sử để phụ huynh xem lại, lưu tiến trình học, khắc phục lỗi và bảo vệ dịch vụ.',
                    ),
                    const SizedBox(height: 18),
                    _LegalSection(
                      icon: Icons.cloud_outlined,
                      title: 'Bên thứ ba nhận dữ liệu và mục đích',
                      text:
                          'Các nhà cung cấp được cấu hình cho bản này: ${widget.aiSubprocessors}. '
                          'Railway nhận dữ liệu cần thiết để vận hành backend HOMI và xử lý yêu cầu. '
                          'Cloudflare Workers AI nhận audio khi cần nhận dạng dự phòng và nhận transcript cần thiết để nhận dạng, dịch hoặc tạo giọng đọc. '
                          'Cloudinary nhận và lưu bản ghi giọng nói có kiểm soát để phụ huynh nghe lại trong Lịch sử gần đây. '
                          'Các nhà cung cấp này chỉ được xử lý dữ liệu cho các mục đích HOMI mô tả, phải áp dụng biện pháp bảo vệ dữ liệu tương đương và không được dùng dữ liệu cho quảng cáo hoặc huấn luyện mô hình nếu chưa có chấp thuận riêng.',
                    ),
                    const SizedBox(height: 18),
                    _LegalSection(
                      icon: Icons.schedule_rounded,
                      title: 'Lưu trữ, xóa và rút lại chấp thuận',
                      text:
                          '${widget.dataRetentionSummary} Phụ huynh có thể rút lại chấp thuận hoặc yêu cầu xóa dữ liệu trong phần Cài đặt/Hỗ trợ.',
                    ),
                    const SizedBox(height: 18),
                    const _LegalSection(
                      icon: Icons.mic_off_outlined,
                      title: 'Quyền lựa chọn',
                      text:
                          'Có thể tiếp tục ở chế độ không dùng giọng nói. Khi đó HOMI không yêu cầu quyền micro và các tính năng cần nói sẽ không hoạt động.',
                    ),
                    const SizedBox(height: 22),
                    Text('Tài liệu đầy đủ', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    _LegalDocumentLink(
                      key: const Key('startup-open-privacy-policy'),
                      label: 'Chính sách quyền riêng tư',
                      available: widget.privacyPolicyUri != null,
                      onPressed: widget.onOpenPrivacyPolicy,
                    ),
                    _LegalDocumentLink(
                      key: const Key('startup-open-terms'),
                      label: 'Điều khoản sử dụng',
                      available: widget.termsUri != null,
                      onPressed: widget.onOpenTerms,
                    ),
                    _LegalDocumentLink(
                      key: const Key('startup-open-support'),
                      label: 'Hỗ trợ và yêu cầu xóa dữ liệu',
                      available: widget.supportUri != null,
                      onPressed: widget.onOpenSupport,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Nhấn “Đã hiểu” để xác nhận nội dung trên và tích ô đồng ý Điều khoản và quyền riêng tư. Sau đó, chọn “Đồng ý và tiếp tục” ở màn hình trước để tiếp tục thiết lập giọng nói.',
                    ),
                    const SizedBox(
                      key: Key('startup-legal-end-marker'),
                      height: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton.icon(
                      key: const Key('startup-legal-reviewed'),
                      onPressed: _reachedEnd
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Đã hiểu'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 23, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalDocumentLink extends StatelessWidget {
  const _LegalDocumentLink({
    required this.label,
    required this.available,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool available;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Text(
        available ? label : '$label (chưa cấu hình)',
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({
    required this.stepNumber,
    required this.totalSteps,
    required this.canGoBack,
    required this.onBack,
  });

  final int stepNumber;
  final int totalSteps;
  final bool canGoBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compactHeader =
        MediaQuery.sizeOf(context).width < 400 &&
        MediaQuery.textScalerOf(context).scale(16) > 22;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 22, 14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 46,
                child: canGoBack
                    ? Material(
                        color: theme.colorScheme.surface,
                        elevation: 3,
                        shadowColor: AppColors.primaryNavy.withValues(
                          alpha: 0.15,
                        ),
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const Key('startup-back'),
                          onPressed: onBack,
                          tooltip: 'Quay lại',
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(2),
                        child: Image.asset(
                          MascotAssets.avatar,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      compactHeader
                          ? 'Bước $stepNumber/$totalSteps'
                          : 'Thiết lập HOMI',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurface
                            : AppColors.indigoDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!compactHeader)
                      Text(
                        'Bước $stepNumber/$totalSteps • Dành cho phụ huynh',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              for (var index = 1; index <= totalSteps; index += 1) ...<Widget>[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 5,
                    decoration: BoxDecoration(
                      gradient: index <= stepNumber
                          ? LinearGradient(
                              colors: isDark
                                  ? <Color>[
                                      theme.colorScheme.secondary,
                                      theme.colorScheme.tertiary,
                                    ]
                                  : const <Color>[
                                      AppColors.accentPink,
                                      Color(0xFFF45A91),
                                    ],
                            )
                          : null,
                      color: index <= stepNumber
                          ? null
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (index != totalSteps) const SizedBox(width: 7),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MascotHero extends StatelessWidget {
  const _MascotHero({
    this.connection = false,
    this.ready = false,
    this.height = 240,
  });
  final bool connection;
  final bool ready;
  final double height;

  @override
  Widget build(BuildContext context) {
    final visibleHeight = MediaQuery.sizeOf(context).height < 700
        ? 140.0
        : height;
    return SizedBox(
      height: visibleHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (connection) ...<Widget>[
            if (ready)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 58,
              )
            else
              const HomiBluetoothIcon(size: 64),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Image.asset(
              MascotAssets.wave,
              height: visibleHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ],
      ),
    );
  }
}

// Both consent controls share the same checkbox column and label inset.
// Helper copy sits below the label, so it cannot shift the checkbox's center.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.checkbox, required this.label, this.helper});

  final Widget checkbox;
  final Widget label;
  final Widget? helper;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          SizedBox(width: 48, child: checkbox),
          const SizedBox(width: 8),
          Expanded(child: label),
        ],
      ),
      if (helper != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 56),
          child: helper,
        ),
    ],
  );
}

class _PrimaryNextButton extends StatelessWidget {
  const _PrimaryNextButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    key: const Key('startup-next'),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(child: Text(context.tr('Tiếp tục', '继续'))),
        const SizedBox(width: 10),
        const Icon(Icons.arrow_forward_rounded),
      ],
    ),
  );
}

class _ProfileAgeOption extends StatelessWidget {
  const _ProfileAgeOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? theme.colorScheme.secondary : AppColors.accentPink;
    return Material(
      color: selected
          ? (isDark
                ? theme.colorScheme.surfaceContainerHigh
                : AppColors.accentPinkSoft)
          : theme.colorScheme.surface,
      elevation: selected ? 0 : 3,
      shadowColor: AppColors.primaryNavy.withValues(alpha: 0.13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected ? BorderSide(color: accent, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 70),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? accent : theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Measure using the actual width and text scale, rather than fixed pixel
// heights, so retry labels cannot resize their surrounding layout.
double _maximumTextHeight(
  BuildContext context,
  Iterable<String> labels,
  TextStyle? style,
  double width,
) {
  var height = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width.clamp(1, double.infinity));
    if (painter.height > height) height = painter.height;
    painter.dispose();
  }
  return height;
}

class _StableText extends StatelessWidget {
  const _StableText({
    required this.text,
    required this.alternatives,
    required this.style,
  });
  final String text;
  final List<String> alternatives;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (alternatives.isEmpty) return Text(text, style: style);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: _maximumTextHeight(
          context,
          [text, ...alternatives],
          style,
          constraints.maxWidth,
        ),
        child: Text(text, style: style),
      ),
    );
  }
}

class _StableActionSlot extends StatelessWidget {
  const _StableActionSlot({required this.labels, required this.child});
  final List<String> labels;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      );
      final contentHeight = _maximumTextHeight(
        context,
        labels,
        style,
        constraints.maxWidth - 32,
      );
      return SizedBox(
        height: (contentHeight + 28).clamp(52, double.infinity),
        child: child,
      );
    },
  );
}

class _SetupStepLayout extends StatelessWidget {
  const _SetupStepLayout({
    required this.title,
    required this.subtitle,
    required this.panel,
    required this.footer,
    this.hero,
    this.titleAlternatives = const [],
    this.subtitleAlternatives = const [],
    super.key,
  });
  final List<String> titleAlternatives;
  final List<String> subtitleAlternatives;
  final String title;
  final String subtitle;
  final Widget panel;
  final List<Widget> footer;
  final Widget? hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final navy = dark ? theme.colorScheme.primary : AppColors.primaryNavy;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            key: const Key('startup-content-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (hero != null) ...<Widget>[
                  hero!,
                  const SizedBox(height: 12),
                ],
                _StableText(
                  text: title,
                  alternatives: titleAlternatives,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 28,
                    height: 1.15,
                    letterSpacing: -.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _StableText(
                  text: subtitle,
                  alternatives: subtitleAlternatives,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                panel,
              ],
            ),
          ),
        ),
        // Keep actions out of the scroll view: the last button has the same
        // safe-area inset on every step, independent of content and state.
        Padding(
          key: const Key('startup-action-footer'),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: FilledButtonTheme(
            data: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                backgroundColor: navy,
                foregroundColor: dark
                    ? theme.colorScheme.onPrimary
                    : Colors.white,
                disabledBackgroundColor: navy.withValues(alpha: .45),
                disabledForegroundColor: Colors.white,
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                shape: shape,
                elevation: 0,
              ),
            ),
            child: OutlinedButtonTheme(
              data: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  foregroundColor: navy,
                  backgroundColor: theme.colorScheme.surface,
                  side: BorderSide(color: navy, width: 1.5),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: shape,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: footer,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusRow extends StatelessWidget {
  const _ConnectionStatusRow({
    required this.label,
    required this.connected,
    this.mainControl = false,
    super.key,
  });
  final String label;
  final bool connected;
  final bool mainControl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.tr(
      connected ? 'Đã kết nối' : 'Chưa kết nối',
      connected ? '已连接' : '尚未连接',
    );
    return Semantics(
      label: '$label, $status',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            if (mainControl)
              const HomiBluetoothIcon()
            else
              const SizedBox.square(
                dimension: 44,
                child: Icon(Icons.mic_rounded, color: AppColors.mint),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _StableText(
                    text: status,
                    alternatives: [
                      context.tr('Đã kết nối', '已连接'),
                      context.tr('Chưa kết nối', '尚未连接'),
                    ],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: connected
                          ? AppColors.success
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              connected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: connected
                  ? AppColors.success
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionProgress extends StatelessWidget {
  const _ConnectionProgress({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const Key('startup-connection-progress'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 26,
            child: active
                ? const CircularProgressIndicator(strokeWidth: 3)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(context.tr('Đang tìm thiết bị…', '正在查找设备…'))),
        ],
      ),
    ),
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.granted,
    required this.waiting,
  });
  final IconData icon;
  final String label;
  final String description;
  final bool granted;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = granted
        ? AppColors.success
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          if (icon == Icons.bluetooth_rounded)
            const HomiBluetoothIcon()
          else
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHigh
                    : AppColors.mintSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.mint),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr(
                    granted ? 'Đã cấp quyền' : 'Chưa cấp quyền',
                    granted ? '已授权' : '尚未授权',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (waiting)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              granted ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: color,
              size: 22,
            ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.tertiaryContainer
            : AppColors.mintSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            color: isDark
                ? theme.colorScheme.onTertiaryContainer
                : AppColors.softNavy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark
                    ? theme.colorScheme.onTertiaryContainer
                    : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }
}
