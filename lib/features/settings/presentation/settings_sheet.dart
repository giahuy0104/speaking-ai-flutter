import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../config/app_config.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/device/aiv0_ble_control.dart';
import '../../../core/privacy/parental_gate.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/application/conversation_settings_port.dart';
import '../../listening/domain/listening_catalog.dart';

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({
    required this.controller,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.stopMediaWhenBackgrounded,
    this.onStopMediaWhenBackgroundedChanged,
    super.key,
  });

  final ConversationSettingsPort controller;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final bool? stopMediaWhenBackgrounded;
  final ValueChanged<bool>? onStopMediaWhenBackgroundedChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final h20State = controller.h20ConnectionState();
        return DisplayLanguageScope(
          language: controller.displayLanguage,
          child: Builder(
            builder: (context) => SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? const <Color>[
                            AppColors.darkCanvas,
                            AppColors.darkSurface,
                          ]
                        : const <Color>[AppColors.mintWash, AppColors.mintSoft],
                  ),
                ),
                child: SingleChildScrollView(
                  key: const Key('settings-scroll-view'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              context.tr('Thiết lập phụ huynh', '家长设置'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          _SettingsRaisedIcon(
                            icon: Icons.close_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: context.tr('Đóng', '关闭'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _AppearanceSelector(
                        value: themeMode,
                        onChanged: onThemeModeChanged,
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(
                        label: context.tr('Ngôn ngữ hiển thị', '显示语言'),
                        icon: Icons.language_rounded,
                      ),
                      const SizedBox(height: 10),
                      if (MediaQuery.textScalerOf(context).scale(1) >= 1.5)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: DisplayLanguage.values
                              .map(
                                (language) => ChoiceChip(
                                  label: Text(language.nativeLabel),
                                  selected:
                                      controller.displayLanguage == language,
                                  onSelected: (_) =>
                                      controller.setDisplayLanguage(language),
                                ),
                              )
                              .toList(growable: false),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<DisplayLanguage>(
                            showSelectedIcon: false,
                            segments: DisplayLanguage.values
                                .map(
                                  (language) => ButtonSegment<DisplayLanguage>(
                                    value: language,
                                    label: Text(language.nativeLabel),
                                  ),
                                )
                                .toList(growable: false),
                            selected: <DisplayLanguage>{
                              controller.displayLanguage,
                            },
                            onSelectionChanged: (selection) =>
                                controller.setDisplayLanguage(selection.first),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _SectionLabel(
                        label: context.tr('Nhóm tuổi của trẻ', '孩子年龄组'),
                        icon: Icons.child_care_rounded,
                      ),
                      const SizedBox(height: 10),
                      _ChildAgeGroupSelector(
                        childAge: controller.childAge,
                        enabled:
                            !controller.isBusy && onChildAgeChanged != null,
                        onChanged: onChildAgeChanged,
                      ),
                      const SizedBox(height: 12),
                      _CompactSettingsSection(
                        key: const Key('settings-audio-h20-section'),
                        icon: Icons.headset_mic_rounded,
                        title: context.tr('Âm thanh & HOMI', '音频与 HOMI'),
                        summary: h20State.isH20Ready
                            ? context.tr('Thiết bị đã sẵn sàng', '设备已就绪')
                            : context.tr(
                                'Thông tin và kết nối thiết bị',
                                '设备信息与连接',
                              ),
                        children: <Widget>[
                          HomiSurface(
                            key: const Key('settings-h20-group'),
                            padding: const EdgeInsets.all(12),
                            color: Theme.of(context).colorScheme.surface,
                            borderColor: Theme.of(
                              context,
                            ).colorScheme.outlineVariant,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    2,
                                    4,
                                    10,
                                  ),
                                  child: Text(
                                    context.tr(
                                      'Thông tin thiết bị HOMI',
                                      'HOMI 设备信息',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                _SettingsDeviceTile(
                                  icon: Icons.battery_full_rounded,
                                  title: context.tr('Pin thiết bị', '设备电量'),
                                  trailing: Text(
                                    controller.aiv0BleStatus.isConnected &&
                                            controller
                                                    .aiv0BleStatus
                                                    .batteryPercent !=
                                                null
                                        ? '${controller.aiv0BleStatus.batteryPercent}%'
                                        : context.tr('Chưa đọc pin', '尚未读取电量'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _Aiv0BleControlCard(
                                  status: controller.aiv0BleStatus,
                                  disabled: controller.isBusy,
                                  onScan: () => _scanAndConnectAiv0(context),
                                  onDisconnect: controller.disconnectAiv0Device,
                                ),
                                const SizedBox(height: 8),
                                _HfpStatusCard(
                                  status: controller.hfpAudioStatus,
                                  selected: controller.usesHfpInput,
                                  disabled: controller.isBusy,
                                  onFind: () => _findAndConnectHfp(context),
                                  onDisconnect: controller.disconnectHfpDevice,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      _SectionLabel(
                        label: context.tr('Dữ liệu và quyền riêng tư', '数据与隐私'),
                        icon: Icons.shield_outlined,
                      ),
                      const SizedBox(height: 10),
                      _SettingsRaisedPanel(
                        child: HomiSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          color: Colors.transparent,
                          child: Column(
                            children: <Widget>[
                              _SettingsActionTile(
                                key: const Key('settings-privacy-policy'),
                                icon: Icons.privacy_tip_outlined,
                                title: context.tr(
                                  'Chính sách quyền riêng tư',
                                  '隐私政策',
                                ),
                                detail: context.tr(
                                  'Xem dữ liệu được thu thập, nhà cung cấp AI, thời hạn lưu và cách yêu cầu xóa.',
                                  '查看所收集的数据、AI 服务商、保存期限和删除方式。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  config?.privacyPolicyUri,
                                  context.tr(
                                    'Chính sách quyền riêng tư',
                                    '隐私政策',
                                  ),
                                ),
                              ),
                              const _SettingsDivider(),
                              _SettingsActionTile(
                                key: const Key('settings-terms'),
                                icon: Icons.description_outlined,
                                title: context.tr('Điều khoản sử dụng', '使用条款'),
                                detail: context.tr(
                                  'Điều khoản dành cho phụ huynh và người giám hộ.',
                                  '面向家长和监护人的使用条款。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  config?.termsUri,
                                  context.tr('Điều khoản sử dụng', '使用条款'),
                                ),
                              ),
                              const _SettingsDivider(),
                              _SettingsActionTile(
                                key: const Key('settings-support'),
                                icon: Icons.support_agent_rounded,
                                title: context.tr('Hỗ trợ', '支持'),
                                detail: context.tr(
                                  'Liên hệ HOMI về quyền riêng tư, dữ liệu hoặc lỗi ứng dụng.',
                                  '就隐私、数据或应用问题联系 HOMI。',
                                ),
                                onTap: () => _openParentLink(
                                  context,
                                  config?.supportUri,
                                  context.tr('Hỗ trợ', '支持'),
                                ),
                              ),
                              if (privacyConsentGranted &&
                                  !voiceAccessEnabled &&
                                  onRequestVoiceAccess != null) ...<Widget>[
                                const _SettingsDivider(),
                                _SettingsActionTile(
                                  key: const Key('settings-enable-voice'),
                                  icon: Icons.mic_rounded,
                                  title: context.tr('Cho phép micro', '允许麦克风'),
                                  detail: context.tr(
                                    'Mở hộp thoại quyền hệ thống. Audio chỉ được gửi sau khi có cả chấp thuận phụ huynh và quyền micro.',
                                    '打开系统权限对话框。只有家长同意并授予麦克风权限后才会发送音频。',
                                  ),
                                  onTap: onRequestVoiceAccess!,
                                ),
                              ],
                              if (!privacyConsentGranted &&
                                  onManagePrivacyConsent != null) ...<Widget>[
                                const _SettingsDivider(),
                                _SettingsActionTile(
                                  key: const Key(
                                    'settings-manage-privacy-consent',
                                  ),
                                  icon: Icons.verified_user_outlined,
                                  title: context.tr(
                                    'Thiết lập tính năng giọng nói',
                                    '设置语音功能',
                                  ),
                                  detail: context.tr(
                                    'Quay lại màn hình dành cho phụ huynh để đọc thông tin và chọn đồng ý.',
                                    '返回家长设置页面，阅读说明并选择是否同意。',
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    onManagePrivacyConsent!();
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openParentLink(
    BuildContext context,
    Uri? uri,
    String label,
  ) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !context.mounted) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
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

class _SettingsRaisedPanel extends StatelessWidget {
  const _SettingsRaisedPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HomiUi.surfaceRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[
                  AppColors.darkSurfaceRaised,
                  AppColors.darkSurface,
                ]
              : const <Color>[AppColors.surface, AppColors.mintWash],
        ),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primaryNavy.withValues(
              alpha: isDark ? 0.24 : 0.09,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SettingsRaisedIcon extends StatelessWidget {
  const _SettingsRaisedIcon({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.foregroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = onPressed == null ? 40.0 : 48.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[
                  AppColors.darkSurfaceStrong,
                  AppColors.darkSurface,
                ]
              : const <Color>[Colors.white, AppColors.mintSoft],
        ),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.primaryNavy.withValues(
              alpha: isDark ? 0.18 : 0.10,
            ),
            blurRadius: 9,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: onPressed == null
          ? Icon(
              icon,
              size: 22,
              color: foregroundColor ?? Theme.of(context).colorScheme.primary,
            )
          : IconButton(
              onPressed: onPressed,
              tooltip: tooltip,
              icon: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
    );
  }
}

class _SettingsDeviceTile extends StatelessWidget {
  const _SettingsDeviceTile({
    required this.icon,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : AppColors.mintBorder,
        ),
      ),
      child: Row(
        children: <Widget>[
          _SettingsRaisedIcon(icon: icon, foregroundColor: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          trailing,
        ],
      ),
    );
  }
}

class _CompactSettingsSection extends StatelessWidget {
  const _CompactSettingsSection({
    required this.icon,
    required this.title,
    required this.summary,
    required this.children,
    super.key,
  });

  final IconData icon;
  final String title;
  final String summary;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SettingsRaisedPanel(
      child: HomiSurface(
        padding: EdgeInsets.zero,
        color: Colors.transparent,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: _SettingsRaisedIcon(icon: icon),
            title: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            maintainState: true,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 66,
      endIndent: 10,
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.7),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(HomiUi.controlRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HomiUi.controlRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
          child: Row(
            children: <Widget>[
              HomiIconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildAgeGroupSelector extends StatelessWidget {
  const _ChildAgeGroupSelector({
    required this.childAge,
    required this.enabled,
    required this.onChanged,
  });

  final int childAge;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('settings-child-age-group'),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        children: <Widget>[
          for (final catalog in listeningCatalogs)
            ChoiceChip(
              key: ValueKey('settings-age-${catalog.id}'),
              showCheckmark: true,
              elevation: 0,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              label: Text(
                context.tr(
                  '${catalog.startAge}–${catalog.endAge} tuổi',
                  '${catalog.startAge}–${catalog.endAge} 岁',
                ),
              ),
              selected:
                  childAge >= catalog.startAge && childAge <= catalog.endAge,
              onSelected: enabled
                  ? (_) => onChanged?.call(catalog.startAge)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _AppearanceSelector extends StatefulWidget {
  const _AppearanceSelector({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  State<_AppearanceSelector> createState() => _AppearanceSelectorState();
}

class _AppearanceSelectorState extends State<_AppearanceSelector> {
  late ThemeMode _value = widget.value;

  @override
  void didUpdateWidget(covariant _AppearanceSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  void _select(ThemeMode mode) {
    if (mode == _value) {
      return;
    }
    setState(() => _value = mode);
    widget.onChanged?.call(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = <({ThemeMode mode, IconData icon, String label})>[
      (
        mode: ThemeMode.system,
        icon: Icons.brightness_auto_rounded,
        label: context.tr('Hệ thống', '跟随系统'),
      ),
      (
        mode: ThemeMode.light,
        icon: Icons.light_mode_rounded,
        label: context.tr('Sáng', '浅色'),
      ),
      (
        mode: ThemeMode.dark,
        icon: Icons.dark_mode_rounded,
        label: context.tr('Tối', '深色'),
      ),
    ];
    final selectedLabel = options
        .firstWhere((option) => option.mode == _value)
        .label;

    return Padding(
      key: const Key('appearance-settings-card'),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (MediaQuery.textScalerOf(context).scale(1) >= 1.4)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _SettingsRaisedIcon(icon: Icons.palette_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('Giao diện', '外观'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  selectedLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          else
            Row(
              children: <Widget>[
                const _SettingsRaisedIcon(icon: Icons.palette_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('Giao diện', '外观'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  selectedLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (option) => FilterChip(
                    key: ValueKey<String>('theme-mode-${option.mode.name}'),
                    avatar: Icon(option.icon, size: 18),
                    label: Text(option.label),
                    selected: _value == option.mode,
                    showCheckmark: false,
                    elevation: 0,
                    side: BorderSide(color: colorScheme.outlineVariant),
                    onSelected: widget.onChanged == null
                        ? null
                        : (_) => _select(option.mode),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _SettingsRaisedIcon(icon: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _Aiv0BleControlCard extends StatelessWidget {
  const _Aiv0BleControlCard({
    required this.status,
    required this.disabled,
    required this.onScan,
    required this.onDisconnect,
  });

  final Aiv0BleStatus status;
  final bool disabled;
  final VoidCallback onScan;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final connected = status.isConnected;
    final busy =
        status.phase == Aiv0BlePhase.scanning ||
        status.phase == Aiv0BlePhase.connecting ||
        status.phase == Aiv0BlePhase.reconnecting;
    return _SettingsDeviceTile(
      icon: connected
          ? Icons.bluetooth_connected_rounded
          : Icons.bluetooth_rounded,
      foregroundColor: connected ? AppColors.success : null,
      title: context.tr('Kết nối HM-D001 (BLE)', '连接 HM-D001 (BLE)'),
      subtitle: busy
          ? context.tr('Đang kết nối…', '正在连接…')
          : connected
          ? context.tr('Đã kết nối', '已连接')
          : context.tr('Chưa kết nối', '尚未连接'),
      trailing: busy
          ? const SizedBox(
              width: 48,
              child: HomiWaveform(active: true, width: 42, height: 22),
            )
          : IconButton(
              tooltip: connected
                  ? context.tr('Ngắt kết nối BLE', '断开 BLE 连接')
                  : context.tr('Quét và kết nối', '扫描并连接'),
              onPressed: disabled || status.phase == Aiv0BlePhase.disabled
                  ? null
                  : connected
                  ? () => onDisconnect()
                  : onScan,
              icon: Icon(
                connected ? Icons.link_off_rounded : Icons.search_rounded,
              ),
            ),
    );
  }
}

class _HfpStatusCard extends StatelessWidget {
  const _HfpStatusCard({
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
    final name = status.deviceName?.trim();
    return _SettingsDeviceTile(
      icon: Icons.mic_rounded,
      foregroundColor: selected ? AppColors.success : null,
      title: name == null || name.isEmpty
          ? context.tr('Mic HOMI', 'HOMI 麦克风')
          : name,
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
