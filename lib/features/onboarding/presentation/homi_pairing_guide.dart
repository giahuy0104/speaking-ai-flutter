import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';

/// What the parent chose in the pairing guide.
enum HomiPairingGuideAction { openSettings, alreadyPaired }

/// System Bluetooth pairing guide shown before the first connection.
///
/// Both platforms pair HM-D001 in system settings: iOS apps cannot pair a
/// Classic device, and an in-app Android bond left BLE MAIN undiscoverable
/// until the Bluetooth stack restarted. The caller opens settings and checks
/// the connection again when the app resumes.
Future<HomiPairingGuideAction?> showHomiPairingGuide(BuildContext context) =>
    showModalBottomSheet<HomiPairingGuideAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => const HomiPairingGuide(),
    );

class HomiPairingGuide extends StatelessWidget {
  const HomiPairingGuide({super.key});

  static const deviceName = 'HM-D001';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final steps = ios
        ? <_GuideStep>[
            _GuideStep(
              context.tr('Bật HOMI và đặt gần điện thoại.', '开启 HOMI 并放在手机附近。'),
            ),
            _GuideStep(
              context.tr(
                'Mở app Cài đặt của iPhone, chọn Bluetooth.',
                '打开 iPhone 的“设置”，选择“蓝牙”。',
              ),
            ),
            _GuideStep(
              context.tr(
                'Trong "Thiết bị khác", chọn $deviceName.',
                '在“其他设备”中选择 $deviceName。',
              ),
              preview: _SettingsPreview(
                ios: true,
                sectionLabel: context.tr('THIẾT BỊ KHÁC', '其他设备'),
              ),
            ),
            _GuideStep(
              context.tr(
                'Khi $deviceName hiện "Đã kết nối", quay lại HOMI. App sẽ tự kết nối.',
                '当 $deviceName 显示“已连接”后返回 HOMI，应用会自动连接。',
              ),
            ),
          ]
        : <_GuideStep>[
            _GuideStep(
              context.tr('Bật HOMI và đặt gần điện thoại.', '开启 HOMI 并放在手机附近。'),
            ),
            _GuideStep(
              context.tr(
                'Bấm "Mở Cài đặt Bluetooth", rồi chọn "Ghép nối thiết bị mới".',
                '点击“打开蓝牙设置”，然后选择“配对新设备”。',
              ),
            ),
            _GuideStep(
              context.tr(
                'Chọn $deviceName. Nếu được hỏi, bấm "Ghép nối".',
                '选择 $deviceName。如有提示，请点击“配对”。',
              ),
              preview: _SettingsPreview(
                ios: false,
                sectionLabel: context.tr('Thiết bị khả dụng', '可用设备'),
              ),
            ),
            _GuideStep(
              context.tr(
                'Bấm Quay lại để về HOMI. App sẽ tự kết nối.',
                '点击返回回到 HOMI，应用会自动连接。',
              ),
            ),
          ];

    return SingleChildScrollView(
      key: const Key('homi-pairing-guide'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.tr('Ghép đôi HOMI', '配对 HOMI'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'Làm một lần trong Cài đặt Bluetooth, khoảng 1 phút.',
              '只需在蓝牙设置中操作一次，约 1 分钟。',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            _StepRow(number: i + 1, step: steps[i]),
          const _TroubleshootingTile(),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('homi-pairing-open-settings'),
            onPressed: () =>
                Navigator.of(context).pop(HomiPairingGuideAction.openSettings),
            icon: const Icon(Icons.settings_bluetooth_rounded),
            label: Text(
              ios
                  ? context.tr('Mở Cài đặt', '打开设置')
                  : context.tr('Mở Cài đặt Bluetooth', '打开蓝牙设置'),
            ),
          ),
          if (ios) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Nếu Cài đặt mở trang của HOMI, bấm "‹ Cài đặt" ở góc trên để về trang chính rồi chọn Bluetooth.',
                '如果打开的是 HOMI 的设置页，请点击左上角“‹ 设置”返回，再选择“蓝牙”。',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            key: const Key('homi-pairing-already-paired'),
            onPressed: () =>
                Navigator.of(context).pop(HomiPairingGuideAction.alreadyPaired),
            child: Text(
              context.tr('Tôi đã ghép đôi, kết nối ngay', '我已配对，立即连接'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep {
  const _GuideStep(this.text, {this.preview});
  final String text;
  final Widget? preview;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.step});
  final int number;
  final _GuideStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 13,
            backgroundColor: isDark
                ? theme.colorScheme.primary
                : AppColors.primaryNavy,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isDark ? theme.colorScheme.onPrimary : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(step.text, style: theme.textTheme.bodyLarge),
                ),
                if (step.preview != null) ...<Widget>[
                  const SizedBox(height: 8),
                  step.preview!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small, platform-neutral sketch of the system device list that points
/// at HM-D001. Labels differ between phone makers, so only the target name
/// is emphasised.
class _SettingsPreview extends StatelessWidget {
  const _SettingsPreview({required this.ios, required this.sectionLabel});
  final bool ios;
  final String sectionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final highlight = isDark ? AppColors.darkSurfaceStrong : AppColors.mintSoft;
    final border = isDark ? AppColors.darkMint : AppColors.mint;
    Widget row(String name, {bool target = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: target
          ? BoxDecoration(
              color: highlight,
              border: Border.all(color: border, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: <Widget>[
          if (!ios) ...<Widget>[
            Icon(
              Icons.headphones_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: target ? FontWeight.w800 : FontWeight.w400,
                color: target ? null : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (target) Icon(Icons.touch_app_rounded, size: 18, color: border),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceRaised
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
            child: Text(
              sectionLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          row(context.tr('Laptop', '笔记本电脑')),
          row(HomiPairingGuide.deviceName, target: true),
          row(context.tr('Loa Bluetooth', '蓝牙音箱')),
        ],
      ),
    );
  }
}

class _TroubleshootingTile extends StatelessWidget {
  const _TroubleshootingTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tips = <String>[
      context.tr(
        'Kiểm tra HOMI đã bật và ở trong khoảng 1 mét.',
        '确认 HOMI 已开启并在 1 米范围内。',
      ),
      context.tr(
        'Ngắt HOMI khỏi điện thoại hoặc máy tính khác.',
        '断开 HOMI 与其他手机或电脑的连接。',
      ),
      context.tr(
        'Đã ghép đôi trước đó mà không kết nối được: chọn "Quên thiết bị" $_name rồi ghép đôi lại.',
        '之前已配对但无法连接：选择“忘记此设备” $_name 后重新配对。',
      ),
    ];
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('homi-pairing-troubleshooting'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.help_outline_rounded),
        title: Text(
          context.tr('Không thấy $_name?', '找不到 $_name？'),
          style: theme.textTheme.titleSmall,
        ),
        children: <Widget>[
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('•  '),
                  Expanded(child: Text(tip, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const _name = HomiPairingGuide.deviceName;
}
