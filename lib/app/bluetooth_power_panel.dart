import 'dart:async';

import 'package:flutter/material.dart';

import '../core/device/aiv0_ble_control.dart';
import '../core/device/bluetooth_power_controller.dart';
import '../l10n/display_language.dart';

/// Checks the actual adapter before offering device connection actions.
class BluetoothPowerPanel extends StatefulWidget {
  const BluetoothPowerPanel({required this.controller, super.key});

  final BluetoothPowerController controller;

  @override
  State<BluetoothPowerPanel> createState() => _BluetoothPowerPanelState();
}

class _BluetoothPowerPanelState extends State<BluetoothPowerPanel>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAfterBuild();
  }

  @override
  void didUpdateWidget(BluetoothPowerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _refreshAfterBuild();
  }

  void _refreshAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final power = widget.controller;
      final state = power.state;
      final checking =
          !power.hasChecked || state == Aiv0BluetoothAdapterState.resetting;
      final label = checking
          ? context.tr('Đang kiểm tra Bluetooth…', '正在检查蓝牙…')
          : switch (state) {
              Aiv0BluetoothAdapterState.poweredOn => context.tr(
                'Bluetooth đã bật',
                '蓝牙已开启',
              ),
              Aiv0BluetoothAdapterState.poweredOff => context.tr(
                'Bluetooth đang tắt',
                '蓝牙已关闭',
              ),
              Aiv0BluetoothAdapterState.unauthorized => context.tr(
                'Cần quyền Bluetooth',
                '需要蓝牙权限',
              ),
              Aiv0BluetoothAdapterState.unsupported => context.tr(
                'Máy này không hỗ trợ Bluetooth',
                '此设备不支持蓝牙',
              ),
              _ => context.tr('Chưa kiểm tra được Bluetooth', '暂时无法检查蓝牙'),
            };
      return Column(
        key: const Key('bluetooth-power-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              state == Aiv0BluetoothAdapterState.poweredOn
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
            ),
            title: Text(label),
            trailing: checking || power.isBusy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (!checking && state == Aiv0BluetoothAdapterState.poweredOff)
            if (power.canRequestEnable)
              SwitchListTile.adaptive(
                key: const Key('bluetooth-enable-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('Bật Bluetooth', '开启蓝牙')),
                subtitle: Text(
                  context.tr(
                    'Xác nhận bật Bluetooth khi điện thoại yêu cầu.',
                    '请在手机提示时确认开启蓝牙。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // Only the adapter result can turn this control on.
                value: false,
                onChanged: power.isBusy
                    ? null
                    : (_) => unawaited(power.enable()),
              )
            else ...<Widget>[
              Text(
                context.tr(
                  'iPhone không cho ứng dụng tự bật Bluetooth. Hãy thử bật trong Trung tâm điều khiển. Nếu Bluetooth đã tắt hoàn toàn, mở Cài đặt > Bluetooth để bật, rồi quay lại HOMI.',
                  'iPhone 不允许应用直接开启蓝牙。请尝试在控制中心开启；如果蓝牙已完全关闭，请前往“设置 > 蓝牙”开启，然后返回 HOMI。',
                ),
              ),
              TextButton(
                key: const Key('bluetooth-refresh'),
                onPressed: power.isBusy
                    ? null
                    : () => unawaited(power.refresh()),
                child: Text(context.tr('Kiểm tra lại', '重新检查')),
              ),
            ],
          if (!checking && state == Aiv0BluetoothAdapterState.unauthorized)
            TextButton.icon(
              key: const Key('bluetooth-authorize'),
              onPressed: power.isBusy
                  ? null
                  : () => unawaited(power.authorize()),
              icon: const Icon(Icons.lock_open_rounded),
              label: Text(context.tr('Cho phép Bluetooth', '允许蓝牙')),
            ),
          if (state == Aiv0BluetoothAdapterState.unauthorized &&
              power.needsPermissionSettings &&
              power.canOpenPermissionSettings)
            TextButton.icon(
              key: const Key('bluetooth-open-permission-settings'),
              onPressed: power.isBusy
                  ? null
                  : () => unawaited(power.openPermissionSettings()),
              icon: const Icon(Icons.app_settings_alt_rounded),
              label: Text(context.tr('Mở cài đặt quyền HOMI', '打开 HOMI 权限设置')),
            ),
          if (power.hasChecked &&
              (state == Aiv0BluetoothAdapterState.unknown ||
                  state == Aiv0BluetoothAdapterState.resetting))
            TextButton(
              key: const Key('bluetooth-refresh'),
              onPressed: power.isBusy ? null : () => unawaited(power.refresh()),
              child: Text(context.tr('Kiểm tra lại', '重新检查')),
            ),
          if (power.actionFailed && !power.isBusy)
            Text(
              state == Aiv0BluetoothAdapterState.unauthorized
                  ? context.tr(
                      'Chưa được cấp quyền Bluetooth. Hãy thử lại.',
                      '尚未获得蓝牙权限，请重试。',
                    )
                  : context.tr(
                      'Bluetooth chưa bật. Bạn có thể thử lại.',
                      '蓝牙尚未开启，您可以重试。',
                    ),
              key: const Key('bluetooth-action-failed'),
            ),
        ],
      );
    },
  );
}
