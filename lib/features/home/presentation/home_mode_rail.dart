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

  static const double _collapsedWidth = 50;
  static const double _collapsedHeight = 176;
  static const double _collapsedHeightWithBadge = 190;
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
    final faceRadius = BorderRadius.only(
      topLeft: Radius.circular(isLeft ? 0 : 22),
      bottomLeft: Radius.circular(isLeft ? 0 : 22),
      topRight: Radius.circular(isLeft ? 22 : 0),
      bottomRight: Radius.circular(isLeft ? 22 : 0),
    );

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
            left: isLeft ? 0 : 12,
            right: isLeft ? 12 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.primaryContainer
                    : AppColors.primaryNavy,
                borderRadius: faceRadius,
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x32142451),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 14,
            bottom: 14,
            left: isLeft ? 0 : 3,
            right: isLeft ? 3 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.tertiary : AppColors.mint,
                borderRadius: faceRadius,
              ),
            ),
          ),
          Positioned(
            top: (railHeight - 34) / 2,
            left: isLeft ? 40 : null,
            right: isLeft ? null : 40,
            child: Container(
              width: 12,
              height: 34,
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
            top: 18,
            bottom: 18,
            left: isLeft ? 0 : 4,
            right: isLeft ? 4 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: faceColor,
                borderRadius: faceRadius,
                border: Border.all(
                  color: isDark
                      ? theme.colorScheme.tertiary
                      : const Color(0xFF62D9C5),
                  width: 1.4,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x24142451),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Column(
                  children: <Widget>[
                    Icon(icon, color: contentColor, size: 23),
                    const SizedBox(height: 11),
                    Expanded(
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              color: contentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.1,
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
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onPressed, borderRadius: faceRadius),
            ),
          ),
        ],
      ),
    );
  }
}
