import 'package:flutter/material.dart';
import '../../../app/homi_ui.dart';
import '../../../l10n/display_language.dart';

class SettingsBackgroundMediaCard extends StatelessWidget {
  const SettingsBackgroundMediaCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomiSurface(
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        key: const Key('settings-stop-media-background-switch'),
        value: value,
        onChanged: onChanged,
        secondary: const HomiIconBadge(
          icon: Icons.pause_circle_outline_rounded,
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
        title: Text(
          context.tr('Dừng âm thanh khi rời HOMI', '离开 HOMI 时停止音频'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          context.tr(
            'Mở ứng dụng khác hoặc khóa màn hình: dừng bài học, trợ lý và loa HOMI nhưng vẫn giữ tiến độ.',
            '打开其他应用或锁屏时：停止课程、助手和 HOMI 扬声器，同时保留进度。',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
