import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../core/audio/audio_input.dart';
import '../../../l10n/display_language.dart';
import 'settings_ble_diagnostic_line.dart';

class SettingsHfpDetailsCard extends StatelessWidget {
  const SettingsHfpDetailsCard({
    super.key,
    this.embedded = false,
    required this.status,
    required this.browserManaged,
    required this.selected,
    required this.disabled,
    required this.onFind,
    required this.onDisconnect,
  });

  final bool embedded;
  final BluetoothAudioStatus status;
  final bool browserManaged;
  final bool selected;
  final bool disabled;
  final VoidCallback onFind;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy = status.isBusy;
    final stateColor = selected
        ? AppColors.success
        : status.phase == BluetoothAudioConnectionPhase.error
        ? AppColors.coral
        : connected
        ? AppColors.indigo
        : AppColors.muted;
    final deviceName = status.deviceName?.trim();
    return Container(
      width: double.infinity,
      padding: embedded
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: connected
                  ? Color.alphaBlend(
                      AppColors.success.withValues(alpha: 0.12),
                      colorScheme.surfaceContainer,
                    )
                  : colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: stateColor.withValues(alpha: 0.22)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HomiIconBadge(
                icon: Icons.headset_mic_rounded,
                foregroundColor: stateColor,
                backgroundColor: stateColor.withValues(alpha: 0.11),
                size: 40,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      deviceName == null || deviceName.isEmpty
                          ? context.tr('Mic Bluetooth HFP', '蓝牙 HFP 麦克风')
                          : deviceName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _detail(context, selected: selected),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connected && !browserManaged) ...<Widget>[
            const SizedBox(height: 9),
            SettingsBleDiagnosticLine(
              label: context.tr('Micro thực tế', '实际麦克风'),
              value: status.routeActive
                  ? status.inputDeviceName ??
                        context.tr('HFP/SCO (không rõ tên)', 'HFP/SCO（名称未知）')
                  : context.tr(
                      'Chưa xác nhận • đường SCO chưa mở',
                      '尚未确认 • SCO 通道未打开',
                    ),
            ),
            SettingsBleDiagnosticLine(
              label: context.tr('Loa thực tế', '实际扬声器'),
              value: status.routeActive
                  ? status.outputDeviceName ??
                        context.tr('HFP/SCO (không rõ tên)', 'HFP/SCO（名称未知）')
                  : context.tr(
                      'Chưa xác nhận • đường SCO chưa mở',
                      '尚未确认 • SCO 通道未打开',
                    ),
            ),
            SettingsBleDiagnosticLine(
              label: context.tr('Đường SCO', 'SCO 通道'),
              value: status.routeActive
                  ? context.tr('Đang hoạt động', '正在使用')
                  : context.tr('Chưa mở', '未打开'),
            ),
          ],
          const SizedBox(height: 6),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: HomiWaveform(active: true, width: 58, height: 24),
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    disabled ||
                        status.phase ==
                            BluetoothAudioConnectionPhase.unsupported ||
                        status.phase == BluetoothAudioConnectionPhase.disabled
                    ? null
                    : selected
                    ? () => onDisconnect()
                    : onFind,
                icon: Icon(
                  selected
                      ? Icons.link_off_rounded
                      : Icons.manage_search_rounded,
                ),
                label: Text(
                  selected
                      ? context.tr('Dùng mic điện thoại', '使用手机麦克风')
                      : connected && !browserManaged
                      ? context.tr('Dùng mic này', '使用此麦克风')
                      : browserManaged
                      ? context.tr('Chọn mic HFP', '选择 HFP 麦克风')
                      : context.tr('Tìm HFP', '查找 HFP'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _detail(BuildContext context, {required bool selected}) {
    if (browserManaged) {
      return switch (status.phase) {
        BluetoothAudioConnectionPhase.disabled => context.tr(
          'HFP Web đang tắt trong cấu hình bản build.',
          '此构建中已关闭网页 HFP。',
        ),
        BluetoothAudioConnectionPhase.unsupported => context.tr(
          'Trình duyệt này không hỗ trợ chọn mic Bluetooth.',
          '此浏览器不支持选择蓝牙麦克风。',
        ),
        BluetoothAudioConnectionPhase.permissionRequired => context.tr(
          'Cần cho phép quyền micro của trình duyệt.',
          '需要允许浏览器使用麦克风。',
        ),
        BluetoothAudioConnectionPhase.scanning => context.tr(
          'Đang kiểm tra các mic mà trình duyệt cung cấp…',
          '正在检查浏览器提供的麦克风…',
        ),
        BluetoothAudioConnectionPhase.connecting => context.tr(
          'Đang chọn mic Bluetooth…',
          '正在选择蓝牙麦克风…',
        ),
        BluetoothAudioConnectionPhase.discovering => context.tr(
          'Đang kiểm tra đường âm thanh của trình duyệt…',
          '正在检查浏览器音频通道…',
        ),
        BluetoothAudioConnectionPhase.ready => context.tr(
          'Đã chọn • sẵn sàng ghi âm qua Web',
          '已选择 • 可通过网页录音',
        ),
        BluetoothAudioConnectionPhase.recording => context.tr(
          'Đang ghi âm từ mic Bluetooth trên Web',
          '正在通过网页蓝牙麦克风录音',
        ),
        BluetoothAudioConnectionPhase.error =>
          status.message ??
              context.tr('Không thể dùng mic Bluetooth.', '无法使用蓝牙麦克风。'),
        BluetoothAudioConnectionPhase.idle => context.tr(
          'Kết nối tai nghe trong hệ thống rồi chọn mic tại đây.',
          '请先在系统中连接耳机，再在此选择麦克风。',
        ),
      };
    }
    return switch (status.phase) {
      BluetoothAudioConnectionPhase.disabled => context.tr(
        'HFP đang tắt trong cấu hình bản build.',
        '此构建中已关闭 HFP。',
      ),
      BluetoothAudioConnectionPhase.unsupported => context.tr(
        'Điện thoại hoặc bản ứng dụng này không hỗ trợ HFP.',
        '此手机或应用版本不支持 HFP。',
      ),
      BluetoothAudioConnectionPhase.permissionRequired => context.tr(
        'Cần quyền Thiết bị ở gần/Bluetooth.',
        '需要“附近设备/蓝牙”权限。',
      ),
      BluetoothAudioConnectionPhase.scanning => context.tr(
        'Đang tìm thiết bị HFP đã ghép đôi…',
        '正在查找已配对的 HFP 设备…',
      ),
      BluetoothAudioConnectionPhase.connecting => context.tr(
        'Đang kiểm tra kết nối HFP…',
        '正在检查 HFP 连接…',
      ),
      BluetoothAudioConnectionPhase.discovering => context.tr(
        'Đang kiểm tra đường âm thanh SCO…',
        '正在检查 SCO 音频通道…',
      ),
      BluetoothAudioConnectionPhase.ready => context.tr(
        selected
            ? 'Nguồn đang chọn • HOMI qua HFP/SCO'
            : 'Đã kết nối • bấm “Dùng mic này” để chọn',
        selected ? '当前音源 • HOMI 通过 HFP/SCO' : '已连接 • 点击“使用此麦克风”',
      ),
      BluetoothAudioConnectionPhase.recording => context.tr(
        'Đang nhận diện từ mic HFP/SCO',
        '正在通过 HFP/SCO 麦克风识别',
      ),
      BluetoothAudioConnectionPhase.error =>
        status.message ?? context.tr('Kết nối HFP gặp lỗi.', 'HFP 连接发生错误。'),
      BluetoothAudioConnectionPhase.idle => context.tr(
        'Kết nối HFP trong Cài đặt hệ thống, rồi chọn mic tại đây.',
        '请先在系统设置中连接 HFP，再在此选择麦克风。',
      ),
    };
  }
}
