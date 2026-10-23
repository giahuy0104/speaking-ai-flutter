import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../l10n/display_language.dart';
import '../../../features/conversation/application/conversation_settings_port.dart';
import '../../../core/device/aivo_control_dispatcher.dart';
import '../screen/homi_control_diagnostics_screen.dart';
import 'settings_divider.dart';
import 'settings_status_tile.dart';
import 'settings_ble_diagnostics_card.dart';
import 'settings_hfp_details_card.dart';

class SettingsIosDeviceDetails extends StatelessWidget {
  const SettingsIosDeviceDetails({required this.controller, super.key});
  final ConversationSettingsPort controller;
  @override
  Widget build(BuildContext context) {
    final deviceControls = AivoControlScope.maybeOf(context);
    final homiState = controller.homiConnectionState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsStatusTile(
          icon: Icons.mic_rounded,
          title: context.trKnown(controller.inputLabel),
          detail: context.tr(
            controller.usesHfpInput
                ? 'Mic HM-D001 qua HFP • Apple Speech ưu tiên'
                : 'Mic iPhone/iPad • Apple Speech ưu tiên',
            controller.usesHfpInput
                ? 'HM-D001 HFP 麦克风 • 优先使用 Apple Speech'
                : 'iPhone/iPad 麦克风 • 优先使用 Apple Speech',
          ),
          trailing: context.tr('Đang dùng', '使用中'),
          stateColor: AppColors.success,
        ),
        const SizedBox(height: 10),
        HomiSurface(
          key: const Key('settings-hm-d001-group'),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            children: <Widget>[
              HomiSectionHeading(
                icon: Icons.headset_mic_rounded,
                title: context.tr('Kết nối HOMI', '连接 HOMI'),
                trailing: HomiStatusPill(
                  label: homiState.isHomiReady
                      ? context.tr('Sẵn sàng', '已就绪')
                      : context.tr('Chưa sẵn sàng', '未就绪'),
                  color: homiState.isHomiReady
                      ? AppColors.success
                      : AppColors.coral,
                  icon: homiState.isHomiReady
                      ? Icons.check_rounded
                      : Icons.error_outline_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr(
                    homiState.isHomiReady
                        ? 'Âm thanh và nút MAIN đã kết nối.'
                        : 'Hoàn tất cả âm thanh HFP và BLE để dùng nút MAIN.',
                    homiState.isHomiReady
                        ? '音频与 MAIN 按钮均已连接。'
                        : '请完成 HFP 音频与 BLE 连接以使用 MAIN 按钮。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SettingsBleDiagnosticsCard(
                embedded: true,
                status: controller.aiv0BleStatus,
                events: controller.aiv0ButtonEventLog,
                mainDispatchStatus: controller.aiv0MainDispatchStatus,
                mainDispatchAt: controller.aiv0MainDispatchAt,
                disabled: controller.isBusy,
                onScan: () => _scanAndConnectAiv0(context),
                onDisconnect: controller.disconnectAiv0Device,
              ),
              if (deviceControls != null)
                OutlinedButton.icon(
                  key: const Key('open-hm-d001-control-diagnostics'),
                  icon: const Icon(Icons.settings_remote_outlined),
                  label: const Text('Điều khiển thiết bị HOMI'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => HomiControlDiagnosticsScreen(
                        controller: controller,
                        controls: deviceControls,
                      ),
                    ),
                  ),
                ),
              const SettingsDivider(),
              SettingsHfpDetailsCard(
                embedded: true,
                status: controller.hfpAudioStatus,
                browserManaged: controller.supportsBrowserHfp,
                selected: controller.usesHfpInput,
                disabled: controller.isBusy,
                onFind: () => _findAndConnectHfp(context),
                onDisconnect: controller.disconnectHfpDevice,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _scanAndConnectAiv0(BuildContext context) async {
    try {
      final devices = await controller.scanAiv0Devices();
      if (!context.mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không tìm thấy HM-D001. Hãy bật thiết bị và thử lại.',
                '未找到 HM-D001。请开启设备后重试。',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<Aiv0BleDevice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Chọn thiết bị BLE Control', '选择 BLE 控制设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'APK sẽ xác nhận service 9E3B0001. Âm thanh không truyền qua BLE.',
                    'APK 将验证 9E3B0001 服务。音频不通过 BLE 传输。',
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
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.bluetooth_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(device.name),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !context.mounted) return;
      await controller.connectAiv0Device(selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Đã kết nối BLE Control. MAIN Raw Hex đã sẵn sàng.',
                'BLE 控制已连接。MAIN Raw Hex 已可使用。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // Kept only for release builds that intentionally re-enable legacy
  // FF12/FF13/FF14 audio through ENABLE_LEGACY_BLE_AUDIO.
  // ignore: unused_element
  Future<void> _scanAndConnect(BuildContext context) async {
    try {
      final devices = await controller.scanInnotrikDevices();
      if (!context.mounted) {
        return;
      }
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không tìm thấy thiết bị. Hãy bật INNOTRIK và thử lại.',
                '未找到设备。请打开 INNOTRIK 后重试。',
              ),
            ),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<BluetoothAudioDevice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  context.tr('Chọn thiết bị INNOTRIK', '选择 INNOTRIK 设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    'Thiết bị đúng giao thức được ưu tiên ở đầu danh sách.',
                    '符合协议的设备会优先显示在列表顶部。',
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
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: device.isLikelyInnotrik
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : Theme.of(context).colorScheme.surfaceContainer,
                          child: Icon(
                            device.isLikelyInnotrik
                                ? Icons.bluetooth_connected_rounded
                                : Icons.bluetooth_rounded,
                            color: device.isLikelyInnotrik
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(device.displayName),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
                        trailing: device.isLikelyInnotrik
                            ? const Icon(
                                Icons.verified_rounded,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !context.mounted) {
        return;
      }
      await controller.connectInnotrikDevice(selected);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Đã kết nối. Hãy nói thử để kiểm tra Mic INNOTRIK.',
                '已连接。请说话测试 INNOTRIK 麦克风。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // ignore: unused_element
  Future<void> _testInnotrik(BuildContext context) async {
    try {
      await controller.testInnotrikMicrophone();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Kiểm tra hoàn tất. Nếu nghe đúng giọng vừa nói, decoder hoạt động tốt.',
                '测试完成。如果能听到刚才的声音，说明解码器工作正常。',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _findAndConnectHfp(BuildContext context) async {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    try {
      final devices = await controller.findHfpDevices();
      if (!context.mounted) {
        return;
      }
      if (devices.isEmpty) {
        await _showHfpMessage(
          context,
          title: controller.supportsBrowserHfp
              ? context.tr('Chưa thấy mic Bluetooth trên Web', '网页中未发现蓝牙麦克风')
              : context.tr('Chưa có thiết bị HFP', '暂无 HFP 设备'),
          message: context.tr(
            controller.supportsBrowserHfp
                ? 'Web không thể tự kết nối HFP. Hãy kết nối tai nghe trong Cài đặt Bluetooth, cho phép quyền micro, tải lại trang rồi bấm Chọn mic HFP. Safari trên iPhone có thể chỉ cung cấp mic iPhone.'
                : isIOS
                ? 'iOS chỉ cho ứng dụng chọn mic HFP đang kết nối. Hãy kết nối HM-D001 trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.'
                : 'Hãy ghép đôi tai nghe hoặc thiết bị HFP trong Cài đặt Bluetooth, sau đó quay lại bấm Tìm HFP.',
            controller.supportsBrowserHfp
                ? '网页无法自行连接 HFP。请先在蓝牙设置中连接耳机、允许麦克风权限、刷新页面，再点击选择 HFP 麦克风。iPhone Safari 可能只提供 iPhone 麦克风。'
                : isIOS
                ? 'iOS 只能选择当前已连接的 HFP 麦克风。请先在蓝牙设置中连接 HM-D001，然后返回并点击“查找 HFP”。'
                : '请先在蓝牙设置中配对耳机或 HFP 设备，然后返回并点击“查找 HFP”。',
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<HfpAudioDevice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  controller.supportsBrowserHfp
                      ? context.tr('Chọn mic Bluetooth', '选择蓝牙麦克风')
                      : context.tr('Chọn thiết bị HFP', '选择 HFP 设备'),
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr(
                    controller.supportsBrowserHfp
                        ? 'Chỉ các mic Bluetooth mà trình duyệt công bố mới xuất hiện. Thiết bị đã chọn được ưu tiên.'
                        : isIOS
                        ? 'iOS chỉ hiển thị các mic HFP đang khả dụng trong AVAudioSession. Thiết bị đang dùng được ưu tiên.'
                        : 'Android chỉ cho ứng dụng dùng HFP đã ghép đôi. Thiết bị đang kết nối được ưu tiên.',
                    controller.supportsBrowserHfp
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
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: device.isConnected
                              ? Color.alphaBlend(
                                  AppColors.success.withValues(alpha: 0.14),
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                )
                              : Theme.of(context).colorScheme.surfaceContainer,
                          child: Icon(
                            Icons.headset_mic_rounded,
                            color: device.isConnected
                                ? AppColors.success
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(device.displayName),
                        subtitle: Text(
                          device.isConnected
                              ? controller.supportsBrowserHfp
                                    ? context.tr(
                                        'Mic đang được chọn cho Web',
                                        '已选为网页麦克风',
                                      )
                                    : context.tr('HFP đang kết nối', 'HFP 已连接')
                              : context.tr(
                                  controller.supportsBrowserHfp
                                      ? 'Chạm để dùng mic này'
                                      : 'Đã ghép đôi • chạm để mở kết nối',
                                  controller.supportsBrowserHfp
                                      ? '点击使用此麦克风'
                                      : '已配对 • 点击连接',
                                ),
                        ),
                        trailing: device.isConnected
                            ? const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.success,
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !context.mounted) {
        return;
      }
      await controller.connectHfpDevice(selected);
    } catch (error) {
      if (context.mounted) {
        await _showHfpMessage(
          context,
          title: context.tr('Chưa thể dùng HFP', '暂时无法使用 HFP'),
          message: error.toString(),
        );
      }
    }
  }

  Future<void> _showHfpMessage(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
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
}
