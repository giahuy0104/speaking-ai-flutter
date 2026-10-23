import 'package:flutter/material.dart';
import '../../../app/app_theme.dart';

class SettingsRaisedPanel extends StatelessWidget {
  const SettingsRaisedPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurfaceRaised
        : Colors.white,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
