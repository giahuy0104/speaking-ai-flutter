import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/conversation/application/conversation_settings_port.dart';
import '../../l10n/display_language.dart';
import '../audio/hfp_audio_control.dart';
import 'device_connection_coordinator.dart';
import 'device_display_name.dart';

/// Scans for HFP microphones and lets the user pick one, showing the same
/// bottom sheet and guidance dialogs regardless of which screen triggers it
/// (Settings' manual "Tìm HFP" card, or Home's speak action). Keeping this in
/// one place avoids Settings and Home drifting into two different pickers for
/// the same action.
class DeviceHfpPickerFlow {
  DeviceHfpPickerFlow({
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

  /// Runs the full scan -> pick -> (confirm) -> connect round. Returns the
  /// connection result, or `null` if nothing was picked, the round was
  /// superseded/cancelled, or the lock was already held by another caller.
  /// [onMessage] receives localized, non-fatal status text (empty list,
  /// failed connect) so each caller can render it its own way (inline text,
  /// snackbar, ...); dialogs for the same situations are still shown here so
  /// both screens keep an identical guided experience.
  Future<DeviceConnectionResult?> findAndConnectHfp(
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
        coordinator.setManualPhase(
          token,
          DeviceConnectionPhase.preparingMicrophone,
        );
      }
      if (_disposed || generation != _generation || !context.mounted) {
        return null;
      }
      return await _run(context, generation, onMessage);
    } catch (error) {
      if (_isCurrent(generation) && context.mounted) {
        await _showHfpMessage(
          context,
          title: context.tr('Chưa thể dùng HFP', '暂时无法使用 HFP'),
          message: context.tr(
            'Chưa kết nối được micro. Hãy kiểm tra Bluetooth và thử lại.',
            '暂时无法连接麦克风。请检查蓝牙后重试。',
          ),
        );
      }
      return const DeviceConnectionResult(DeviceConnectionOutcome.failed);
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
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final foundDevices = await _controller.findHfpDevices();
    final devices = _prioritizeMicrophones(foundDevices);
    if (!_isCurrent(generation) || !context.mounted) return null;
    if (devices.isEmpty) {
      final message = context.tr(
        'Micro chưa khả dụng. Hãy kiểm tra Cài đặt Bluetooth.',
        '麦克风暂不可用。请检查蓝牙设置。',
      );
      onMessage?.call(message);
      await _showHfpMessage(
        context,
        title: _controller.supportsBrowserHfp
            ? context.tr('Chưa thấy mic Bluetooth trên Web', '网页中未发现蓝牙麦克风')
            : context.tr('Chưa có thiết bị HFP', '暂无 HFP 设备'),
        message: context.tr(
          _controller.supportsBrowserHfp
              ? 'Web không thể tự kết nối HFP. Hãy kết nối tai nghe trong Cài đặt Bluetooth, cho phép quyền micro, tải lại trang rồi bấm Chọn mic HFP. Safari trên iPhone có thể chỉ cung cấp mic iPhone.'
              : isIOS
              ? 'iOS chỉ cho ứng dụng chọn mic HFP đang kết nối. Hãy kết nối HM-D001 trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.'
              : 'Hãy ghép đôi tai nghe hoặc thiết bị HFP trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.',
          _controller.supportsBrowserHfp
              ? '网页无法自行连接 HFP。请先在蓝牙设置中连接耳机、允许麦克风权限、刷新页面，再点击选择 HFP 麦克风。iPhone Safari 可能只提供 iPhone 麦克风。'
              : isIOS
              ? 'iOS 只能选择当前已连接的 HFP 麦克风。请先在蓝牙设置中连接 HM-D001，然后返回并点击“查找 HFP”。'
              : '请先在蓝牙设置中配对耳机或 HFP 设备，然后返回并点击“查找 HFP”。',
        ),
      );
      return null;
    }
    final selected = await _showDevicePicker<HfpAudioDevice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _controller.supportsBrowserHfp
                    ? context.tr('Chọn mic Bluetooth', '选择蓝牙麦克风')
                    : context.tr('Chọn thiết bị HFP', '选择 HFP 设备'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  _controller.supportsBrowserHfp
                      ? 'Chỉ các mic Bluetooth mà trình duyệt công bố mới xuất hiện. Thiết bị đã chọn được ưu tiên.'
                      : isIOS
                      ? 'iOS chỉ hiển thị các mic HFP đang khả dụng trong AVAudioSession. Thiết bị đang dùng được ưu tiên.'
                      : 'Android chỉ cho ứng dụng dùng HFP đã ghép đôi. Thiết bị đang kết nối được ưu tiên.',
                  _controller.supportsBrowserHfp
                      ? '这里只显示浏览器公开的蓝牙麦克风；已选择的设备优先。'
                      : isIOS
                      ? 'iOS 仅显示 AVAudioSession 中可用的 HFP 麦克风；当前设备优先。'
                      : 'Android 仅允许应用使用已配对的 HFP；已连接设备优先显示。',
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
                            _isLikelyMicrophone(devices[index - 1]) !=
                                _isLikelyMicrophone(device))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              _isLikelyMicrophone(device)
                                  ? context.tr(
                                      'Micro HOMI phù hợp',
                                      '符合条件的 HOMI 麦克风',
                                    )
                                  : context.tr('Micro khác', '其他麦克风'),
                            ),
                          ),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: device.isConnected
                                ? Theme.of(
                                    itemContext,
                                  ).colorScheme.primaryContainer
                                : Theme.of(
                                    itemContext,
                                  ).colorScheme.surfaceContainer,
                            child: Icon(
                              Icons.headset_mic_rounded,
                              color: device.isConnected
                                  ? Theme.of(itemContext).colorScheme.primary
                                  : Theme.of(
                                      itemContext,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            localizedDeviceName(
                              device.name,
                              _controller.displayLanguage,
                              deviceId: device.id,
                            ),
                          ),
                          subtitle: Text(
                            device.isConnected
                                ? _controller.supportsBrowserHfp
                                      ? context.tr(
                                          'Mic đang được chọn cho Web',
                                          '已选为网页麦克风',
                                        )
                                      : context.tr(
                                          'HFP đang kết nối',
                                          'HFP 已连接',
                                        )
                                : context.tr(
                                    _controller.supportsBrowserHfp
                                        ? 'Chạm để dùng mic này'
                                        : 'Đã ghép đôi • chạm để mở kết nối',
                                    _controller.supportsBrowserHfp
                                        ? '点击使用此麦克风'
                                        : '已配对 • 点击连接',
                                  ),
                          ),
                          trailing: device.isConnected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: Theme.of(
                                    itemContext,
                                  ).colorScheme.primary,
                                )
                              : const Icon(Icons.chevron_right_rounded),
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
    var confirmHomiAssociation = false;
    if (_controller.requiresHomiMicrophoneConfirmation(selected)) {
      final associationBleId = _controller.aiv0BleStatus.deviceId
          ?.trim()
          .toUpperCase();
      final microphoneName = localizedDeviceName(
        selected.name,
        _controller.displayLanguage,
        deviceId: selected.id,
      );
      final confirmed = await _showOwnedDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Đây là micro của HOMI?', '这是 HOMI 的麦克风吗？')),
          content: Text(
            context.tr(
              'Micro "$microphoneName" có đi cùng thiết bị HOMI của bạn không? Nếu chưa chắc, hãy chọn "Chỉ dùng micro".',
              '麦克风"$microphoneName"是您的 HOMI 设备配套的吗？如果不确定，请选择"仅使用麦克风"。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.tr('Chỉ dùng micro', '仅使用麦克风')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.tr('Đúng, dùng với HOMI', '是的，连接 HOMI')),
            ),
          ],
        ),
      );
      if (!_isCurrent(generation) || !context.mounted || confirmed == null) {
        return null;
      }
      if (confirmed &&
          (associationBleId == null ||
              associationBleId.isEmpty ||
              !_controller.aiv0BleStatus.isConnected ||
              _controller.aiv0BleStatus.deviceId?.trim().toUpperCase() !=
                  associationBleId)) {
        onMessage?.call(
          context.tr(
            'Thiết bị chưa khả dụng. Hãy kiểm tra kết nối Bluetooth rồi thử lại.',
            '设备暂不可用。请检查蓝牙连接后重试。',
          ),
        );
        return const DeviceConnectionResult(DeviceConnectionOutcome.unavailable);
      }
      confirmHomiAssociation = confirmed;
    }
    final result = await _controller.connectHfpDevice(
      selected,
      confirmHomiAssociation: confirmHomiAssociation,
    );
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

  Future<T?> _showOwnedDialog<T extends Object>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(context: context, builder: builder);
    _devicePickerRoute = route;
    try {
      return await navigator.push<T>(route);
    } finally {
      if (identical(_devicePickerRoute, route)) _devicePickerRoute = null;
    }
  }

  Future<void> _showHfpMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await _showOwnedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Đã hiểu', '知道了')),
          ),
        ],
      ),
    );
  }

  bool _isLikelyMicrophone(HfpAudioDevice device) =>
      selectLikelyHomiHfpDevice(<HfpAudioDevice>[
        device,
      ], bleDeviceName: _controller.aiv0BleStatus.deviceName) !=
      null;

  List<HfpAudioDevice> _prioritizeMicrophones(List<HfpAudioDevice> devices) =>
      List<HfpAudioDevice>.of(devices)..sort((a, b) {
        if (_isLikelyMicrophone(a) != _isLikelyMicrophone(b)) {
          return _isLikelyMicrophone(a) ? -1 : 1;
        }
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return a.name.compareTo(b.name);
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
      debugPrint('HFP picker cancellation failed: $error');
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
