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

  static const double _expandedWidth = 138;
  static const double _expandedHeight = 184;

  @override
  Widget build(BuildContext context) {
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return Semantics(
      button: true,
      label: badge == null ? label : '$label, $badge',
      onTap: onPressed,
      excludeSemantics: true,
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
    final isLeft = edge == HomeRailEdge.left;
    final width = (MediaQuery.sizeOf(context).width * 0.22).clamp(78.0, 100.0);
    final height = width * 1.12 + (badge == null ? 0 : 22);
    final radius = BorderRadius.horizontal(
      left: Radius.circular(isLeft ? 12 : 28),
      right: Radius.circular(isLeft ? 28 : 12),
    );
    final medallionSize = width * 0.66;
    return SizedBox(
      key: const Key('collapsed-home-mode-rail'),
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(
            top: width * 0.28,
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              key: const Key('home-rail-silhouette'),
              decoration: BoxDecoration(
                color: const Color(0xFF071F4A),
                borderRadius: radius,
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x260B2C66),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy,
                    borderRadius: radius,
                    border: Border.all(color: const Color(0x334B79AE)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: width * 0.08,
            left: (width - medallionSize) / 2,
            child: Container(
              width: medallionSize,
              height: medallionSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF91E5D5), width: 1.3),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x22051432),
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: AppColors.primaryNavy,
                size: width * 0.34,
              ),
            ),
          ),
          Positioned(
            top: -width * 0.05,
            left: isLeft ? width * 0.08 : null,
            right: isLeft ? null : width * 0.08,
            child: ExcludeSemantics(
              child: Transform.flip(
                flipX: !isLeft,
                child: SizedBox(
                  width: width * 0.24,
                  height: width * 0.24,
                  child: ClipRect(
                    child: OverflowBox(
                      maxWidth: width * 0.48,
                      maxHeight: width * 0.48,
                      child: Image.asset(
                        'assets/images/home-navigation-rays.png',
                        width: width * 0.48,
                        height: width * 0.48,
                        cacheWidth: 144,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: width * 0.79,
            left: 7,
            right: 7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    key: const Key('home-mode-rail-label'),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                ),
                if (badge != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: radius,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
