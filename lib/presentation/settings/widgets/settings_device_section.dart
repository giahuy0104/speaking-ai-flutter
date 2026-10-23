import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/bluetooth_power_panel.dart';
import '../../../app/homi_ui.dart';
import '../../../app/homi_connection_presentation.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/device_display_name.dart';
import '../../../core/device/device_connection_coordinator.dart';
import '../../../l10n/display_language.dart';
import '../../../features/conversation/application/conversation_settings_port.dart';
import 'settings_raised_panel.dart';
import 'settings_device_tile.dart';
import 'settings_expandable_section.dart';
import 'settings_divider.dart';
import 'settings_device_heading.dart';
import 'settings_aiv0_ble_control_card.dart';
import 'settings_hfp_status_card.dart';
import 'settings_last_connected_device_tile.dart';
import 'settings_connection_summary.dart';
import 'settings_ios_device_details.dart';

class SettingsDeviceSection extends StatefulWidget {
  const SettingsDeviceSection({
    required this.controller,
    this.connectionCoordinator,
    super.key,
  });
  final ConversationSettingsPort controller;
  final DeviceConnectionCoordinator? connectionCoordinator;
  @override
  State<SettingsDeviceSection> createState() => _SettingsDeviceSectionState();
}

class _SettingsDeviceSectionState extends State<SettingsDeviceSection> {
  ConversationSettingsPort get controller => widget.controller;
  DisplayLanguage get _language => DisplayLanguageScope.of(context);
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      controller,
      ?widget.connectionCoordinator,
      ?widget.connectionCoordinator?.bluetoothPower,
    ]),
    builder: (context, _) {
      final homiState = controller.homiConnectionState();
      return SettingsRaisedPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (widget.connectionCoordinator?.bluetoothPower
                      case final power?)
                    Offstage(
                      offstage: _canUseBluetooth,
                      child: BluetoothPowerPanel(controller: power),
                    ),
                  if (widget.connectionCoordinator case final coordinator?)
                    SettingsConnectionSummary(
                      coordinator: coordinator,
                      connection: HomiConnectionPresentation.from(
                        homiState,
                        isReady: homiState.isHomiReady,
                      ),
                      microphoneNeedsConfirmation:
                          controller.aiv0BleStatus.isConnected &&
                          controller.usesHfpInput &&
                          !homiState.isHomiReady,
                      canConnect: _canUseBluetooth,
                      onConnect: () => unawaited(_connectHomi()),
                      onCancel: () => unawaited(_cancelManualOperation()),
                      onChooseMicrophone: () =>
                          unawaited(_findAndConnectHfp(context)),
                    )
                  else
                    SettingsDeviceHeading(
                      label: HomiConnectionPresentation.from(
                        homiState,
                        isReady: homiState.isHomiReady,
                      ).label(context),
                    ),
                ],
              ),
            ),
            const SettingsDivider(),
            SettingsExpandableSection(
              key: const Key('settings-audio-hm-d001-section'),
              icon: Icons.headset_mic_outlined,
              title: context.tr('Âm thanh & thiết bị', '音频与设备'),
              children: <Widget>[_deviceDetails(context)],
            ),
          ],
        ),
      );
    },
  );
  Widget _deviceDetails(BuildContext context) =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? SettingsIosDeviceDetails(controller: controller)
      : HomiSurface(
          key: const Key('settings-hm-d001-group'),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (widget.connectionCoordinator case final coordinator?)
                TextButton.icon(
                  key: const Key('settings-open-bluetooth-settings'),
                  onPressed: () =>
                      unawaited(coordinator.openBluetoothSettings()),
                  icon: const Icon(Icons.settings_bluetooth_rounded),
                  label: Text(context.tr('Mở cài đặt Bluetooth', '打开蓝牙设置')),
                ),
              SettingsDeviceTile(
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
              SettingsAiv0BleControlCard(
                status: controller.aiv0BleStatus,
                disabled:
                    !_canUseBluetooth ||
                    controller.isBusy ||
                    _manualOperationActive,
                onScan: () => _scanAndConnectAiv0(context),
                onDisconnect: () =>
                    _disconnectDevice(context, microphone: false),
              ),
              const SizedBox(height: 8),
              SettingsHfpStatusCard(
                status: controller.hfpAudioStatus,
                selected: controller.usesHfpInput,
                disabled:
                    !_canUseBluetooth ||
                    controller.isBusy ||
                    _manualOperationActive,
                onFind: () => _findAndConnectHfp(context),
                onDisconnect: () =>
                    _disconnectDevice(context, microphone: true),
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
                  SettingsLastConnectedDeviceTile(record: record),
                if (controller.lastConnectedMicrophone case final record?)
                  SettingsLastConnectedDeviceTile(record: record),
              ],
            ],
          ),
        );

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
        language: _language,
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
      selectLikelyHomiHfpDevice(<HfpAudioDevice>[
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
                                  _language,
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
                            _language,
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
                                  _language,
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
                  'Micro “${localizedDeviceName(selected.name, _language, deviceId: selected.id)}” có thuộc thiết bị HOMI đang kết nối không? Chỉ xác nhận khi bạn biết đây là cùng một thiết bị.',
                  '麦克风“${localizedDeviceName(selected.name, _language, deviceId: selected.id)}”是否属于当前连接的 HOMI？请仅在确定是同一台设备时确认。',
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
