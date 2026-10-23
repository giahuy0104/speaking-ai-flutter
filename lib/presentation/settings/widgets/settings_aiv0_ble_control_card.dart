import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/device_display_name.dart';
import '../../../l10n/display_language.dart';
import 'settings_device_tile.dart';

class SettingsAiv0BleControlCard extends StatelessWidget {
  const SettingsAiv0BleControlCard({
    super.key,
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
    return SettingsDeviceTile(
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
