import 'package:flutter/material.dart';

class SettingsExpandableSection extends StatelessWidget {
  const SettingsExpandableSection({
    required this.icon,
    required this.title,
    required this.children,
    super.key,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      leading: Icon(
        icon,
        size: 26,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      maintainState: true,
      children: children,
    ),
  );
}
