import 'package:flutter/material.dart';

class SettingsActionTile extends StatelessWidget {
  const SettingsActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.showDetail = false,
    super.key,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool showDetail;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, size: 25, color: Theme.of(context).colorScheme.primary),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    subtitle: showDetail ? Text(detail) : null,
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
