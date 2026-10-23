import 'package:flutter/material.dart';
import '../../../app/homi_connection_presentation.dart';
import '../../../core/device/device_connection_coordinator.dart';
import '../../../l10n/display_language.dart';
import 'settings_device_heading.dart';

class SettingsConnectionSummary extends StatelessWidget {
  const SettingsConnectionSummary({
    super.key,
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
        SettingsDeviceHeading(label: label, busy: busy, ready: ready),
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
