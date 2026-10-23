import 'package:flutter/material.dart';
import '../../../l10n/display_language.dart';

class SettingsDeviceHeading extends StatelessWidget {
  const SettingsDeviceHeading({
    super.key,
    required this.label,
    this.busy = false,
    this.ready = false,
  });
  final String label;
  final bool busy;
  final bool ready;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          shape: BoxShape.circle,
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                ready ? Icons.check_rounded : Icons.bluetooth_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.tr('Thiết bị HOMI', 'HOMI 设备'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
