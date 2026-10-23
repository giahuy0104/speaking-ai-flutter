import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import 'settings_ble_diagnostic_line.dart';

class SettingsBleDiagnosticsCard extends StatelessWidget {
  const SettingsBleDiagnosticsCard({
    super.key,
    this.embedded = false,
    required this.status,
    required this.events,
    required this.mainDispatchStatus,
    required this.mainDispatchAt,
    required this.disabled,
    required this.onScan,
    required this.onDisconnect,
  });

  final bool embedded;
  final Aiv0BleStatus status;
  final List<Aiv0ButtonEvent> events;
  final String mainDispatchStatus;
  final DateTime? mainDispatchAt;
  final bool disabled;
  final VoidCallback onScan;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connected = status.isConnected;
    final busy =
        status.phase == Aiv0BlePhase.scanning ||
        status.phase == Aiv0BlePhase.connecting ||
        status.phase == Aiv0BlePhase.reconnecting;
    final stateColor = connected
        ? AppColors.success
        : status.phase == Aiv0BlePhase.error
        ? AppColors.coral
        : AppColors.muted;
    final name = status.deviceName?.trim();
    final hasNativeDiagnostics =
        status.peripheralState != null ||
        status.mainNotificationState != null ||
        status.lastDisconnectCode != null ||
        status.lastNotificationRecovery != null ||
        status.diagnosticTimeline.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: embedded
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.all(14),
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
              border: Border.all(color: stateColor.withValues(alpha: 0.25)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HomiIconBadge(
                icon: connected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.settings_remote_rounded,
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
                      name == null || name.isEmpty
                          ? context.tr('BLE Control AIV0 V1', 'AIV0 V1 BLE 控制')
                          : name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _detail(context),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'BLE: MAIN, pin, firmware và trạng thái • Âm thanh: HFP hai chiều',
              'BLE：MAIN、电量、固件和状态 • 音频：双向 HFP',
            ),
            style: const TextStyle(
              color: AppColors.indigo,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasNativeDiagnostics) ...<Widget>[
            const SizedBox(height: 9),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('aiv0-technical-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined, size: 21),
                title: Text(
                  context.tr('Chi tiết kỹ thuật', '技术详情'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                children: <Widget>[
                  Container(
                    key: const Key('aiv0-native-diagnostics'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        SettingsBleDiagnosticLine(
                          label: context.tr('GATT thực tế', '实际 GATT'),
                          value:
                              '${status.peripheralState ?? 'unknown'} • MAIN Notify '
                              '${status.mainNotificationState ?? 'unknown'}',
                        ),
                        if (status.lastDisconnectCode != null ||
                            status.lastDisconnectMessage != null)
                          SettingsBleDiagnosticLine(
                            label: context.tr('Mất BLE gần nhất', '最近 BLE 断开'),
                            value: <String>[
                              if (status.lastDisconnectAt != null)
                                _formatEventTime(status.lastDisconnectAt!),
                              if (status.lastDisconnectCode != null)
                                status.lastDisconnectCode!,
                              if (status.lastDisconnectMessage != null)
                                status.lastDisconnectMessage!,
                            ].join(' • '),
                          ),
                        if (status.lastNotificationRecovery != null)
                          SettingsBleDiagnosticLine(
                            label: context.tr('Khôi phục MAIN', '恢复 MAIN'),
                            value: status.lastNotificationRecovery!,
                          ),
                        SettingsBleDiagnosticLine(
                          label: context.tr('Retry đang hoãn', '延迟重试'),
                          value: '${status.deferredRecoveryRepeatCount}',
                        ),
                        if (status.diagnosticTimeline.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            context.tr(
                              'Timeline BLE / HFP (tối đa 80 sự kiện gần nhất)',
                              'BLE / HFP 时间线（最近最多 80 个事件）',
                            ),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            key: const Key('aiv0-ble-hfp-timeline'),
                            constraints: const BoxConstraints(maxHeight: 360),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLowest
                                  .withValues(alpha: 0.76),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                status.diagnosticTimeline
                                    .skip(
                                      status.diagnosticTimeline.length > 80
                                          ? status.diagnosticTimeline.length -
                                                80
                                          : 0,
                                    )
                                    .map(_formatTimelineEvent)
                                    .join('\n'),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10.5,
                                  height: 1.45,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (connected) ...<Widget>[
            const SizedBox(height: 9),
            SettingsBleDiagnosticLine(
              label: context.tr('Pin & firmware', '电量与固件'),
              value:
                  '${status.batteryPercent == null ? context.tr('Chưa đọc pin', '尚未读取电量') : 'Pin ${status.batteryPercent}%'}'
                  ' • FW ${status.firmwareRevision ?? context.tr('chưa rõ', '未知')}',
            ),
          ],
          if (status.deviceId != null ||
              events.isNotEmpty ||
              status.packetCount > 0) ...<Widget>[
            const SizedBox(height: 9),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const Key('aiv0-packet-details'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                leading: const Icon(Icons.data_object_rounded, size: 21),
                title: Text(
                  context.tr('Dữ liệu MAIN', 'MAIN 数据'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                children: <Widget>[
                  SettingsBleDiagnosticLine(
                    label: context.tr('Giao thức packet', '数据包协议'),
                    value: status.protocolConfirmed
                        ? context.tr('Đã xác nhận', '已确认')
                        : context.tr(
                            'MAIN Raw Hex đã điều khiển APP • chưa gửi APP State',
                            'MAIN Raw Hex 已控制 APP • 尚未发送 APP State',
                          ),
                  ),
                  SettingsBleDiagnosticLine(
                    label: context.tr('MAIN → trợ lý', 'MAIN → 助手'),
                    value: mainDispatchAt == null
                        ? mainDispatchStatus
                        : '${_formatEventTime(mainDispatchAt!)} • '
                              '$mainDispatchStatus',
                  ),
                  if (events.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Log MAIN / Raw Hex gần nhất',
                        '最近的 MAIN / Raw Hex 日志',
                      ),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    ...events
                        .take(5)
                        .map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: SelectableText(
                              '${_formatEventTime(event.receivedAt)}  '
                              '${event.transportSource == 'hfpRemote' ? '[HFP] ' : '[BLE] '}'
                              '${event.isDuplicate ? '[TRÙNG] ' : ''}${event.rawHex}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: event.isDuplicate
                                    ? AppColors.coral
                                    : AppColors.indigo,
                              ),
                            ),
                          ),
                        ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      '${status.packetCount} gói • ${status.invalidPacketCount} lỗi • ${status.duplicatePacketCount} trùng • ${status.remoteMainCount} MAIN HFP${status.remoteMainCommandsEnabled ? ' • HFP remote sẵn sàng' : ''} • ${status.reconnectCount} reconnect',
                      '${status.packetCount} 包 • ${status.invalidPacketCount} 错误 • ${status.duplicatePacketCount} 重复 • ${status.remoteMainCount} 次 HFP MAIN${status.remoteMainCommandsEnabled ? ' • HFP remote 已就绪' : ''} • ${status.reconnectCount} 次重连',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: HomiWaveform(active: true, width: 58, height: 24),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: disabled || status.phase == Aiv0BlePhase.disabled
                    ? null
                    : connected
                    ? () => onDisconnect()
                    : onScan,
                icon: Icon(
                  connected ? Icons.link_off_rounded : Icons.search_rounded,
                ),
                label: Text(
                  connected
                      ? context.tr('Ngắt BLE', '断开 BLE')
                      : context.tr('Quét & kết nối', '扫描并连接'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _detail(BuildContext context) {
    return switch (status.phase) {
      Aiv0BlePhase.disabled => context.tr(
        'BLE Control AIV0 chỉ hoạt động trên Android/iOS native.',
        'AIV0 BLE 控制仅适用于 Android/iOS 原生应用。',
      ),
      Aiv0BlePhase.idle => context.tr(
        'Chưa kết nối service 9E3B0001.',
        '尚未连接 9E3B0001 服务。',
      ),
      Aiv0BlePhase.scanning => context.tr(
        'Đang tìm HM-D001 ở gần…',
        '正在搜索附近的 HM-D001…',
      ),
      Aiv0BlePhase.connecting => context.tr(
        'Đang xác nhận 9E3B0001/0002/0003…',
        '正在验证 9E3B0001/0002/0003…',
      ),
      Aiv0BlePhase.connected =>
        status.message ?? context.tr('BLE Control đã kết nối.', 'BLE 控制已连接。'),
      Aiv0BlePhase.reconnecting =>
        status.message ?? context.tr('Đang tự kết nối lại…', '正在自动重连…'),
      Aiv0BlePhase.error =>
        status.message ?? context.tr('Kết nối BLE gặp lỗi.', 'BLE 连接发生错误。'),
    };
  }

  String _formatEventTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}.'
        '${value.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatTimelineEvent(Aiv0BleDiagnosticEvent event) {
    final metadata = event.metadata.entries
        .where((entry) => entry.key != 'type')
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' • ');
    return <String>[
      '${_formatEventTime(event.occurredAt)}  ${event.stage}'
          '${event.caller == null ? '' : '  @${event.caller}'}',
      if (event.code != null) '  code=${event.code}',
      if (event.message != null) '  ${event.message}',
      if (metadata.isNotEmpty) '  $metadata',
      if (event.audioRoute != null) '  route=${event.audioRoute}',
    ].join('\n');
  }
}
