import 'package:flutter/material.dart';
import '../../../core/device/device_display_name.dart';
import '../../../core/device/device_connection_history.dart';
import '../../../l10n/display_language.dart';

class SettingsLastConnectedDeviceTile extends StatelessWidget {
  const SettingsLastConnectedDeviceTile({super.key, required this.record});
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
