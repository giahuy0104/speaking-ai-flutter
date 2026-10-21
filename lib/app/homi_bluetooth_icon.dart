import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The Bluetooth mark used for HOMI's MAIN control connection.
class HomiBluetoothIcon extends StatelessWidget {
  const HomiBluetoothIcon({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark
            ? theme.colorScheme.surfaceContainerHigh
            : AppColors.mintWash,
        borderRadius: BorderRadius.circular(size * .3),
        border: Border.all(
          color: dark ? theme.colorScheme.outlineVariant : AppColors.mintBorder,
        ),
      ),
      child: Icon(
        Icons.bluetooth_rounded,
        size: size * .55,
        color: dark ? theme.colorScheme.primary : AppColors.primaryNavy,
      ),
    );
  }
}
