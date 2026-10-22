import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';

/// Which system Bluetooth step the parent must do in settings.
///
/// HM-D001 stops advertising BLE MAIN while its Classic audio (HFP/A2DP) is
/// connected, so setup runs in this order: connect MAIN over BLE first, then
/// turn HOMI audio on.
enum HomiAudioGuide {
  /// Audio is connected before MAIN: pause it so MAIN can be found.
  pauseAudio,

  /// MAIN is connected: pair HOMI or turn its audio back on.
  enableAudio,
}

/// What the parent chose in the guide.
enum HomiGuideAction { openSettings, checkAgain }

Future<HomiGuideAction?> showHomiAudioGuide(
  BuildContext context,
  HomiAudioGuide guide,
) => showModalBottomSheet<HomiGuideAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => HomiAudioGuideSheet(guide: guide),
);

class HomiAudioGuideSheet extends StatelessWidget {
  const HomiAudioGuideSheet({required this.guide, super.key});

  final HomiAudioGuide guide;

  static const deviceName = 'HM-D001';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final pause = guide == HomiAudioGuide.pauseAudio;
    final title = pause
        ? context.tr('Tạm tắt âm thanh HOMI', '暂时关闭 HOMI 音频')
        : context.tr('Bật âm thanh HOMI', '开启 HOMI 音频');
    final subtitle = pause
        ? context.tr(
            'Nút MAIN chỉ kết nối được khi âm thanh HOMI chưa bật. Tạm tắt âm thanh, kết nối MAIN xong app sẽ hướng dẫn bật lại.',
            '只有在 HOMI 音频未开启时才能连接 MAIN 按钮。请暂时关闭音频，连接 MAIN 后应用会引导您重新开启。',
          )
        : context.tr(
            'Nút MAIN đã kết nối. Bật âm thanh để dùng micro và loa HOMI.',
            'MAIN 按钮已连接。开启音频即可使用 HOMI 的麦克风和扬声器。',
          );
    final steps = switch ((pause, ios)) {
      (true, false) => <_GuideStep>[
        _GuideStep(context.tr('Bấm "Mở Cài đặt Bluetooth".', '点击“打开蓝牙设置”。')),
        _GuideStep(
          context.tr(
            'Bấm biểu tượng bánh răng cạnh $deviceName.',
            '点击 $deviceName 旁边的齿轮图标。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Tắt "Cuộc gọi điện thoại" và "Âm thanh đa phương tiện". Vẫn giữ ghép đôi.',
            '关闭“通话音频”和“媒体音频”，保留配对。',
          ),
          preview: const _ProfileTogglesPreview(enabled: false),
        ),
        _GuideStep(
          context.tr(
            'Quay lại HOMI. App sẽ tự kết nối nút MAIN.',
            '返回 HOMI，应用会自动连接 MAIN 按钮。',
          ),
        ),
      ],
      (true, true) => <_GuideStep>[
        _GuideStep(
          context.tr(
            'Mở app Cài đặt của iPhone, chọn Bluetooth.',
            '打开 iPhone 的“设置”，选择“蓝牙”。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Bấm (i) cạnh $deviceName, chọn "Ngắt kết nối".',
            '点击 $deviceName 旁边的 (i)，选择“断开连接”。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Quay lại HOMI. App sẽ tự kết nối nút MAIN.',
            '返回 HOMI，应用会自动连接 MAIN 按钮。',
          ),
        ),
      ],
      (false, false) => <_GuideStep>[
        _GuideStep(context.tr('Bấm "Mở Cài đặt Bluetooth".', '点击“打开蓝牙设置”。')),
        _GuideStep(
          context.tr(
            'Đã có $deviceName trong danh sách đã ghép nối: bấm bánh răng, bật lại "Cuộc gọi điện thoại" và "Âm thanh đa phương tiện".',
            '已配对列表中有 $deviceName：点击齿轮，重新开启“通话音频”和“媒体音频”。',
          ),
          preview: const _ProfileTogglesPreview(enabled: true),
        ),
        _GuideStep(
          context.tr(
            'Chưa có: bấm "Ghép nối thiết bị mới", chọn $deviceName.',
            '如果没有：点击“配对新设备”，选择 $deviceName。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Quay lại HOMI. App sẽ tự chọn micro HOMI.',
            '返回 HOMI，应用会自动选择 HOMI 麦克风。',
          ),
        ),
      ],
      (false, true) => <_GuideStep>[
        _GuideStep(
          context.tr(
            'Mở app Cài đặt của iPhone, chọn Bluetooth.',
            '打开 iPhone 的“设置”，选择“蓝牙”。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Bấm $deviceName để kết nối (trong "Thiết bị khác" nếu chưa ghép đôi).',
            '点击 $deviceName 进行连接（如未配对，在“其他设备”中）。',
          ),
        ),
        _GuideStep(
          context.tr(
            'Quay lại HOMI. App sẽ tự chọn micro HOMI.',
            '返回 HOMI，应用会自动选择 HOMI 麦克风。',
          ),
        ),
      ],
    };

    return SingleChildScrollView(
      key: Key(pause ? 'homi-guide-pause-audio' : 'homi-guide-enable-audio'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            _StepRow(number: i + 1, step: steps[i]),
          const SizedBox(height: 4),
          FilledButton.icon(
            key: const Key('homi-guide-open-settings'),
            onPressed: () =>
                Navigator.of(context).pop(HomiGuideAction.openSettings),
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
            key: const Key('homi-guide-check-again'),
            onPressed: () =>
                Navigator.of(context).pop(HomiGuideAction.checkAgain),
            child: Text(
              context.tr('Tôi đã làm xong, kiểm tra lại', '我已完成，重新检查'),
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

/// Sketch of the Android device-details screen with the two audio profile
/// switches. Labels vary between phone makers; the switches are the point.
class _ProfileTogglesPreview extends StatelessWidget {
  const _ProfileTogglesPreview({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkMint : AppColors.mint;
    Widget row(String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          IgnorePointer(
            child: Switch(
              value: enabled,
              onChanged: (_) {},
              activeThumbColor: Colors.white,
              activeTrackColor: accent,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceRaised
            : theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: accent, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
            child: Text(
              HomiAudioGuideSheet.deviceName,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          row(context.tr('Cuộc gọi điện thoại', '通话音频')),
          row(context.tr('Âm thanh đa phương tiện', '媒体音频')),
        ],
      ),
    );
  }
}
