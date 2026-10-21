import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

enum HomeRailEdge { left, right }

class HomeModeRail extends StatefulWidget {
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

  static const double collapsedWidth = 48;
  static const double collapsedHeight = 168;

  @override
  State<HomeModeRail> createState() => _HomeModeRailState();
}

class _HomeModeRailState extends State<HomeModeRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 170),
  );
  bool _activating = false;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _pressDown(TapDownDetails _) {
    if (!_reduceMotion && !_activating) _press.forward();
  }

  void _cancelPress() {
    if (!_activating) _press.reverse();
  }

  Future<void> _activate() async {
    if (_activating) return;
    _activating = true;
    try {
      // A single tap briefly finishes its visual feedback before invoking the
      // existing navigation callback. The hit target itself never moves.
      if (!_reduceMotion) await _press.forward().orCancel;
      if (!mounted) return;
      widget.onPressed();
      if (mounted) _press.reverse();
    } on TickerCanceled {
      // The source can disappear while a pointer interaction is in progress.
    } finally {
      _activating = false;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(15) / 15;
    final collapsedWidth = (HomeModeRail.collapsedWidth + (textScale - 1) * 8)
        .clamp(HomeModeRail.collapsedWidth, 56.0)
        .toDouble();
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return Semantics(
      button: true,
      label: widget.badge == null
          ? widget.label
          : '${widget.label}, ${widget.badge}',
      onTap: _activate,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: AnimatedSwitcher(
          duration: animationDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: widget.expanded
              ? SizedBox(
                  key: const Key('expanded-home-mode-rail'),
                  width: HomeModeRail._expandedWidth,
                  height: HomeModeRail._expandedHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: InkWell(
                      onTap: _activate,
                      onTapDown: _pressDown,
                      onTapCancel: _cancelPress,
                      borderRadius: BorderRadius.circular(22),
                      child: _ExpandedRailContent(
                        label: widget.label,
                        icon: widget.icon,
                      ),
                    ),
                  ),
                )
              : SizedBox(
                  key: const Key('collapsed-home-mode-rail'),
                  width: collapsedWidth,
                  height: HomeModeRail.collapsedHeight,
                  child: InkWell(
                    onTap: _activate,
                    onTapDown: _pressDown,
                    onTapCancel: _cancelPress,
                    excludeFromSemantics: true,
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: AnimatedBuilder(
                      animation: _press,
                      builder: (context, child) => Transform.scale(
                        key: const Key('home-cloud-press-transform'),
                        alignment: widget.edge == HomeRailEdge.left
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        scale: _reduceMotion
                            ? 1
                            : 1 +
                                  Curves.easeOutCubic.transform(_press.value) *
                                      0.045,
                        transformHitTests: false,
                        child: child,
                      ),
                      child: _CloudRailContent(
                        edge: widget.edge,
                        label: widget.label,
                        icon: widget.icon,
                        badge: widget.badge,
                        contentWidth: collapsedWidth - 20,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _CloudRailContent extends StatelessWidget {
  const _CloudRailContent({
    required this.edge,
    required this.label,
    required this.icon,
    required this.contentWidth,
    this.badge,
  });

  final HomeRailEdge edge;
  final String label;
  final IconData icon;
  final double contentWidth;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final isLeft = edge == HomeRailEdge.left;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? AppColors.darkPrimary : AppColors.primaryNavy;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        ExcludeSemantics(
          child: RepaintBoundary(
            key: const Key('home-cloud-artwork'),
            // The artwork includes its curved caps and a wide white face.
            // Paint it whole: stretching a white strip creates square ledges
            // at the top/bottom, and clipping removes the blue curved rim.
            child: ColorFiltered(
              colorFilter: isDark
                  ? const ColorFilter.mode(
                      Color(0xFF244E78),
                      BlendMode.modulate,
                    )
                  : const ColorFilter.mode(
                      Color(0x33FFFFFF),
                      BlendMode.srcATop,
                    ),
              child: FractionallySizedBox(
                // The right PNG's solid screen edge ends at column 834 of
                // 894. Put that edge on screen; only alpha padding overflows.
                widthFactor: isLeft ? 1 : 894 / 835,
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  isLeft
                      ? 'assets/images/home-cloud-tab-left.png'
                      : 'assets/images/home-cloud-tab-right.png',
                  key: const Key('home-rail-silhouette'),
                  fit: BoxFit.fill,
                  cacheWidth: 216,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 46,
          left: isLeft ? 0 : null,
          right: isLeft ? null : 0,
          width: isLeft ? contentWidth : contentWidth - 5,
          height: 94,
          child: Column(
            children: <Widget>[
              Icon(
                icon,
                key: const Key('home-mode-rail-icon'),
                color: foreground,
                size: 21,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RotatedBox(
                  quarterTurns: isLeft ? 3 : 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      key: const Key('home-mode-rail-label'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              if (badge != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(badge!, style: const TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ),
      ],
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
