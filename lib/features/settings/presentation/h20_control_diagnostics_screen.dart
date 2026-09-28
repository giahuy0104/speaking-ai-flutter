import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/homi_ui.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/device/aivo_control_dispatcher.dart';
import '../../conversation/application/conversation_settings_port.dart';

/// Button diagnostics only: never exports voice, ASR or API diagnostics.
class H20ControlDiagnosticsScreen extends StatefulWidget {
  const H20ControlDiagnosticsScreen({
    required this.controller,
    required this.controls,
    super.key,
  });

  final ConversationSettingsPort controller;
  final AivoControlDispatcher controls;

  @override
  State<H20ControlDiagnosticsScreen> createState() =>
      _H20ControlDiagnosticsScreenState();
}

class _H20ControlDiagnosticsScreenState
    extends State<H20ControlDiagnosticsScreen> {
  static const _checks = <(Aiv0Button, Aiv0ButtonGesture, String)>[
    (Aiv0Button.main, Aiv0ButtonGesture.shortPress, 'MAIN SHORT'),
    (Aiv0Button.main, Aiv0ButtonGesture.longPress, 'MAIN LONG'),
    (Aiv0Button.volumeUp, Aiv0ButtonGesture.longPress, 'Volume Up LONG'),
    (Aiv0Button.volumeDown, Aiv0ButtonGesture.longPress, 'Volume Down LONG'),
    (Aiv0Button.power, Aiv0ButtonGesture.shortPress, 'Power H20 SHORT'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controls.setDiagnosticsActive(true));
    });
  }

  @override
  void dispose() {
    final controls = widget.controls;
    unawaited(
      Future<void>.microtask(() => controls.setDiagnosticsActive(false)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.controls]),
    builder: (context, _) {
      final controls = widget.controls;
      final ble = widget.controller.aiv0BleStatus;
      final history = controls.history;
      final last = history.firstOrNull;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Điều khiển thiết bị H20'),
          actions: [
            IconButton(
              key: const Key('h20-copy-log'),
              tooltip: 'Sao chép log',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: controls.exportLog()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép log nút H20.')),
                );
              },
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              key: const Key('h20-clear-log'),
              tooltip: 'Xóa log',
              onPressed: controls.clearLog,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: HomiUi.pagePadding.copyWith(top: 16, bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Chỉ quan sát tín hiệu theo mặc định. Nút chưa xác nhận giữ UNKNOWN; '
                  'không bật giao thức Draft. Không xử lý nút nguồn điện thoại.',
                ),
                const SizedBox(height: 16),
                _section(context, 'Kết nối hiện tại', [
                  _field('Thiết bị', ble.deviceName ?? 'Chưa kết nối'),
                  _field('Mã thiết bị', ble.deviceId ?? '—'),
                  _field('BLE Control', _blePhase(ble.phase)),
                  _field(
                    'Audio route',
                    _audioRoute(widget.controller.hfpAudioStatus),
                  ),
                  _field('Nền tảng', controls.platform),
                  _field('Firmware', ble.firmwareRevision ?? 'Chưa xác định'),
                  _field(
                    'Nguồn sự kiện cuối',
                    last == null ? '—' : _source(last.input.source),
                  ),
                  _field(
                    'Protocol',
                    last == null ? 'Unknown' : _protocol(last.input.protocol),
                  ),
                ]),
                _section(context, 'Sự kiện cuối cùng', [
                  if (last == null)
                    const Text('Chưa có sự kiện.', key: Key('h20-no-events'))
                  else ...[
                    _field(
                      'Nút',
                      _button(last.input.button),
                      key: const Key('h20-last-button'),
                    ),
                    _field('Gesture', _gesture(last.input.gesture)),
                    _field(
                      'Thời gian',
                      last.input.occurredAt.toLocal().toIso8601String(),
                    ),
                    _field('Sequence', '${last.input.sequence ?? '—'}'),
                    _field(
                      'Raw Hex / Key',
                      last.safeRawPayload.isEmpty ? '—' : last.safeRawPayload,
                      key: const Key('h20-last-raw'),
                    ),
                    _field('Intent', last.intent.name),
                    _field('Kết quả', last.status.name),
                    _field('Trước → sau', '${last.before} → ${last.after}'),
                    if (!last.input.isPhysical)
                      const Text(
                        'Đây là mô phỏng/nút ảo, không chứng minh nút vật lý hoạt động.',
                      ),
                  ],
                ]),
                _section(context, 'Khả năng nút vật lý', [
                  const Text(
                    'Bấm “Thử 8 giây”, rồi bấm nút thật. Chỉ tín hiệu nhận diện được '
                    'trên nền tảng hiện tại mới ghi “Đã nhận”. Không nhận trong cửa sổ '
                    'test không có nghĩa thiết bị không hỗ trợ.',
                  ),
                  const SizedBox(height: 12),
                  for (final (button, gesture, label) in _checks)
                    _capabilityRow(context, button, gesture, label),
                ]),
                _section(context, 'Mô phỏng luồng dùng chung', [
                  SwitchListTile.adaptive(
                    key: const Key('h20-execute-tests'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Chạy lệnh thử vào bài đang mở'),
                    subtitle: const Text(
                      'Cảnh báo: bật lên có thể dừng ghi âm, chuyển câu hoặc mở trợ lý. '
                      'Tắt: chỉ ghi log, không chạy lệnh.',
                    ),
                    value: controls.executeTests,
                    onChanged: controls.setExecuteTests,
                  ),
                  const Text(
                    'Mô phỏng không xác nhận firmware và không đánh dấu “Đã nhận”.',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (button, gesture, label) in _checks)
                        OutlinedButton(
                          key: Key(
                            'h20-simulate-${button.name}-${gesture.name}',
                          ),
                          onPressed: () =>
                              unawaited(controls.simulate(button, gesture)),
                          child: Text(label),
                        ),
                    ],
                  ),
                ]),
                _section(context, 'Lịch sử nút (${history.length}/80)', [
                  const Text(
                    'Chỉ lưu trong RAM: thời gian, nguồn, raw, intent và kết quả. '
                    'Không chứa âm thanh, lời nói hay khóa API.',
                  ),
                  const SizedBox(height: 8),
                  for (var index = 0; index < history.length; index++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SelectableText(
                        history[index].logLine,
                        key: Key('h20-history-$index'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _capabilityRow(
    BuildContext context,
    Aiv0Button button,
    Aiv0ButtonGesture gesture,
    String label,
  ) {
    final controls = widget.controls;
    final current = controls.platform.toLowerCase();
    final capability = _capability(controls.capability(button, gesture));
    final evidence = controls.history
        .where(
          (record) =>
              record.input.isPhysical &&
              record.input.actionable &&
              record.input.button == button &&
              record.input.gesture == gesture &&
              record.status != AivoControlStatus.duplicate,
        )
        .firstOrNull;
    String onPlatform(String platform) =>
        current == platform ? capability : 'Chưa thử';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Android: ${onPlatform('android')}\niOS: ${onPlatform('ios')}',
                  key: Key('h20-capability-${button.name}-${gesture.name}'),
                ),
              ),
              TextButton(
                key: Key('h20-probe-${button.name}-${gesture.name}'),
                onPressed: () => controls.beginProbe(button, gesture),
                child: const Text('Thử 8 giây'),
              ),
            ],
          ),
          if (evidence != null)
            Text(
              'Nguồn đã nhận: ${_source(evidence.input.source)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: HomiSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _field(String label, String value, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(value),
      ],
    ),
  );

  static String _audioRoute(BluetoothAudioStatus status) {
    final reported = status.audioRoute?.trim();
    if (reported != null &&
        reported.isNotEmpty &&
        reported != 'system/default') {
      return reported;
    }
    if (status.routeActive &&
        status.inputDeviceName != null &&
        status.outputDeviceName != null) {
      return 'HFP/SCO • ${status.outputDeviceName}';
    }
    return 'Chưa xác định (theo hệ điều hành)';
  }

  static String _blePhase(Aiv0BlePhase phase) => switch (phase) {
    Aiv0BlePhase.connected => 'Đã kết nối',
    Aiv0BlePhase.connecting || Aiv0BlePhase.reconnecting => 'Đang kết nối',
    Aiv0BlePhase.scanning => 'Đang quét',
    Aiv0BlePhase.disabled => 'Không khả dụng',
    _ => 'Mất kết nối',
  };
  static String _button(Aiv0Button button) => switch (button) {
    Aiv0Button.main => 'MAIN',
    Aiv0Button.volumeUp => 'VOLUME_UP',
    Aiv0Button.volumeDown => 'VOLUME_DOWN',
    Aiv0Button.power => 'POWER H20',
    Aiv0Button.unknown => 'UNKNOWN',
  };
  static String _gesture(Aiv0ButtonGesture gesture) => switch (gesture) {
    Aiv0ButtonGesture.shortPress => 'SHORT',
    Aiv0ButtonGesture.longPress => 'LONG',
    Aiv0ButtonGesture.release => 'RELEASE',
    Aiv0ButtonGesture.unknown => 'UNKNOWN',
  };
  static String _source(AivoControlSource source) => switch (source) {
    AivoControlSource.ble => 'BLE',
    AivoControlSource.androidMediaKey => 'Android Media Key',
    AivoControlSource.iosRemoteCommand => 'iOS Remote Command',
    AivoControlSource.virtualButton => 'Nút ảo',
    AivoControlSource.simulation => 'Mô phỏng',
  };
  static String _protocol(String protocol) => switch (protocol) {
    'observedV1' => 'Observed V1',
    'draft' => 'Draft',
    'simulation' => 'Mô phỏng (không phải firmware)',
    _ => 'Unknown',
  };
  static String _capability(AivoCapability value) => switch (value) {
    AivoCapability.untested => 'Chưa thử',
    AivoCapability.waiting => 'Đang chờ tín hiệu',
    AivoCapability.received => 'Đã nhận',
    AivoCapability.notReceived => 'Không nhận trong 8 giây',
  };
}
