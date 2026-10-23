import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';

class SettingsRaisedIcon extends StatelessWidget {
  const SettingsRaisedIcon({
    super.key,
    required this.icon,
    this.foregroundColor,
  });

  final IconData icon;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const size = 40.0;
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
      child: Icon(
        icon,
        size: 22,
        color: foregroundColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
