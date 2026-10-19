import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/bluetooth_power_panel.dart';
import '../../../core/device/bluetooth_power_controller.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import '../../../app/device_connection_feedback_overlay.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';

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

class _StartupSetupScreenState extends State<StartupSetupScreen> {
  _ParentSetupStep _step = _ParentSetupStep.privacy;
  late bool _adultRoleConfirmed;
  late bool _legalReviewCompleted;
  bool _h20SetupRequested = false;
  bool _choiceInProgress = false;
  DeviceConnectionFeedbackStage? _deviceConnectionFeedbackStage;

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
    _adultRoleConfirmed = widget.privacyConsentGranted;
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
      _adultRoleConfirmed = true;
      _legalReviewCompleted = true;
    }
  }

  void _onBluetoothPowerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.bluetoothPower?.removeListener(_onBluetoothPowerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepNumber = _step.index + 1;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Scaffold(
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
                        stepNumber: stepNumber,
                        totalSteps: _ParentSetupStep.values.length,
                        canGoBack: _step.index > 0,
                        onBack: _goBack,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey<_ParentSetupStep>(_step),
                              child: switch (_step) {
                                _ParentSetupStep.privacy => _buildPrivacyStep(
                                  theme,
                                ),
                                _ParentSetupStep.profile => _buildProfileStep(
                                  theme,
                                ),
                                _ParentSetupStep.permissions =>
                                  _buildPermissionsStep(theme),
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_deviceConnectionFeedbackStage != null)
          DeviceConnectionFeedbackOverlay(
            stage: _deviceConnectionFeedbackStage!,
            connectedDetail:
                (widget.allowPhoneMicFallback || widget.allowBleOnlySetup) &&
                    widget.h20BleConnected &&
                    !widget.h20HfpConfigured
                ? 'Nút MAIN đã kết nối. HOMI sẽ tự tìm micro HM-D001 sau thiết lập.'
                : null,
          ),
      ],
    );
  }

  Widget _buildPrivacyStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final headingColor = isDark
        ? theme.colorScheme.onSurface
        : AppColors.indigoDark;
    final accentColor = isDark ? theme.colorScheme.secondary : AppColors.coral;
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-privacy-step'),
      title: 'Xác nhận của phụ huynh',
      subtitle: 'Cùng HOMI chuẩn bị một buổi học vui cho bé.',
      hero: const _MascotHero(),
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: theme.colorScheme.surface,
            elevation: 4,
            shadowColor: AppColors.primaryNavy.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(22),
            child: CheckboxListTile(
              key: const Key('startup-confirm-adult-role'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              controlAffinity: ListTileControlAffinity.leading,
              value: _adultRoleConfirmed,
              onChanged: widget.profileLoading
                  ? null
                  : (value) =>
                        setState(() => _adultRoleConfirmed = value ?? false),
              activeColor: accentColor,
              checkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Text(
                'Tôi là phụ huynh, người giám hộ hoặc giáo viên',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: headingColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            key: const Key('startup-review-legal'),
            onPressed: _showLegalReview,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              foregroundColor: isDark
                  ? theme.colorScheme.primary
                  : AppColors.indigoDark,
              backgroundColor: theme.colorScheme.surface,
              minimumSize: const Size.fromHeight(58),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: Icon(
              _legalReviewCompleted
                  ? Icons.check_circle_rounded
                  : Icons.description_outlined,
              color: _legalReviewCompleted ? AppColors.success : null,
            ),
            label: Text(
              _legalReviewCompleted
                  ? 'Đã đọc Điều khoản và Chính sách quyền riêng tư'
                  : 'Đọc Điều khoản và Chính sách quyền riêng tư',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
      footer: <Widget>[
        if (!widget.privacyConfigurationComplete)
          const _WarningBox(
            text:
                'Bản build chưa cấu hình đầy đủ URL pháp lý, nhà cung cấp hoặc thời hạn lưu. Chế độ giọng nói đang bị khóa.',
          ),
        if (!widget.privacyConfigurationComplete) const SizedBox(height: 12),
        if (widget.privacyConsentGranted)
          const _GrantedBanner(
            text: 'Phụ huynh đã đồng ý xử lý, gửi và lưu dữ liệu giọng nói.',
          )
        else if (widget.limitedModeSelected)
          const _GrantedBanner(text: 'Đã chọn chế độ không dùng giọng nói.'),
        if (_privacyChoiceMade) const SizedBox(height: 14),
        if (!widget.privacyConsentGranted && !widget.limitedModeSelected)
          FilledButton.icon(
            key: const Key('startup-grant-privacy-consent'),
            onPressed:
                !_adultRoleConfirmed ||
                    !_legalReviewCompleted ||
                    widget.profileLoading ||
                    !widget.privacyConfigurationComplete
                ? null
                : _grantConsentAndContinue,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Đồng ý và tiếp tục'),
          ),
        if (!_privacyChoiceMade) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('startup-continue-without-voice'),
            onPressed:
                !_adultRoleConfirmed ||
                    !_legalReviewCompleted ||
                    widget.profileLoading
                ? null
                : _chooseLimitedMode,
            icon: const Icon(Icons.mic_off_outlined),
            label: const Text('Tiếp tục không dùng giọng nói'),
          ),
        ] else
          _PrimaryNextButton(onPressed: _adultRoleConfirmed ? _goNext : null),
      ],
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-profile-step'),
      title: 'Bé đang ở độ tuổi nào?',
      subtitle: 'HOMI chọn chủ đề và cách hướng dẫn phù hợp.',
      panel: LayoutBuilder(
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
                    label: '${catalog.startAge}–${catalog.endAge} tuổi',
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
      footer: <Widget>[
        const _InfoBox(
          icon: Icons.tune_rounded,
          text: 'Bạn có thể đổi nhóm tuổi trong Cài đặt phụ huynh.',
        ),
        const SizedBox(height: 24),
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

    final permissionsGranted =
        widget.microphoneGranted &&
        (!widget.bluetoothRequired || widget.bluetoothGranted);
    if (permissionsGranted) return _buildDeviceConnectionStep(theme);

    return _SetupStepLayout(
      key: const ValueKey<String>('startup-permissions-step'),
      title: 'Cho HOMI quyền cần thiết',
      subtitle: 'Chỉ cần hai quyền để HOMI nghe bé nói và tìm thiết bị.',
      panelPadding: EdgeInsets.zero,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PermissionRow(
            icon: Icons.mic_rounded,
            label: 'Micro',
            description: 'Để nhận biết lời bé nói trong bài học',
            granted: widget.microphoneGranted,
            waiting:
                widget.profileLoading || widget.permissionRequestInProgress,
          ),
          if (widget.bluetoothRequired) ...<Widget>[
            const SizedBox(height: 12),
            _PermissionRow(
              icon: Icons.bluetooth_rounded,
              label: 'Bluetooth',
              description: 'Để tìm và kết nối HM-D001 ở gần',
              granted: widget.bluetoothGranted,
              waiting:
                  widget.profileLoading || widget.permissionRequestInProgress,
            ),
          ],
          if (widget.bluetoothRequired && !widget.bluetoothGranted)
            if (widget.bluetoothPower case final power?) ...<Widget>[
              const SizedBox(height: 12),
              BluetoothPowerPanel(controller: power),
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
        const _InfoBox(
          icon: Icons.check_rounded,
          text: 'HOMI sẽ hướng dẫn từng quyền khi bạn tiếp tục.',
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('startup-request-permissions'),
          onPressed: widget.permissionRequestInProgress
              ? null
              : widget.onRetryPermissions,
          icon: widget.permissionRequestInProgress
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.lock_open_rounded),
          label: Text(
            widget.permissionRequestInProgress
                ? 'Đang yêu cầu quyền…'
                : 'Cấp quyền và tiếp tục',
          ),
        ),
        _continueWithoutVoiceAction(),
      ],
    );
  }

  Widget _buildDeviceConnectionStep(ThemeData theme) {
    return _SetupStepLayout(
      key: const ValueKey<String>('startup-device-step'),
      title: context.tr('Kết nối thiết bị', '连接设备'),
      subtitle: context.tr(
        'Bật HOMI và đặt gần điện thoại để kết nối.',
        '请开启 HOMI 并放在手机附近进行连接。',
      ),
      panelPadding: EdgeInsets.zero,
      panel: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.bluetoothPower case final power?) ...<Widget>[
            BluetoothPowerPanel(controller: power),
            const SizedBox(height: 12),
          ],
          _DeviceChoiceCard(
            key: const Key('startup-h20-choice'),
            icon: Icons.bluetooth_audio_rounded,
            title: context.tr('Thiết bị HOMI', 'HOMI 设备'),
            description: context.tr('Nút MAIN và micro', 'MAIN 按钮与麦克风'),
            selected: _h20Ready,
            status: !_bluetoothAvailable
                ? context.tr('Chưa kết nối', '尚未连接')
                : _h20Ready
                ? context.tr(
                    'Nút MAIN và micro HOMI đã sẵn sàng',
                    'MAIN 按钮和 HOMI 麦克风已就绪',
                  )
                : widget.h20BleConnected
                ? context.tr(
                    'Nút MAIN đã kết nối · Mic chưa kết nối',
                    'MAIN 按钮已连接 · 麦克风尚未连接',
                  )
                : widget.h20HfpConfigured
                ? context.tr(
                    'Mic đã kết nối · Nút MAIN chưa kết nối',
                    '麦克风已连接 · MAIN 按钮尚未连接',
                  )
                : _h20SetupRequested
                ? context.tr(
                    'Chưa tìm thấy thiết bị. Hãy kiểm tra và thử lại.',
                    '未找到设备，请检查后重试。',
                  )
                : context.tr('Chưa kết nối', '尚未连接'),
            actionKey: const Key('startup-setup-h20'),
            actionLabel: _h20Ready
                ? context.tr('Đã kết nối', '已连接')
                : context.tr('Kết nối HOMI', '连接 HOMI'),
            showAction: _canUseBluetooth,
            busy: _choiceInProgress,
            onPressed: _choiceInProgress || _h20Ready || !_canUseBluetooth
                ? null
                : _setupH20,
          ),
          if (widget.allowPhoneMicFallback &&
              !widget.h20HfpConfigured &&
              widget.onChooseH20Microphone != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('startup-choose-h20-microphone'),
              onPressed: _choiceInProgress || !_canUseBluetooth
                  ? null
                  : _chooseH20Microphone,
              icon: const Icon(Icons.headset_mic_rounded),
              label: const Text('Chọn micro HOMI'),
            ),
          ],
          if (widget.microphoneGranted &&
              !_h20Ready &&
              (widget.h20BleConnected ||
                  widget.allowPhoneMicFallback)) ...<Widget>[
            const SizedBox(height: 14),
            _InfoBox(
              icon: Icons.phone_iphone_rounded,
              text: widget.allowBleOnlySetup
                  ? widget.h20BleConnected
                        ? 'Nút MAIN đã kết nối. HOMI sẽ tiếp tục tìm micro HM-D001. Trong lúc chờ, trẻ có thể dùng micro trên điện thoại.'
                        : 'Kết nối nút MAIN trước khi bắt đầu. HOMI sẽ tiếp tục tìm micro của thiết bị sau.'
                  : widget.allowPhoneMicFallback
                  ? 'Bạn có thể bắt đầu bằng micro iPhone. HOMI sẽ tiếp tục tìm thiết bị sau.'
                  : 'Cần kết nối nút MAIN và micro HOMI để bắt đầu bài học.',
            ),
          ],
        ],
      ),
      footer: <Widget>[
        if (_canComplete)
          FilledButton.icon(
            key: const Key('startup-confirm-age'),
            onPressed: _choiceInProgress ? null : widget.onCompleteSetup,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary
                  : AppColors.indigo,
              foregroundColor: theme.brightness == Brightness.dark
                  ? theme.colorScheme.onPrimary
                  : Colors.white,
              elevation: 4,
              shadowColor: AppColors.primaryNavy.withValues(alpha: 0.2),
            ),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Bắt đầu bài học'),
          )
        else
          Text(
            context.tr(
              'Kết nối HOMI để bắt đầu bài học có giọng nói.',
              '连接 HOMI 后即可开始语音课程。',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (!_h20Ready) _continueWithoutVoiceAction(),
      ],
    );
  }

  Widget _continueWithoutVoiceAction() => TextButton.icon(
    key: const Key('startup-continue-without-voice-after-consent'),
    onPressed: _choiceInProgress || widget.permissionRequestInProgress
        ? null
        : _continueWithoutVoiceHere,
    icon: const Icon(Icons.mic_off_outlined),
    label: Text(context.tr('Tiếp tục không dùng giọng nói', '不使用语音继续')),
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
    setState(() {
      _choiceInProgress = true;
      _h20SetupRequested = true;
      _deviceConnectionFeedbackStage = DeviceConnectionFeedbackStage.connecting;
    });
    var connected = false;
    var failedUnexpectedly = false;
    try {
      connected = await widget.onSetupH20();
    } catch (_) {
      failedUnexpectedly = true;
    } finally {
      if (mounted) {
        setState(() {
          _choiceInProgress = false;
          _deviceConnectionFeedbackStage = null;
        });
      }
    }
    if (!mounted) return;
    if (failedUnexpectedly) {
      final retry = await _showConnectionFailureSheet();
      if (retry && mounted) {
        await _setupH20();
      }
    } else if (connected) {
      // The callback may update its parent in this frame. Success is based on
      // refreshed live MAIN + microphone state, never on a BLE-only result.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_h20Ready) return;
      final startLesson = await _showConnectionSuccessSheet();
      if (startLesson == true && mounted && _h20Ready) {
        await widget.onCompleteSetup();
      }
    }
  }

  Future<bool?> _showConnectionSuccessSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            key: const Key('startup-connection-success-dialog'),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 122,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? theme.colorScheme.surfaceContainerHigh
                              : AppColors.mintSoft,
                        ),
                      ),
                      Image.asset(
                        MascotAssets.wave,
                        height: 116,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      Transform.translate(
                        offset: const Offset(54, 42),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Kết nối thành công',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Nút MAIN và micro HOMI đã sẵn sàng. Bé có thể bắt đầu bài học.',
                    'MAIN 按钮和 HOMI 麦克风已就绪，可以开始学习。',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const Key('startup-start-after-connection'),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: isDark
                        ? theme.colorScheme.primary
                        : AppColors.indigo,
                    foregroundColor: isDark
                        ? theme.colorScheme.onPrimary
                        : Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Bắt đầu bài học'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Để sau'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showConnectionFailureSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final retry = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            key: const Key('startup-connection-failure-sheet'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 92,
                  child: Image.asset(MascotAssets.wave, fit: BoxFit.contain),
                ),
                const SizedBox(height: 12),
                Text(
                  'HOMI chưa thấy thiết bị',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mình cùng kiểm tra HM-D001 rồi thử tìm lại nhé.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHigh
                        : AppColors.mintSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ConnectionCheckRow(
                        icon: Icons.power_settings_new_rounded,
                        label: 'Bật HM-D001 và đặt gần điện thoại',
                      ),
                      SizedBox(height: 12),
                      _ConnectionCheckRow(
                        icon: Icons.bluetooth_rounded,
                        label: 'Kiểm tra Bluetooth đang mở',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('startup-retry-connection'),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: isDark
                        ? theme.colorScheme.primary
                        : AppColors.indigo,
                    foregroundColor: isDark
                        ? theme.colorScheme.onPrimary
                        : Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử tìm lại'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Để sau'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return retry == true;
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
    }
  }

  void _goBack() {
    if (_step.index > 0) {
      setState(() => _step = _ParentSetupStep.values[_step.index - 1]);
    }
  }

  Future<void> _showLegalReview() async {
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
      setState(() => _legalReviewCompleted = true);
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
                      'Bằng việc tiếp tục, phụ huynh xác nhận đã hiểu nội dung trên. Việc đồng ý xử lý dữ liệu giọng nói vẫn được thực hiện bằng một lựa chọn riêng ở màn hình trước.',
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
                    if (!_reachedEnd)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Cuộn đến cuối nội dung để xác nhận đã đọc.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('startup-legal-reviewed'),
                      onPressed: _reachedEnd
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        _reachedEnd ? 'Tôi đã đọc hết' : 'Đọc hết để tiếp tục',
                      ),
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
                      'Thiết lập HOMI',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurface
                            : AppColors.indigoDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
  const _MascotHero();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 780;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: compact ? 150 : 184,
      child: Center(
        child: SizedBox(
          width: compact ? 172 : 194,
          height: compact ? 146 : 178,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: compact ? 140 : 164,
                height: compact ? 140 : 164,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.25, -0.4),
                    colors: isDark
                        ? const <Color>[Color(0xFF375E7C), Color(0xFF153E59)]
                        : const <Color>[Colors.white, Color(0xFFC7F5E9)],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primaryNavy.withValues(alpha: 0.15),
                      blurRadius: 24,
                      offset: const Offset(0, 13),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: 112,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primaryNavy.withValues(alpha: 0.10),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Image.asset(
                MascotAssets.wave,
                height: compact ? 142 : 173,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              Positioned(
                top: 7,
                right: 6,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: isDark
                      ? const Color(0xFFFFC7D9)
                      : AppColors.accentPink,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryNextButton extends StatelessWidget {
  const _PrimaryNextButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return FilledButton(
      key: const Key('startup-next'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        backgroundColor: isDark ? theme.colorScheme.primary : AppColors.indigo,
        foregroundColor: isDark ? theme.colorScheme.onPrimary : Colors.white,
        elevation: 4,
        shadowColor: AppColors.primaryNavy.withValues(alpha: 0.22),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('Tiếp tục'),
          SizedBox(width: 10),
          Icon(Icons.arrow_forward_rounded),
        ],
      ),
    );
  }
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

class _SetupStepLayout extends StatelessWidget {
  const _SetupStepLayout({
    required this.title,
    required this.subtitle,
    required this.panel,
    required this.footer,
    this.hero,
    this.panelPadding = EdgeInsets.zero,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget panel;
  final List<Widget> footer;
  final Widget? hero;
  final EdgeInsetsGeometry panelPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).height < 780;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hero != null) ...<Widget>[hero!, const SizedBox(height: 8)],
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.onSurface
                : AppColors.indigoDark,
            fontWeight: FontWeight.w800,
            fontSize: compact ? 27 : 30,
            letterSpacing: -0.7,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: compact ? 15 : 16,
            height: 1.35,
          ),
        ),
        SizedBox(height: compact ? 20 : 26),
        Container(padding: panelPadding, child: panel),
        SizedBox(height: compact ? 20 : 24),
        ...footer,
      ],
    );
  }
}

class _DeviceChoiceCard extends StatelessWidget {
  const _DeviceChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.status,
    required this.actionKey,
    required this.actionLabel,
    required this.busy,
    required this.onPressed,
    this.showAction = true,
    super.key,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final String status;
  final Key actionKey;
  final String actionLabel;
  final bool busy;
  final bool showAction;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const <Color>[Color(0xFF214A63), Color(0xFF123A58)]
                  : const <Color>[Color(0xFFE7FCF6), Color(0xFFCFF2E7)],
            ),
          ),
          child: _BluetoothOrb(connected: selected),
        ),
        const SizedBox(height: 14),
        Material(
          color: theme.colorScheme.surface,
          elevation: 4,
          shadowColor: AppColors.primaryNavy.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.successSoft
                        : (isDark
                              ? theme.colorScheme.surfaceContainerHigh
                              : AppColors.mintSoft),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : icon,
                    color: selected
                        ? AppColors.success
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? (isDark
                                    ? theme.colorScheme.tertiary
                                    : AppColors.success)
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showAction) const SizedBox(height: 20),
        if (showAction)
          OutlinedButton.icon(
            key: actionKey,
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: isDark
                  ? theme.colorScheme.primary
                  : AppColors.indigo,
              foregroundColor: isDark
                  ? theme.colorScheme.onPrimary
                  : Colors.white,
              disabledBackgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
              side: BorderSide.none,
              elevation: 4,
              shadowColor: AppColors.primaryNavy.withValues(alpha: 0.2),
            ),
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    selected ? Icons.check_rounded : Icons.bluetooth_rounded,
                  ),
            label: Text(actionLabel),
          ),
      ],
    );
  }
}

class _BluetoothOrb extends StatelessWidget {
  const _BluetoothOrb({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ring = isDark ? const Color(0xFF75D5C2) : const Color(0xFF86DCC9);
    return Center(
      child: SizedBox.square(
        dimension: 158,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            for (final diameter in <double>[154, 124, 96])
              Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ring.withValues(
                      alpha: diameter == 154 ? 0.44 : 0.64,
                    ),
                  ),
                ),
              ),
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const <Color>[Color(0xFF467D8B), Color(0xFF174F65)]
                      : const <Color>[Colors.white, Color(0xFFE8F9F5)],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                connected ? Icons.check_rounded : Icons.bluetooth_rounded,
                size: 34,
                color: connected
                    ? AppColors.success
                    : (isDark ? Colors.white : AppColors.indigo),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    final color = granted ? AppColors.success : theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      shadowColor: AppColors.primaryNavy.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: granted
                    ? (isDark
                          ? AppColors.success.withValues(alpha: 0.22)
                          : AppColors.successSoft)
                    : (isDark
                          ? theme.colorScheme.surfaceContainerHigh
                          : AppColors.accentPinkSoft),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (waiting)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Icon(
                granted
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: color,
              ),
          ],
        ),
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

class _GrantedBanner extends StatelessWidget {
  const _GrantedBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.success.withValues(alpha: 0.16)
            : AppColors.successSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCheckRow extends StatelessWidget {
  const _ConnectionCheckRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
