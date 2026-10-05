import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

enum HomeRailEdge { left, right }

class HomeModeRail extends StatelessWidget {
  const HomeModeRail({
    required this.edge,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.badge,
    this.expanded = false,
    super.key,
  });

  final HomeRailEdge edge;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String? badge;
  final bool expanded;

  static const double _collapsedWidth = 52;
  static const double _collapsedHeight = 184;
  static const double _collapsedHeightWithBadge = 198;
  static const double _expandedWidth = 138;
  static const double _expandedHeight = 184;

  @override
  Widget build(BuildContext context) {
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: AnimatedSwitcher(
          duration: animationDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: expanded
              ? SizedBox(
                  key: const Key('expanded-home-mode-rail'),
                  width: _expandedWidth,
                  height: _expandedHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: InkWell(
                      onTap: onPressed,
                      borderRadius: BorderRadius.circular(22),
                      child: _ExpandedRailContent(label: label, icon: icon),
                    ),
                  ),
                )
              : _CollapsedRailContent(
                  edge: edge,
                  label: label,
                  icon: icon,
                  badge: badge,
                  onPressed: onPressed,
                ),
        ),
      ),
    );
  }
}

class _ExpandedRailContent extends StatelessWidget {
  const _ExpandedRailContent({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedRailContent extends StatelessWidget {
  const _CollapsedRailContent({
    required this.edge,
    required this.label,
    required this.icon,
    required this.badge,
    required this.onPressed,
  });

  final HomeRailEdge edge;
  final String label;
  final IconData icon;
  final String? badge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLeft = edge == HomeRailEdge.left;
    final isDark = theme.brightness == Brightness.dark;
    final railHeight = badge == null
        ? HomeModeRail._collapsedHeight
        : HomeModeRail._collapsedHeightWithBadge;
    final faceColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFFFFEFB);
    final contentColor = isDark
        ? theme.colorScheme.primary
        : AppColors.primaryNavy;
    return SizedBox(
      key: const Key('collapsed-home-mode-rail'),
      width: HomeModeRail._collapsedWidth,
      height: railHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(
              key: const Key('home-rail-silhouette'),
              painter: _HomeRailPainter(
                edge: edge,
                spineColor: isDark
                    ? theme.colorScheme.primaryContainer
                    : AppColors.primaryNavy,
                borderColor: isDark
                    ? theme.colorScheme.tertiary
                    : AppColors.mint,
                faceColor: faceColor,
              ),
            ),
          ),
          Positioned(
            top: (railHeight - 24) / 2,
            left: isLeft ? 46 : null,
            right: isLeft ? null : 46,
            child: Container(
              width: 8,
              height: 24,
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.secondary
                    : AppColors.accentPink,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(isLeft ? 0 : 8),
                  right: Radius.circular(isLeft ? 8 : 0),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22D90E5E),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 36,
            bottom: 10,
            left: isLeft ? 12 : 4,
            right: isLeft ? 4 : 12,
            child: Column(
              children: <Widget>[
                Icon(icon, color: contentColor, size: 22),
                const SizedBox(height: 9),
                Expanded(
                  child: Center(
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.15,
                      child: Transform.translate(
                        offset: const Offset(0, -8),
                        child: Text(
                          _stackedLabel(label),
                          key: const Key('home-mode-rail-label'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.primaryContainer
                          : AppColors.mintSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed,
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onPressed),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stackedLabel(String value) => value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), '')
      .runes
      .map(String.fromCharCode)
      .join('\n');
}

class _HomeRailPainter extends CustomPainter {
  const _HomeRailPainter({
    required this.edge,
    required this.spineColor,
    required this.borderColor,
    required this.faceColor,
  });

  final HomeRailEdge edge;
  final Color spineColor;
  final Color borderColor;
  final Color faceColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (edge == HomeRailEdge.right) {
      canvas
        ..save()
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }

    final w = size.width;
    final h = size.height;
    final spine = Path()
      ..moveTo(0, 0)
      ..cubicTo(12, 0, 18, 5, 22, 13)
      ..lineTo(22, h - 13)
      ..cubicTo(18, h - 5, 12, h, 0, h)
      ..close();
    final border = Path()
      ..moveTo(8, 14)
      ..cubicTo(19, 13, w - 11, 20, w - 4, 28)
      ..quadraticBezierTo(w, 32, w, 40)
      ..lineTo(w, h - 40)
      ..quadraticBezierTo(w, h - 30, w - 5, h - 25)
      ..cubicTo(w - 15, h - 17, 19, h - 10, 8, h - 7)
      ..close();
    final face = Path()
      ..moveTo(12, 19)
      ..cubicTo(23, 18, w - 15, 25, w - 9, 32)
      ..quadraticBezierTo(w - 5, 36, w - 5, 42)
      ..lineTo(w - 5, h - 42)
      ..quadraticBezierTo(w - 5, h - 35, w - 10, h - 31)
      ..cubicTo(w - 19, h - 24, 22, h - 18, 12, h - 15)
      ..close();

    canvas.drawPath(spine, Paint()..color = spineColor);
    canvas.drawShadow(border, Colors.black.withValues(alpha: 0.17), 3, true);
    canvas.drawPath(border, Paint()..color = borderColor);
    canvas.drawPath(face, Paint()..color = faceColor);

    if (edge == HomeRailEdge.right) canvas.restore();
  }

  @override
  bool shouldRepaint(_HomeRailPainter oldDelegate) =>
      oldDelegate.edge != edge ||
      oldDelegate.spineColor != spineColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.faceColor != faceColor;
}
