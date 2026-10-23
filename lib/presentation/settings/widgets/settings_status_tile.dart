import 'package:flutter/material.dart';
import '../../../app/homi_ui.dart';

class SettingsStatusTile extends StatelessWidget {
  const SettingsStatusTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.stateColor,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String trailing;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return HomiSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HomiIconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: HomiStatusPill(label: trailing, color: stateColor),
          ),
        ],
      ),
    );
  }
}
