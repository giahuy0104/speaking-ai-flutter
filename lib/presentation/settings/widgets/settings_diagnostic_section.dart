import 'package:flutter/material.dart';
import '../../../app/homi_ui.dart';

class SettingsDiagnosticSection extends StatelessWidget {
  const SettingsDiagnosticSection({
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
    return HomiSurface(
      padding: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: HomiIconBadge(icon: icon),
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
    );
  }
}
