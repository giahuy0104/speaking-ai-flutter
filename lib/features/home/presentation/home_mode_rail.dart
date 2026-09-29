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

  // Keep a full cross-platform touch target while the painted rail remains
  // deliberately slimmer than the tappable area.
  static const double _collapsedWidth = 48;
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
    final railClipper = _HomeRailTrapezoidClipper(edge);

    return SizedBox(
      key: const Key('collapsed-home-mode-rail'),
      width: HomeModeRail._collapsedWidth,
      height: railHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: railClipper,
              child: ColoredBox(
                color: isDark
                    ? theme.colorScheme.primaryContainer
                    : AppColors.primaryNavy,
              ),
            ),
          ),
          Positioned(
            top: 8,
            bottom: 8,
            left: isLeft ? 0 : 4,
            right: isLeft ? 4 : 0,
            child: ClipPath(
              clipper: railClipper,
              child: ColoredBox(
                color: isDark ? theme.colorScheme.tertiary : AppColors.mint,
              ),
            ),
          ),
          Positioned(
            top: (railHeight - 30) / 2,
            left: isLeft ? 38 : null,
            right: isLeft ? null : 38,
            child: Container(
              width: 10,
              height: 30,
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
            top: 14,
            bottom: 14,
            left: isLeft ? 0 : 8,
            right: isLeft ? 8 : 0,
            child: ClipPath(
              clipper: railClipper,
              child: ColoredBox(
                color: faceColor,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    children: <Widget>[
                      Icon(icon, color: contentColor, size: 22),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Center(
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.15,
                            child: Text(
                              _stackedLabel(label.toUpperCase()),
                              key: const Key('home-mode-rail-stacked-label'),
                              textAlign: TextAlign.center,
                              softWrap: false,
                              style: TextStyle(
                                color: contentColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
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
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onPressed),
            ),
          ),
        ],
      ),
    );
  }

  String _stackedLabel(String value) => value
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .runes
      .map(String.fromCharCode)
      .join('\n');
}

class _HomeRailTrapezoidClipper extends CustomClipper<Path> {
  const _HomeRailTrapezoidClipper(this.edge);

  final HomeRailEdge edge;

  @override
  Path getClip(Size size) {
    const slope = 13.0;
    const curve = 5.0;
    final path = Path();
    if (edge == HomeRailEdge.left) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width - curve, slope)
        ..quadraticBezierTo(size.width, slope + 1, size.width, slope + curve)
        ..lineTo(size.width, size.height - slope - curve)
        ..quadraticBezierTo(
          size.width,
          size.height - slope - 1,
          size.width - curve,
          size.height - slope,
        )
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(curve, slope)
        ..quadraticBezierTo(0, slope + 1, 0, slope + curve)
        ..lineTo(0, size.height - slope - curve)
        ..quadraticBezierTo(
          0,
          size.height - slope - 1,
          curve,
          size.height - slope,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_HomeRailTrapezoidClipper oldClipper) =>
      oldClipper.edge != edge;
}
