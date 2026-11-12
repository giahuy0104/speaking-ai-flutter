import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/device/aiv0_ble_control.dart';
import '../../core/device/device_connection_coordinator.dart';
import '../../core/device/device_display_name.dart';
import '../../features/conversation/application/conversation_settings_port.dart';
import '../../l10n/display_language.dart';

/// Scans for nearby HOMI BLE devices and lets the user pick one, showing the
/// same bottom sheet regardless of which screen triggers it (Settings'
/// manual "Kết nối HOMI" card, or Home's speak action when the automatic
/// connect attempt did not find the device). Keeping this in one place avoids
/// Settings and Home drifting into two different pickers for the same
/// action.
class DeviceBlePickerFlow {
  DeviceBlePickerFlow({
    required ConversationSettingsPort controller,
    this.connectionCoordinator,
  }) : _controller = controller;

  final ConversationSettingsPort _controller;
  final DeviceConnectionCoordinator? connectionCoordinator;

  /// True while a scan/pick/connect round owns the manual-operation lock.
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  int _generation = 0;
  int? _coordinatorToken;
  Route<Object?>? _devicePickerRoute;
  bool _disposed = false;

  bool _isCurrent(int generation) =>
      !_disposed &&
      generation == _generation &&
      (_coordinatorToken == null ||
          connectionCoordinator?.isCurrent(_coordinatorToken!) == true);

  /// Runs the full scan -> pick -> connect round. Returns the connection
  /// result, or `null` if nothing was picked, the round was
  /// superseded/cancelled, or the lock was already held by another caller.
  /// [onMessage] receives localized, non-fatal status text (empty list,
  /// failed connect) so each caller can render it its own way (inline text,
  /// snackbar, ...).
  Future<DeviceConnectionResult?> findAndConnectBle(
    BuildContext context, {
    void Function(String message)? onMessage,
  }) async {
    if (_disposed || isActive.value) return null;
    final generation = ++_generation;
    isActive.value = true;
    int? token;
    try {
      if (connectionCoordinator case final coordinator?) {
        token = await coordinator.beginManualOperation();
        if (_disposed || generation != _generation) {
          if (token != null) coordinator.endManualOperation(token);
          return null;
        }
        if (token == null) return null;
        _coordinatorToken = token;
        coordinator.setManualPhase(token, DeviceConnectionPhase.searching);
      }
      if (_disposed || generation != _generation || !context.mounted) {
        return null;
      }
      return await _run(context, generation, onMessage);
    } catch (error) {
      if (_isCurrent(generation) && context.mounted) {
        onMessage?.call(
          context.tr(
            'Chưa kết nối được thiết bị. Hãy thử lại.',
            '暂时无法连接设备，请重试。',
          ),
        );
      }
      return DeviceConnectionResult(
        error is DeviceConnectionBusyException
            ? DeviceConnectionOutcome.busy
            : DeviceConnectionOutcome.failed,
      );
    } finally {
      if (token != null) connectionCoordinator?.endManualOperation(token);
      if (!_disposed && generation == _generation) {
        _coordinatorToken = null;
        isActive.value = false;
      }
    }
  }

  Future<DeviceConnectionResult?> _run(
    BuildContext context,
    int generation,
    void Function(String message)? onMessage,
  ) async {
    final foundDevices = await _controller.scanAiv0Devices();
    final devices = _prioritizeBleDevices(foundDevices);
    if (!_isCurrent(generation) || !context.mounted) return null;
    if (devices.isEmpty) {
      final message = context.tr(
        'Không tìm thấy thiết bị. Hãy bật thiết bị và thử lại.',
        '未找到设备。请开启设备后重试。',
      );
      onMessage?.call(message);
      return null;
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
                  itemBuilder: (itemContext, index) {
                    final device = devices[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (index == 0 ||
                            _isLikelyBle(devices[index - 1]) !=
                                _isLikelyBle(device))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                              itemContext,
                            ).colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.bluetooth_rounded,
                              color: Theme.of(itemContext).colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            localizedDeviceName(
                              device.name,
                              _controller.displayLanguage,
                              deviceId: device.id,
                            ),
                          ),
                          subtitle: Text('${device.id} • ${device.rssi} dBm'),
                          onTap: () => Navigator.of(itemContext).pop(device),
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
      return null;
    }
    if (connectionCoordinator?.isCurrent(_coordinatorToken ?? -1) ?? false) {
      connectionCoordinator!.setManualPhase(
        _coordinatorToken!,
        DeviceConnectionPhase.connecting,
      );
    }
    final result = await _controller.connectAiv0Device(selected);
    if (_isCurrent(generation) && context.mounted && !result.succeeded) {
      onMessage?.call(
        switch (result.outcome) {
          DeviceConnectionOutcome.busy => context.tr(
            'Ứng dụng đang bận. Hãy thử lại sau.',
            '应用正忙，请稍后重试。',
          ),
          DeviceConnectionOutcome.unavailable => context.tr(
            'Thiết bị chưa khả dụng. Hãy kiểm tra kết nối Bluetooth rồi thử lại.',
            '设备暂不可用。请检查蓝牙连接后重试。',
          ),
          _ => context.tr('Chưa kết nối được thiết bị. Hãy thử lại.', '暂时无法连接设备，请重试。'),
        },
      );
    }
    return result;
  }

  Future<T?> _showDevicePicker<T extends Object>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = ModalBottomSheetRoute<T>(
      builder: (routeContext) => DisplayLanguageScope(
        language: _controller.displayLanguage,
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

  bool _isLikelyBle(Aiv0BleDevice device) =>
      device.advertisesControlService || device.isLikelyAiv0;

  List<Aiv0BleDevice> _prioritizeBleDevices(List<Aiv0BleDevice> devices) =>
      List<Aiv0BleDevice>.of(devices)..sort((a, b) {
        if (_isLikelyBle(a) != _isLikelyBle(b)) return _isLikelyBle(a) ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });

  /// Cancels any in-flight scan/connect and releases the manual lock.
  Future<void> cancel() async {
    _generation++;
    final picker = _devicePickerRoute;
    _devicePickerRoute = null;
    if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
    _coordinatorToken = null;
    isActive.value = false;
    try {
      await (connectionCoordinator?.cancel() ??
          _controller.cancelManualDeviceConnection());
    } catch (error) {
      debugPrint('BLE picker cancellation failed: $error');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final picker = _devicePickerRoute;
    if (picker?.isActive == true) {
      scheduleMicrotask(() {
        if (picker?.isActive == true) picker!.navigator?.removeRoute(picker);
      });
    }
    isActive.dispose();
  }
}
