import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/bluetooth_power_panel.dart';
import '../../../app/homi_ui.dart';
import '../../../app/homi_connection_presentation.dart';
import '../../../config/app_config.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/device_display_name.dart';
import '../../../core/device/device_connection_coordinator.dart';
import '../../../core/device/device_connection_history.dart';
import '../../../core/privacy/parental_gate.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/application/conversation_settings_port.dart';
import '../../listening/domain/listening_catalog.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    required this.controller,
    this.themeMode = ThemeMode.system,
    this.connectionCoordinator,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.stopMediaWhenBackgrounded,
    this.onStopMediaWhenBackgroundedChanged,
    super.key,
  });

  final ConversationSettingsPort controller;
  final DeviceConnectionCoordinator? connectionCoordinator;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final bool? stopMediaWhenBackgrounded;
  final ValueChanged<bool>? onStopMediaWhenBackgroundedChanged;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  ConversationSettingsPort get controller => widget.controller;
  bool _manualOperationActive = false;
  int _manualGeneration = 0;
  Route<Object?>? _devicePickerRoute;
  String? _manualFailure;
  int? _coordinatorToken;
  bool _ownsCoordinatorConnection = false;

  bool get _canUseBluetooth =>
      widget.connectionCoordinator?.bluetoothPower?.canConnect ?? true;

  @override
  void dispose() {
    _manualGeneration++;
    if (_manualOperationActive || _ownsCoordinatorConnection) {
      unawaited(_cancelConnectionWork());
    }
    final picker = _devicePickerRoute;
    if (picker?.isActive == true) {
      scheduleMicrotask(() {
        if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        controller,
        ?widget.connectionCoordinator,
        ?widget.connectionCoordinator?.bluetoothPower,
      ]),
      builder: (context, _) {
        final h20State = controller.h20ConnectionState();
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Builder(
            builder: (context) => SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? const <Color>[
                            AppColors.darkCanvas,
                            AppColors.darkSurface,
                          ]
                        : const <Color>[AppColors.mintWash, AppColors.mintSoft],
                  ),
                ),
                child: SingleChildScrollView(
                  key: const Key('settings-scroll-view'),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.tr('Thiết lập phụ huynh', '家长设置'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: context.tr('Đóng', '关闭'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SettingsRaisedPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  if (widget
                                          .connectionCoordinator
                                          ?.bluetoothPower
                                      case final power?)
                                    Offstage(
                                      offstage: _canUseBluetooth,
                                      child: BluetoothPowerPanel(
                                        controller: power,
                                      ),
                                    ),
                                  if (widget.connectionCoordinator
                                      case final coordinator?)
                                    _ConnectionSummary(
                                      coordinator: coordinator,
                                      connection:
                                          HomiConnectionPresentation.from(
                                            h20State,
                                            isReady: h20State.isH20Ready,
                                          ),
                                      microphoneNeedsConfirmation:
                                          controller
                                              .aiv0BleStatus
                                              .isConnected &&
                                          controller.usesHfpInput &&
                                          !h20State.isH20Ready,
                                      canConnect: _canUseBluetooth,
                                      onConnect: () =>
                                          unawaited(_connectHomi()),
                                      onCancel: () =>
                                          unawaited(_cancelManualOperation()),
                                      onChooseMicrophone: () => unawaited(
                                        _findAndConnectHfp(context),
                                      ),
                                    )
                                  else
                                    _DeviceHeading(
                                      label: HomiConnectionPresentation.from(
                                        h20State,
                                        isReady: h20State.isH20Ready,
                                      ).label(context),
                                    ),
                                ],
                              ),
                            ),
                            const _SettingsDivider(),
                            _CompactSettingsSection(
                              key: const Key('settings-audio-h20-section'),
                              icon: Icons.headset_mic_outlined,
                              title: context.tr('Âm thanh & thiết bị', '音频与设备'),
                              children: <Widget>[_deviceDetails(context)],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      _SectionLabel(
                        label: context.tr('Trải nghiệm học', '学习体验'),
                      ),
                      const SizedBox(height: 12),
                      _SettingsRaisedPanel(
                        child: Column(
                          children: <Widget>[
                            _SettingsPreferenceRow(
                              key: const Key('settings-child-age-group'),
                              icon: Icons.child_care_rounded,
                              title: context.tr('Nhóm tuổi', '年龄组'),
                              value: _ageLabel(context),
                              onTap:
                                  !controller.isBusy &&
                                      widget.onChildAgeChanged != null
                                  ? () => _chooseAge(context)
                                  : null,
                            ),
                            const _SettingsDivider(),
                            _SettingsPreferenceRow(
                              key: const Key('settings-language-row'),
                              icon: Icons.language_rounded,
                              title: context.tr('Ngôn ngữ', '语言'),
                              value: controller.displayLanguage.nativeLabel,
                              onTap: () => _chooseLanguage(context),
                            ),
                            const _SettingsDivider(),
                            _SettingsPreferenceRow(
                              key: const Key('appearance-settings-card'),
                              icon: Icons.light_mode_outlined,
                              title: context.tr('Giao diện', '外观'),
                              value: _themeLabel(context, widget.themeMode),
                              onTap: widget.onThemeModeChanged == null
                                  ? null
                                  : () => _chooseTheme(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      _SectionLabel(
                        label: context.tr('Thông tin & hỗ trợ', '信息与支持'),
                      ),
                      const SizedBox(height: 10),
                      _SettingsRaisedPanel(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Column(
                            children: <Widget>[
                              _SettingsActionTile(
                                key: const Key('settings-privacy-policy'),
                                icon: Icons.privacy_tip_outlined,
                                title: context.tr(
                                  'Chính sách quyền riêng tư',
                                  '隐私政策',
                                ),
                                detail: context.tr(
                                  'Xem dữ liệu được thu thập, nhà cung cấp AI, thời hạn lưu và cách yêu cầu xóa.',
                                  '查看所收集的数据、AI 服务商、保存期限和删除方式。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  widget.config?.privacyPolicyUri,
                                  context.tr(
                                    'Chính sách quyền riêng tư',
                                    '隐私政策',
                                  ),
                                ),
                              ),
                              const _SettingsDivider(),
                              _SettingsActionTile(
                                key: const Key('settings-terms'),
                                icon: Icons.description_outlined,
                                title: context.tr('Điều khoản sử dụng', '使用条款'),
                                detail: context.tr(
                                  'Điều khoản dành cho phụ huynh và người giám hộ.',
                                  '面向家长和监护人的使用条款。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  widget.config?.termsUri,
                                  context.tr('Điều khoản sử dụng', '使用条款'),
                                ),
                              ),
                              const _SettingsDivider(),
                              _SettingsActionTile(
                                key: const Key('settings-support'),
                                icon: Icons.support_agent_rounded,
                                title: context.tr('Hỗ trợ', '支持'),
                                detail: context.tr(
                                  'Liên hệ HOMI về quyền riêng tư, dữ liệu hoặc lỗi ứng dụng.',
                                  '就隐私、数据或应用问题联系 HOMI。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  widget.config?.supportUri,
                                  context.tr('Hỗ trợ', '支持'),
                                ),
                              ),
                              if (widget.privacyConsentGranted &&
                                  !widget.voiceAccessEnabled &&
                                  widget.onRequestVoiceAccess !=
                                      null) ...<Widget>[
                                const _SettingsDivider(),
                                _SettingsActionTile(
                                  key: const Key('settings-enable-voice'),
                                  showDetail: true,
                                  icon: Icons.mic_rounded,
                                  title: context.tr('Cho phép micro', '允许麦克风'),
                                  detail: context.tr(
                                    'Mở hộp thoại quyền hệ thống. Audio chỉ được gửi sau khi có cả chấp thuận phụ huynh và quyền micro.',
                                    '打开系统权限对话框。只有家长同意并授予麦克风权限后才会发送音频。',
                                  ),
                                  onTap: widget.onRequestVoiceAccess!,
                                ),
                              ],
                              if (!widget.privacyConsentGranted &&
                                  widget.onManagePrivacyConsent !=
                                      null) ...<Widget>[
                                const _SettingsDivider(),
                                _SettingsActionTile(
                                  key: const Key(
                                    'settings-manage-privacy-consent',
                                  ),
                                  showDetail: true,
                                  icon: Icons.verified_user_outlined,
                                  title: context.tr(
                                    'Thiết lập tính năng giọng nói',
                                    '设置语音功能',
                                  ),
                                  detail: context.tr(
                                    'Quay lại màn hình dành cho phụ huynh để đọc thông tin và chọn đồng ý.',
                                    '返回家长设置页面，阅读说明并选择是否同意。',
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onManagePrivacyConsent!();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _choiceSheetOpen = false;

  String _ageLabel(BuildContext context) {
    final catalog = listeningCatalogs.firstWhere(
      (entry) =>
          controller.childAge >= entry.startAge &&
          controller.childAge <= entry.endAge,
      orElse: () => listeningCatalogs.first,
    );
    return context.tr(
      '${catalog.startAge}–${catalog.endAge} tuổi',
      '${catalog.startAge}–${catalog.endAge} 岁',
    );
  }

  String _themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
    ThemeMode.system => context.tr('Hệ thống', '跟随系统'),
    ThemeMode.light => context.tr('Sáng', '浅色'),
    ThemeMode.dark => context.tr('Tối', '深色'),
  };

  Future<T?> _choose<T>(
    BuildContext context, {
    required String title,
    required T selected,
    required List<({T value, String label, String key})> options,
    bool useChips = false,
  }) async {
    if (_choiceSheetOpen) return null;
    _choiceSheetOpen = true;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(sheetContext).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Đóng', '关闭'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: useChips
                        ? SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              children: <Widget>[
                                for (final option in options)
                                  ChoiceChip(
                                    key: ValueKey<String>(option.key),
                                    showCheckmark: true,
                                    elevation: 0,
                                    side: BorderSide(
                                      color: Theme.of(
                                        sheetContext,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    label: Text(option.label),
                                    selected: option.value == selected,
                                    onSelected: (_) => Navigator.of(
                                      sheetContext,
                                    ).pop(option.value),
                                  ),
                              ],
                            ),
                          )
                        : Column(
                            children: <Widget>[
                              for (final option in options)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(12),
                                    color: option.value == selected
                                        ? AppColors.primaryNavy
                                        : Colors.transparent,
                                    child: ListTile(
                                      key: ValueKey<String>(option.key),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      selected: option.value == selected,
                                      selectedColor: Colors.white,
                                      title: Text(option.label),
                                      trailing: option.value == selected
                                          ? const Icon(Icons.check_rounded)
                                          : null,
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(option.value),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _choiceSheetOpen = false;
    }
  }

  Future<void> _chooseAge(BuildContext context) async {
    final catalog = listeningCatalogs.firstWhere(
      (entry) =>
          controller.childAge >= entry.startAge &&
          controller.childAge <= entry.endAge,
      orElse: () => listeningCatalogs.first,
    );
    final value = await _choose<int>(
      context,
      title: context.tr('Nhóm tuổi của trẻ', '孩子年龄组'),
      useChips: true,
      selected: catalog.startAge,
      options: [
        for (final entry in listeningCatalogs)
          (
            value: entry.startAge,
            label: context.tr(
              '${entry.startAge}–${entry.endAge} tuổi',
              '${entry.startAge}–${entry.endAge} 岁',
            ),
            key: 'settings-age-${entry.id}',
          ),
      ],
    );
    if (mounted && value != null && !controller.isBusy) {
      widget.onChildAgeChanged?.call(value);
    }
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final value = await _choose<DisplayLanguage>(
      context,
      title: context.tr('Ngôn ngữ hiển thị', '显示语言'),
      selected: controller.displayLanguage,
      options: [
        for (final language in DisplayLanguage.values)
          (
            value: language,
            label: language.nativeLabel,
            key: 'settings-language-${language.code}',
          ),
      ],
    );
    if (mounted && value != null) controller.setDisplayLanguage(value);
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final value = await _choose<ThemeMode>(
      context,
      title: context.tr('Giao diện', '外观'),
      selected: widget.themeMode,
      options: [
        for (final mode in ThemeMode.values)
          (
            value: mode,
            label: _themeLabel(context, mode),
            key: 'theme-mode-${mode.name}',
          ),
      ],
    );
    if (mounted && value != null) widget.onThemeModeChanged?.call(value);
  }

  Widget _deviceDetails(BuildContext context) => HomiSurface(
    key: const Key('settings-h20-group'),
    padding: const EdgeInsets.all(12),
    color: Theme.of(context).colorScheme.surface,
    borderColor: Theme.of(context).colorScheme.outlineVariant,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Text(
            context.tr('Thông tin thiết bị HOMI', 'HOMI 设备信息'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (widget.connectionCoordinator case final coordinator?)
          TextButton.icon(
            key: const Key('settings-open-bluetooth-settings'),
            onPressed: () => unawaited(coordinator.openBluetoothSettings()),
            icon: const Icon(Icons.settings_bluetooth_rounded),
            label: Text(context.tr('Mở cài đặt Bluetooth', '打开蓝牙设置')),
          ),
        _SettingsDeviceTile(
          icon: Icons.battery_full_rounded,
          title: context.tr('Pin thiết bị', '设备电量'),
          trailing: Text(
            controller.aiv0BleStatus.isConnected &&
                    controller.aiv0BleStatus.batteryPercent != null
                ? '${controller.aiv0BleStatus.batteryPercent}%'
                : context.tr('Chưa đọc pin', '尚未读取电量'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        _Aiv0BleControlCard(
          status: controller.aiv0BleStatus,
          disabled:
              !_canUseBluetooth || controller.isBusy || _manualOperationActive,
          onScan: () => _scanAndConnectAiv0(context),
          onDisconnect: () => _disconnectDevice(context, microphone: false),
        ),
        const SizedBox(height: 8),
        _HfpStatusCard(
          status: controller.hfpAudioStatus,
          selected: controller.usesHfpInput,
          disabled:
              !_canUseBluetooth || controller.isBusy || _manualOperationActive,
          onFind: () => _findAndConnectHfp(context),
          onDisconnect: () => _disconnectDevice(context, microphone: true),
        ),
        if (_manualOperationActive &&
            widget.connectionCoordinator == null) ...<Widget>[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('settings-device-manual-cancel'),
            onPressed: () => unawaited(_cancelManualOperation()),
            icon: const Icon(Icons.close_rounded),
            label: Text(context.tr('Hủy', '取消')),
          ),
        ],
        if (_manualFailure != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _manualFailure!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (controller.lastConnectedBleDevice != null ||
            controller.lastConnectedMicrophone != null) ...<Widget>[
          const Divider(height: 24),
          Text(
            context.tr('Đã kết nối gần nhất', '最近连接'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (controller.lastConnectedBleDevice case final record?)
            _LastConnectedDeviceTile(record: record),
          if (controller.lastConnectedMicrophone case final record?)
            _LastConnectedDeviceTile(record: record),
        ],
      ],
    ),
  );

  Future<void> _openParentLink(
    BuildContext context,
    Uri? uri,
    String label,
  ) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !context.mounted) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }

  bool _isCurrent(int generation) =>
      mounted &&
      generation == _manualGeneration &&
      (_coordinatorToken == null ||
          widget.connectionCoordinator?.isCurrent(_coordinatorToken!) == true);

  Future<void> _runManualOperation(
    BuildContext context,
    Future<void> Function(int generation) action,
  ) async {
    if (_manualOperationActive) return;
    final generation = ++_manualGeneration;
    setState(() {
      _manualOperationActive = true;
      _manualFailure = null;
    });
    int? token;
    try {
      if (widget.connectionCoordinator case final coordinator?) {
        token = await coordinator.beginManualOperation();
        if (!mounted || generation != _manualGeneration) {
          if (token != null) coordinator.endManualOperation(token);
          return;
        }
        if (token == null) return;
        _coordinatorToken = token;
      }
      await action(generation);
    } catch (error) {
      if (_isCurrent(generation) && context.mounted) {
        _showConnectionResult(
          context,
          DeviceConnectionResult(
            error is DeviceConnectionBusyException
                ? DeviceConnectionOutcome.busy
                : DeviceConnectionOutcome.failed,
          ),
        );
      }
    } finally {
      if (token != null) {
        widget.connectionCoordinator?.endManualOperation(token);
      }
      if (mounted && generation == _manualGeneration) {
        _coordinatorToken = null;
        setState(() => _manualOperationActive = false);
      }
    }
  }

  void _setManualPhase(DeviceConnectionPhase phase) {
    if (_coordinatorToken case final token?) {
      widget.connectionCoordinator?.setManualPhase(token, phase);
    }
  }

  Future<void> _connectHomi() async {
    if (!_canUseBluetooth ||
        _manualOperationActive ||
        _ownsCoordinatorConnection) {
      return;
    }
    _ownsCoordinatorConnection = true;
    try {
      await widget.connectionCoordinator?.connect();
    } finally {
      _ownsCoordinatorConnection = false;
    }
  }

  Future<void> _cancelManualOperation() async {
    _manualGeneration++;
    final picker = _devicePickerRoute;
    _devicePickerRoute = null;
    if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
    _coordinatorToken = null;
    _ownsCoordinatorConnection = false;
    if (mounted) setState(() => _manualOperationActive = false);
    await _cancelConnectionWork();
  }

  Future<void> _cancelConnectionWork() async {
    try {
      await (widget.connectionCoordinator?.cancel() ??
          controller.cancelManualDeviceConnection());
    } catch (error) {
      debugPrint('Settings connection cancellation failed: $error');
    }
  }

  Future<T?> _showDevicePicker<T extends Object>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = ModalBottomSheetRoute<T>(
      builder: (context) => DisplayLanguageScope(
        language: controller.displayLanguage,
        child: SingleChildScrollView(child: Builder(builder: builder)),
      ),
      isScrollControlled: true,
      showDragHandle: true,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
    );
    _devicePickerRoute = route;
    try {
      return await Navigator.of(context).push<T>(route);
    } finally {
      if (identical(_devicePickerRoute, route)) _devicePickerRoute = null;
    }
  }

  Future<T?> _showOwnedDialog<T extends Object>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(context: context, builder: builder);
    _devicePickerRoute = route;
    try {
      return await navigator.push<T>(route);
    } finally {
      if (identical(_devicePickerRoute, route)) _devicePickerRoute = null;
    }
  }

  bool _isLikelyBle(Aiv0BleDevice device) =>
      device.advertisesControlService || device.isLikelyAiv0;

  List<Aiv0BleDevice> _prioritizeBleDevices(List<Aiv0BleDevice> devices) =>
      List<Aiv0BleDevice>.of(devices)..sort((a, b) {
        if (_isLikelyBle(a) != _isLikelyBle(b)) return _isLikelyBle(a) ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

  bool _isLikelyMicrophone(HfpAudioDevice device) =>
      selectLikelyH20HfpDevice(<HfpAudioDevice>[
        device,
      ], bleDeviceName: controller.aiv0BleStatus.deviceName) !=
      null;

  List<HfpAudioDevice> _prioritizeMicrophones(List<HfpAudioDevice> devices) =>
      List<HfpAudioDevice>.of(devices)..sort((a, b) {
        if (_isLikelyMicrophone(a) != _isLikelyMicrophone(b)) {
          return _isLikelyMicrophone(a) ? -1 : 1;
        }
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return a.name.compareTo(b.name);
      });

  void _showConnectionResult(
    BuildContext context,
    DeviceConnectionResult result,
  ) {
    if (result.outcome == DeviceConnectionOutcome.cancelled) return;
    final message = switch (result.outcome) {
      DeviceConnectionOutcome.busy => context.tr(
        'Ứng dụng đang bận. Hãy thử lại sau.',
        '应用正忙，请稍后重试。',
      ),
      DeviceConnectionOutcome.unavailable => context.tr(
        'Thiết bị chưa khả dụng. Hãy kiểm tra kết nối Bluetooth rồi thử lại.',
        '设备暂不可用。请检查蓝牙连接后重试。',
      ),
      _ => context.tr(
        'Chưa kết nối được thiết bị. Hãy thử lại.',
        '暂时无法连接设备，请重试。',
      ),
    };
    setState(() => _manualFailure = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _disconnectDevice(
    BuildContext context, {
    required bool microphone,
  }) => _runManualOperation(context, (generation) async {
    final result = microphone
        ? await controller.disconnectHfpDevice()
        : await controller.disconnectAiv0Device();
    if (_isCurrent(generation) && context.mounted && !result.succeeded) {
      _showConnectionResult(context, result);
    }
  });

  Future<void> _scanAndConnectAiv0(BuildContext context) async {
    if (!_canUseBluetooth) return;
    await _runManualOperation(context, (generation) async {
      try {
        _setManualPhase(DeviceConnectionPhase.searching);
        final foundDevices = await controller.scanAiv0Devices();
        final devices = _prioritizeBleDevices(foundDevices);
        if (!_isCurrent(generation) || !context.mounted) return;
        if (devices.isEmpty) {
          setState(
            () => _manualFailure = context.tr(
              'Không tìm thấy thiết bị. Hãy bật thiết bị và thử lại.',
              '未找到设备。请开启设备后重试。',
            ),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Không tìm thấy thiết bị. Hãy bật thiết bị và thử lại.',
                  '未找到设备。请开启设备后重试。',
                ),
              ),
            ),
          );
          return;
        }
        final selected = await _showDevicePicker<Aiv0BleDevice>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('Chọn thiết bị điều khiển', '选择控制设备'),
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      'Thiết bị HOMI phù hợp được hiển thị trước. Kết nối này dùng cho nút điều khiển.',
                      '优先显示符合条件的 HOMI 设备。此连接用于控制按钮。',
                    ),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (index == 0 ||
                                _isLikelyBle(devices[index - 1]) !=
                                    _isLikelyBle(device))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  _isLikelyBle(device)
                                      ? context.tr(
                                          'Thiết bị HOMI phù hợp',
                                          '符合条件的 HOMI 设备',
                                        )
                                      : context.tr('Thiết bị khác', '其他设备'),
                                ),
                              ),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.bluetooth_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                localizedDeviceName(
                                  device.name,
                                  controller.displayLanguage,
                                  deviceId: device.id,
                                ),
                              ),
                              subtitle: Text(
                                '${device.id} • ${device.rssi} dBm',
                              ),
                              onTap: () => Navigator.of(context).pop(device),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (selected == null || !_isCurrent(generation) || !context.mounted) {
          return;
        }
        _setManualPhase(DeviceConnectionPhase.connecting);
        final result = await controller.connectAiv0Device(selected);
        if (_isCurrent(generation) && context.mounted && !result.succeeded) {
          _showConnectionResult(context, result);
        }
        if (_isCurrent(generation) && context.mounted && result.succeeded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr('Đã kết nối thiết bị điều khiển.', '控制设备已连接。'),
              ),
            ),
          );
        }
      } catch (error) {
        if (_isCurrent(generation) && context.mounted) {
          _showConnectionResult(
            context,
            DeviceConnectionResult(
              error is DeviceConnectionBusyException
                  ? DeviceConnectionOutcome.busy
                  : DeviceConnectionOutcome.failed,
            ),
          );
        }
      }
    });
  }

  // Kept only for release builds that intentionally re-enable legacy
  // FF12/FF13/FF14 audio through ENABLE_LEGACY_BLE_AUDIO.
  // ignore: unused_element
  Future<void> _scanAndConnect(BuildContext context) async {
    try {
      final devices = await controller.scanInnotrikDevices();
      if (!context.mounted) {
        return;
      }
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không tìm thấy thiết bị. Hãy bật INNOTRIK và thử lại.',
                '未找到设备。请打开 INNOTRIK 后重试。',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<BluetoothAudioDevice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Chọn thiết bị INNOTRIK', '选择 INNOTRIK 设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Thiết bị đúng giao thức được ưu tiên ở đầu danh sách.',
                    '符合协议的设备会优先显示在列表顶部。',
                  ),
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: device.isLikelyInnotrik
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : Theme.of(context).colorScheme.surfaceContainer,
                          child: Icon(
                            device.isLikelyInnotrik
                                ? Icons.bluetooth_connected_rounded
                                : Icons.bluetooth_rounded,
                            color: device.isLikelyInnotrik
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          localizedDeviceName(
                            device.name,
                            controller.displayLanguage,
                            deviceId: device.id,
                          ),
                        ),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
                        trailing: device.isLikelyInnotrik
                            ? const Icon(
                                Icons.verified_rounded,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !context.mounted) {
        return;
      }
      await controller.connectInnotrikDevice(selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Đã kết nối. Hãy nói thử để kiểm tra Mic INNOTRIK.',
                '已连接。请说话测试 INNOTRIK 麦克风。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // ignore: unused_element
  Future<void> _testInnotrik(BuildContext context) async {
    try {
      await controller.testInnotrikMicrophone();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Kiểm tra hoàn tất. Nếu nghe đúng giọng vừa nói, decoder hoạt động tốt.',
                '测试完成。如果能听到刚才的声音，说明解码器工作正常。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _findAndConnectHfp(BuildContext context) async {
    if (!_canUseBluetooth) return;
    await _runManualOperation(context, (generation) async {
      final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      try {
        _setManualPhase(DeviceConnectionPhase.preparingMicrophone);
        final foundDevices = await controller.findHfpDevices();
        final devices = _prioritizeMicrophones(foundDevices);
        if (!_isCurrent(generation) || !context.mounted) {
          return;
        }
        if (devices.isEmpty) {
          setState(
            () => _manualFailure = context.tr(
              'Micro chưa khả dụng. Hãy kiểm tra Cài đặt Bluetooth.',
              '麦克风暂不可用。请检查蓝牙设置。',
            ),
          );
          await _showHfpMessage(
            context,
            title: controller.supportsBrowserHfp
                ? context.tr('Chưa thấy mic Bluetooth trên Web', '网页中未发现蓝牙麦克风')
                : context.tr('Chưa có thiết bị HFP', '暂无 HFP 设备'),
            message: context.tr(
              controller.supportsBrowserHfp
                  ? 'Web không thể tự kết nối HFP. Hãy kết nối tai nghe trong Cài đặt Bluetooth, cho phép quyền micro, tải lại trang rồi bấm Chọn mic HFP. Safari trên iPhone có thể chỉ cung cấp mic iPhone.'
                  : isIOS
                  ? 'iOS chỉ cho ứng dụng chọn mic HFP đang kết nối. Hãy kết nối HM-D001 trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.'
                  : 'Hãy ghép đôi tai nghe hoặc thiết bị HFP trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.',
              controller.supportsBrowserHfp
                  ? '网页无法自行连接 HFP。请先在蓝牙设置中连接耳机、允许麦克风权限、刷新页面，再点击选择 HFP 麦克风。iPhone Safari 可能只提供 iPhone 麦克风。'
                  : isIOS
                  ? 'iOS 只能选择当前已连接的 HFP 麦克风。请先在蓝牙设置中连接 HM-D001，然后返回并点击“查找 HFP”。'
                  : '请先在蓝牙设置中配对耳机或 HFP 设备，然后返回并点击“查找 HFP”。',
            ),
          );
          return;
        }
        final selected = await _showDevicePicker<HfpAudioDevice>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    controller.supportsBrowserHfp
                        ? context.tr('Chọn mic Bluetooth', '选择蓝牙麦克风')
                        : context.tr('Chọn thiết bị HFP', '选择 HFP 设备'),
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr(
                      controller.supportsBrowserHfp
                          ? 'Chỉ các mic Bluetooth mà trình duyệt công bố mới xuất hiện. Thiết bị đã chọn được ưu tiên.'
                          : isIOS
                          ? 'iOS chỉ hiển thị các mic HFP đang khả dụng trong AVAudioSession. Thiết bị đang dùng được ưu tiên.'
                          : 'Android chỉ cho ứng dụng dùng HFP đã ghép đôi. Thiết bị đang kết nối được ưu tiên.',
                      controller.supportsBrowserHfp
                          ? '这里只显示浏览器公开的蓝牙麦克风；已选择的设备优先。'
                          : isIOS
                          ? 'iOS 仅显示 AVAudioSession 中可用的 HFP 麦克风；当前设备优先。'
                          : 'Android 仅允许应用使用已配对的 HFP；已连接设备优先显示。',
                    ),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (index == 0 ||
                                _isLikelyMicrophone(devices[index - 1]) !=
                                    _isLikelyMicrophone(device))
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  _isLikelyMicrophone(device)
                                      ? context.tr(
                                          'Micro HOMI phù hợp',
                                          '符合条件的 HOMI 麦克风',
                                        )
                                      : context.tr('Micro khác', '其他麦克风'),
                                ),
                              ),
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: device.isConnected
                                    ? Color.alphaBlend(
                                        AppColors.success.withValues(
                                          alpha: 0.14,
                                        ),
                                        Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                      )
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainer,
                                child: Icon(
                                  Icons.headset_mic_rounded,
                                  color: device.isConnected
                                      ? AppColors.success
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              title: Text(
                                localizedDeviceName(
                                  device.name,
                                  controller.displayLanguage,
                                  deviceId: device.id,
                                ),
                              ),
                              subtitle: Text(
                                device.isConnected
                                    ? controller.supportsBrowserHfp
                                          ? context.tr(
                                              'Mic đang được chọn cho Web',
                                              '已选为网页麦克风',
                                            )
                                          : context.tr(
                                              'HFP đang kết nối',
                                              'HFP 已连接',
                                            )
                                    : context.tr(
                                        controller.supportsBrowserHfp
                                            ? 'Chạm để dùng mic này'
                                            : 'Đã ghép đôi • chạm để mở kết nối',
                                        controller.supportsBrowserHfp
                                            ? '点击使用此麦克风'
                                            : '已配对 • 点击连接',
                                      ),
                              ),
                              trailing: device.isConnected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.success,
                                    )
                                  : const Icon(Icons.chevron_right_rounded),
                              onTap: () => Navigator.of(context).pop(device),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (selected == null || !_isCurrent(generation) || !context.mounted) {
          return;
        }
        var confirmHomiAssociation = false;
        if (controller.requiresHomiMicrophoneConfirmation(selected)) {
          final associationBleId = controller.aiv0BleStatus.deviceId
              ?.trim()
              .toUpperCase();
          final confirmed = await _showOwnedDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(context.tr('Xác nhận micro HOMI', '确认 HOMI 麦克风')),
              content: Text(
                context.tr(
                  'Micro “${localizedDeviceName(selected.name, controller.displayLanguage, deviceId: selected.id)}” có thuộc thiết bị HOMI đang kết nối không? Chỉ xác nhận khi bạn biết đây là cùng một thiết bị.',
                  '麦克风“${localizedDeviceName(selected.name, controller.displayLanguage, deviceId: selected.id)}”是否属于当前连接的 HOMI？请仅在确定是同一台设备时确认。',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.tr('Chỉ dùng micro', '仅使用麦克风')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(context.tr('Đúng thiết bị HOMI', '是这台 HOMI')),
                ),
              ],
            ),
          );
          if (!_isCurrent(generation) ||
              !context.mounted ||
              confirmed == null) {
            return;
          }
          if (confirmed &&
              (associationBleId == null ||
                  associationBleId.isEmpty ||
                  !controller.aiv0BleStatus.isConnected ||
                  controller.aiv0BleStatus.deviceId?.trim().toUpperCase() !=
                      associationBleId)) {
            _showConnectionResult(
              context,
              const DeviceConnectionResult(DeviceConnectionOutcome.unavailable),
            );
            return;
          }
          confirmHomiAssociation = confirmed;
        }
        final result = await controller.connectHfpDevice(
          selected,
          confirmHomiAssociation: confirmHomiAssociation,
        );
        if (_isCurrent(generation) && context.mounted && !result.succeeded) {
          _showConnectionResult(context, result);
        }
      } catch (error) {
        if (_isCurrent(generation) && context.mounted) {
          await _showHfpMessage(
            context,
            title: context.tr('Chưa thể dùng HFP', '暂时无法使用 HFP'),
            message: context.tr(
              'Chưa kết nối được micro. Hãy kiểm tra Bluetooth và thử lại.',
              '暂时无法连接麦克风。请检查蓝牙后重试。',
            ),
          );
        }
      }
    });
  }

  Future<void> _showHfpMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await _showOwnedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Đã hiểu', '知道了')),
          ),
        ],
      ),
    );
  }
}

class _SettingsRaisedPanel extends StatelessWidget {
  const _SettingsRaisedPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurfaceRaised
        : Colors.white,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _SettingsRaisedIcon extends StatelessWidget {
  const _SettingsRaisedIcon({required this.icon, this.foregroundColor});

  final IconData icon;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const size = 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[
                  AppColors.darkSurfaceStrong,
                  AppColors.darkSurface,
                ]
              : const <Color>[Colors.white, AppColors.mintSoft],
        ),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primaryNavy.withValues(
              alpha: isDark ? 0.18 : 0.10,
            ),
            blurRadius: 9,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: 22,
        color: foregroundColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _SettingsDeviceTile extends StatelessWidget {
  const _SettingsDeviceTile({
    required this.icon,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
      ),
      child: Row(
        children: <Widget>[
          _SettingsRaisedIcon(icon: icon, foregroundColor: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          trailing,
        ],
      ),
    );
  }
}

class _CompactSettingsSection extends StatelessWidget {
  const _CompactSettingsSection({
    required this.icon,
    required this.title,
    required this.children,
    super.key,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      leading: Icon(
        icon,
        size: 26,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      maintainState: true,
      children: children,
    ),
  );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.showDetail = false,
    super.key,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool showDetail;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, size: 25, color: Theme.of(context).colorScheme.primary),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    subtitle: showDetail ? Text(detail) : null,
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _SettingsPreferenceRow extends StatelessWidget {
  const _SettingsPreferenceRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final large =
        MediaQuery.textScalerOf(context).scale(1) >= 1.4 ||
        MediaQuery.sizeOf(context).width < 360;
    return ListTile(
      enabled: onTap != null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, size: 26, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: large ? Text(value) : null,
      trailing: large
          ? const Icon(Icons.chevron_right_rounded)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
      onTap: onTap,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 19,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _DeviceHeading extends StatelessWidget {
  const _DeviceHeading({
    required this.label,
    this.busy = false,
    this.ready = false,
  });
  final String label;
  final bool busy;
  final bool ready;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          shape: BoxShape.circle,
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                ready ? Icons.check_rounded : Icons.bluetooth_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('Thiết bị HOMI', 'HOMI 设备'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Aiv0BleControlCard extends StatelessWidget {
  const _Aiv0BleControlCard({
    required this.status,
    required this.disabled,
    required this.onScan,
    required this.onDisconnect,
  });

  final Aiv0BleStatus status;
  final bool disabled;
  final VoidCallback onScan;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = status.isConnected;
    final busy =
        status.phase == Aiv0BlePhase.scanning ||
        status.phase == Aiv0BlePhase.connecting ||
        status.phase == Aiv0BlePhase.reconnecting;
    return _SettingsDeviceTile(
      icon: connected
          ? Icons.bluetooth_connected_rounded
          : Icons.bluetooth_rounded,
      foregroundColor: connected ? AppColors.success : null,
      title: context.tr('Thiết bị điều khiển (BLE)', '控制设备 (BLE)'),
      subtitle: busy
          ? context.tr('Đang kết nối…', '正在连接…')
          : connected
          ? '${context.tr('Đã kết nối', '已连接')} · ${localizedDeviceName(status.deviceName, context.displayLanguage, deviceId: status.deviceId)}'
          : context.tr('Chưa kết nối', '尚未连接'),
      trailing: busy
          ? const SizedBox(
              width: 48,
              child: HomiWaveform(active: true, width: 42, height: 22),
            )
          : IconButton(
              tooltip: connected
                  ? context.tr('Ngắt kết nối BLE', '断开 BLE 连接')
                  : context.tr('Quét và kết nối', '扫描并连接'),
              onPressed: disabled || status.phase == Aiv0BlePhase.disabled
                  ? null
                  : connected
                  ? () => onDisconnect()
                  : onScan,
              icon: Icon(
                connected ? Icons.link_off_rounded : Icons.search_rounded,
              ),
            ),
    );
  }
}

class _HfpStatusCard extends StatelessWidget {
  const _HfpStatusCard({
    required this.status,
    required this.selected,
    required this.disabled,
    required this.onFind,
    required this.onDisconnect,
  });

  final BluetoothAudioStatus status;
  final bool selected;
  final bool disabled;
  final VoidCallback onFind;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    return _SettingsDeviceTile(
      icon: Icons.mic_rounded,
      foregroundColor: selected ? AppColors.success : null,
      title: status.deviceId == null
          ? context.tr('Micro', '麦克风')
          : localizedDeviceName(
              status.deviceName,
              context.displayLanguage,
              deviceId: status.deviceId,
            ),
      trailing: status.isBusy
          ? const SizedBox(
              width: 48,
              child: HomiWaveform(active: true, width: 42, height: 22),
            )
          : TextButton(
              onPressed:
                  disabled ||
                      status.phase ==
                          BluetoothAudioConnectionPhase.unsupported ||
                      status.phase == BluetoothAudioConnectionPhase.disabled
                  ? null
                  : selected
                  ? () => onDisconnect()
                  : onFind,
              child: Text(
                selected
                    ? context.tr('Bỏ chọn', '取消选择')
                    : context.tr('Chọn mic', '选择麦克风'),
              ),
            ),
    );
  }
}

class _LastConnectedDeviceTile extends StatelessWidget {
  const _LastConnectedDeviceTile({required this.record});
  final ConnectionDeviceRecord record;

  @override
  Widget build(BuildContext context) {
    final isBle = record.transport == ConnectionDeviceTransport.ble;
    final date = record.connectedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final dateLabel =
        context.displayLanguage == DisplayLanguage.simplifiedChinese
        ? '${date.year}/${two(date.month)}/${two(date.day)}'
        : '${two(date.day)}/${two(date.month)}/${date.year}';
    final timeLabel = '${two(date.hour)}:${two(date.minute)}';
    return ListTile(
      key: Key(isBle ? 'settings-last-ble-device' : 'settings-last-microphone'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(isBle ? Icons.bluetooth_rounded : Icons.mic_rounded),
      title: Text(
        '${isBle ? context.tr('Thiết bị điều khiển', '控制设备') : context.tr('Micro', '麦克风')}: ${localizedDeviceName(record.name, context.displayLanguage, deviceId: record.id)}',
      ),
      subtitle: Text(
        '${record.id} · $dateLabel $timeLabel',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ConnectionSummary extends StatelessWidget {
  const _ConnectionSummary({
    required this.coordinator,
    required this.connection,
    required this.microphoneNeedsConfirmation,
    required this.canConnect,
    required this.onConnect,
    required this.onCancel,
    required this.onChooseMicrophone,
  });
  final DeviceConnectionCoordinator coordinator;
  final HomiConnectionPresentation connection;
  final bool microphoneNeedsConfirmation;
  final bool canConnect;
  final VoidCallback onConnect;
  final VoidCallback onCancel;
  final VoidCallback onChooseMicrophone;

  @override
  Widget build(BuildContext context) {
    final phase = coordinator.phase;
    final busy =
        coordinator.isBusy ||
        coordinator.hasManualOperation ||
        phase == DeviceConnectionPhase.searching ||
        phase == DeviceConnectionPhase.connecting ||
        phase == DeviceConnectionPhase.preparingMicrophone;
    // The adapter panel owns guidance while Bluetooth is unavailable. Cached
    // transport state must not show a green ready badge when the radio is off.
    if (!canConnect && !busy) return const SizedBox.shrink();
    final ready = phase == DeviceConnectionPhase.ready;
    final phaseLabel = switch (phase) {
      DeviceConnectionPhase.disconnected => context.tr('Chưa kết nối', '尚未连接'),
      DeviceConnectionPhase.searching => context.tr(
        'Đang tìm thiết bị…',
        '正在查找设备…',
      ),
      DeviceConnectionPhase.connecting => context.tr(
        'Đang kết nối thiết bị…',
        '正在连接设备…',
      ),
      DeviceConnectionPhase.preparingMicrophone => context.tr(
        'Đã kết nối thiết bị, đang chuẩn bị micro…',
        '设备已连接，正在准备麦克风…',
      ),
      DeviceConnectionPhase.ready => context.tr('HOMI đã sẵn sàng', 'HOMI 已就绪'),
      DeviceConnectionPhase.failed => context.tr(
        'Chưa kết nối đủ thiết bị và micro. Hãy thử lại.',
        '设备和麦克风尚未全部连接，请重试。',
      ),
    };
    final label = connection == HomiConnectionPresentation.mainUnavailable
        ? busy
              ? context.tr('Đang khôi phục nút MAIN…', '正在恢复 MAIN 按钮…')
              : connection.label(context)
        : connection.isPartial && !busy
        ? connection.label(context)
        : phaseLabel;
    return Column(
      key: const Key('settings-homi-connection-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DeviceHeading(label: label, busy: busy, ready: ready),
        if (connection.isPartial && !microphoneNeedsConfirmation)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(connection.detail(context)!),
          ),
        if (microphoneNeedsConfirmation && !busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.tr(
                'Micro hiện tại chưa được xác nhận là micro của HOMI. Chọn micro HOMI để hoàn tất kết nối.',
                '当前麦克风尚未确认属于 HOMI。请选择 HOMI 麦克风以完成连接。',
              ),
            ),
          ),
        if (microphoneNeedsConfirmation && !busy && canConnect)
          TextButton(
            key: const Key('settings-confirm-homi-microphone'),
            onPressed: onChooseMicrophone,
            child: Text(context.tr('Chọn micro HOMI', '选择 HOMI 麦克风')),
          ),
        const SizedBox(height: 16),
        if (busy)
          TextButton.icon(
            key: const Key('settings-homi-cancel'),
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(context.tr('Hủy', '取消')),
          )
        else if (!ready && canConnect)
          FilledButton(
            key: const Key('settings-homi-connect'),
            onPressed: onConnect,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              phase == DeviceConnectionPhase.failed
                  ? context.tr('Thử lại', '重试')
                  : context.tr('Kết nối HOMI', '连接 HOMI'),
            ),
          ),
      ],
    );
  }
}
