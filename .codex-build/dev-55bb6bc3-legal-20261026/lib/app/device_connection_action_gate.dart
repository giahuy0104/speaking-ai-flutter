import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/display_language.dart';

enum DeviceConnectionActionState { searching, unavailable, ready }

/// Opens connection feedback only for a protected user action. Native status
/// changes alone never create a route or resume a cancelled action.
class DeviceConnectionActionGate {
  DeviceConnectionActionGate({
    required this.state,
    required this.onRetry,
    required this.onCancel,
    this.language,
  });

  final ValueListenable<DeviceConnectionActionState> state;
  final Future<void> Function() onRetry;
  final Future<void> Function() onCancel;
  final DisplayLanguage Function()? language;
  DialogRoute<bool>? _route;
  bool _disposed = false;

  Future<bool> ensureConnected(BuildContext context) async {
    if (_disposed || _route != null) return false;
    if (state.value == DeviceConnectionActionState.ready) return true;
    final navigator = Navigator.of(context, rootNavigator: true);
    var accepted = false;
    var cancelled = false;
    Future<void> cancelAttempt() async {
      if (cancelled || accepted) return;
      cancelled = true;
      try {
        await onCancel();
      } catch (error) {
        debugPrint('Device search cancellation failed: $error');
      }
    }

    late final DialogRoute<bool> route;
    void finish(bool result) {
      if (_disposed || !identical(_route, route) || !route.isActive) return;
      accepted = result;
      // Remove this exact route: a late connection must never pop a newer page.
      navigator.removeRoute(route, result);
      if (!result) unawaited(cancelAttempt());
    }

    void observe() {
      if (state.value == DeviceConnectionActionState.ready) {
        scheduleMicrotask(() {
          if (state.value == DeviceConnectionActionState.ready) {
            // Another flow may have navigated above this dialog (for example
            // hardware MAIN). Do not resume the old action over that page.
            finish(route.isCurrent);
          }
        });
      }
    }

    route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      settings: const RouteSettings(name: '/device-connection-action'),
      builder: (_) => DisplayLanguageScope(
        language: language?.call() ?? DisplayLanguageScope.of(context),
        child: _DeviceConnectionActionDialog(
          state: state,
          onCancel: () => finish(false),
          onRetry: onRetry,
        ),
      ),
    );
    _route = route;
    state.addListener(observe);
    try {
      final result = await navigator.push<bool>(route);
      if (result != true) unawaited(cancelAttempt());
      return !_disposed &&
          result == true &&
          state.value == DeviceConnectionActionState.ready;
    } finally {
      state.removeListener(observe);
      if (identical(_route, route)) _route = null;
    }
  }

  void dispose() {
    _disposed = true;
    final route = _route;
    _route = null;
    if (route?.isActive == true) route!.navigator?.removeRoute(route, false);
  }
}

class _DeviceConnectionActionDialog extends StatefulWidget {
  const _DeviceConnectionActionDialog({
    required this.state,
    required this.onCancel,
    required this.onRetry,
  });

  final ValueListenable<DeviceConnectionActionState> state;
  final VoidCallback onCancel;
  final Future<void> Function() onRetry;

  @override
  State<_DeviceConnectionActionDialog> createState() =>
      _DeviceConnectionActionDialogState();
}

class _DeviceConnectionActionDialogState
    extends State<_DeviceConnectionActionDialog> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } catch (error) {
      debugPrint('Device search retry failed: $error');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.state,
    builder: (context, state, _) {
      final searching =
          _retrying || state == DeviceConnectionActionState.searching;
      return AlertDialog(
        key: const Key('device-connection-action-dialog'),
        icon: searching
            ? const Center(
                child: SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(),
                ),
              )
            : const Icon(Icons.bluetooth_disabled_rounded),
        title: Text(
          searching
              ? context.tr('Đang tìm thiết bị', '正在查找设备')
              : context.tr('Cần kết nối thiết bị', '需要连接设备'),
        ),
        content: Text(
          searching
              ? context.tr(
                  'HOMI đang tìm và kết nối thiết bị. Bạn có thể hủy để tiếp tục sử dụng ứng dụng.',
                  'HOMI 正在查找并连接设备。您可以取消并继续使用应用。',
                )
              : context.tr(
                  'Chưa kết nối được với HOMI. Hãy bật thiết bị, đặt gần điện thoại và kiểm tra Bluetooth, sau đó bấm Thử lại. Nếu BLE đã kết nối nhưng micro chưa sẵn sàng, vào Cài đặt để chọn và xác nhận micro của HOMI.',
                  '尚未连接到 HOMI。请开启设备、靠近手机并检查蓝牙，然后重试。如果 BLE 已连接但麦克风尚未就绪，请在应用设置中选择并确认 HOMI 麦克风。',
                ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('device-connection-action-cancel'),
            onPressed: widget.onCancel,
            child: Text(context.tr('Hủy', '取消')),
          ),
          FilledButton(
            key: const Key('device-connection-action-retry'),
            onPressed: _retrying ? null : () => unawaited(_retry()),
            child: Text(context.tr('Thử lại', '重试')),
          ),
        ],
      );
    },
  );
}
