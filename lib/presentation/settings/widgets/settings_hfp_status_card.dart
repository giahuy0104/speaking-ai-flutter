import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/device/device_display_name.dart';
import '../../../l10n/display_language.dart';
import 'settings_device_tile.dart';

class SettingsHfpStatusCard extends StatelessWidget {
  const SettingsHfpStatusCard({
    super.key,
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
    return SettingsDeviceTile(
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
