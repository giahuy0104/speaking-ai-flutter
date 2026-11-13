import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'homi_assistant_bubble.dart';

/// Lets the user drag the HOMI bubble anywhere; on release it springs to the
/// nearest side edge. The chosen edge and height survive app restarts.
///
/// Place it as a direct child of a full-screen [Stack].
class HomiBubbleDock extends StatefulWidget {
  const HomiBubbleDock({
    required this.child,
    this.bubbleSize = HomiAssistantBubble.touchSize,
    this.edgeMargin = 12,
    this.bottomReserve = 112,
    this.topReserve = 64,
    super.key,
  });

  final Widget child;
  final double bubbleSize;
  final double edgeMargin;

  /// Gap kept below the bubble so it never covers bottom CTAs.
  final double bottomReserve;

  /// Gap kept below the status bar so it never covers app bar actions.
  final double topReserve;

  static const _sideKey = 'homi_bubble_dock.on_right';
  static const _heightKey = 'homi_bubble_dock.height_fraction';

  /// The spot last read or saved. The dock is rebuilt each time HOMI shows
  /// again, and this lets it start there instead of waiting for preferences.
  static ({bool onRight, double heightFraction})? _lastSpot;

  @visibleForTesting
  static void resetSavedSpotForTest() => _lastSpot = null;

  @override
  State<HomiBubbleDock> createState() => _HomiBubbleDockState();
}

class _HomiBubbleDockState extends State<HomiBubbleDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  );

  bool _onRight = true;

  /// 0 = highest allowed spot, 1 = lowest (the default, like the old FAB).
  double _heightFraction = 1;

  Offset? _dragPosition;
  Offset _settleFrom = Offset.zero;
  Offset _tilt = Offset.zero;
  Offset _settleTilt = Offset.zero;
  bool _settling = false;

  /// Set once the user moves the bubble, so a late read of the saved spot
  /// cannot pull it back.
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    _spring.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _settling = false);
      }
    });
    final spot = HomiBubbleDock._lastSpot;
    if (spot != null) {
      _onRight = spot.onRight;
      _heightFraction = spot.heightFraction;
    } else {
      unawaited(_restore());
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final onRight = prefs.getBool(HomiBubbleDock._sideKey);
      final fraction = prefs.getDouble(HomiBubbleDock._heightKey);
      if (!mounted || _moved || (onRight == null && fraction == null)) return;
      setState(() {
        _onRight = onRight ?? _onRight;
        _heightFraction = (fraction ?? _heightFraction).clamp(0.0, 1.0);
      });
      _remember();
    } on Object {
      // Preferences are a convenience; the default corner still works.
    }
  }

  void _remember() => HomiBubbleDock._lastSpot = (
    onRight: _onRight,
    heightFraction: _heightFraction,
  );

  Future<void> _persist() async {
    _remember();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(HomiBubbleDock._sideKey, _onRight);
      await prefs.setDouble(HomiBubbleDock._heightKey, _heightFraction);
    } on Object {
      // Ignore: losing the saved spot only resets it to the default corner.
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  ({double minX, double maxX, double minY, double maxY}) _bounds(Size area) {
    final padding = MediaQuery.paddingOf(context);
    final size = widget.bubbleSize;
    final minY = padding.top + widget.topReserve;
    final maxY = math.max(
      minY,
      area.height - math.max(padding.bottom, widget.bottomReserve) - size,
    );
    return (
      minX: padding.left + widget.edgeMargin,
      maxX: math.max(
        padding.left + widget.edgeMargin,
        area.width - padding.right - widget.edgeMargin - size,
      ),
      minY: minY,
      maxY: maxY,
    );
  }

  Offset _dockedPosition(Size area) {
    final b = _bounds(area);
    return Offset(
      _onRight ? b.maxX : b.minX,
      b.minY + (b.maxY - b.minY) * _heightFraction,
    );
  }

  void _onPanStart(DragStartDetails details, Size area) {
    // Read where the bubble is before stopping the settle animation,
    // which would otherwise make it jump to its target.
    final start = _currentPosition(area);
    _spring.stop();
    _moved = true;
    setState(() {
      _settling = false;
      _dragPosition = start;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size area) {
    final current = _dragPosition;
    if (current == null) return;
    final size = widget.bubbleSize;
    final next = Offset(
      (current.dx + details.delta.dx).clamp(-8.0, area.width - size + 8),
      (current.dy + details.delta.dy).clamp(0.0, area.height - size),
    );
    final targetTilt = Offset(
      (details.delta.dx * 3).clamp(-28.0, 28.0),
      (-details.delta.dy * 3).clamp(-28.0, 28.0),
    );
    setState(() {
      _dragPosition = next;
      _tilt = Offset.lerp(_tilt, targetTilt, 0.35)!;
      _onRight = next.dx + size / 2 > area.width / 2;
    });
  }

  void _onPanEnd(DragEndDetails details, Size area) {
    final from = _dragPosition;
    if (from == null) return;
    final b = _bounds(area);
    final velocity = details.velocity.pixelsPerSecond;
    final projectedY = from.dy + velocity.dy * 0.1;
    final span = b.maxY - b.minY;
    _onRight = from.dx + widget.bubbleSize / 2 > area.width / 2;
    _heightFraction = span <= 0
        ? 1
        : ((projectedY.clamp(b.minY, b.maxY) - b.minY) / span);
    _settleFrom = from;
    _settleTilt = _tilt;
    final target = _dockedPosition(area);
    final distance = (target - from).distance;
    final speedTowardTarget = distance == 0
        ? 0.0
        : (velocity.dx * (target.dx - from.dx) +
                  velocity.dy * (target.dy - from.dy)) /
              (distance * distance);
    setState(() {
      _dragPosition = null;
      _tilt = Offset.zero;
      _settling = true;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _spring.value = 1;
      setState(() => _settling = false);
    } else {
      _spring.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 260, damping: 19),
          0,
          1,
          speedTowardTarget.clamp(-8.0, 8.0),
        ),
      );
    }
    unawaited(_persist());
  }

  Offset _currentPosition(Size area) {
    final drag = _dragPosition;
    if (drag != null) return drag;
    final docked = _dockedPosition(area);
    if (!_settling) return docked;
    return Offset.lerp(_settleFrom, docked, _spring.value)!;
  }

  Offset _currentTilt() {
    if (_dragPosition != null) return _tilt;
    if (!_settling) return Offset.zero;
    return _settleTilt * (1 - _spring.value).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        final dragging = _dragPosition != null;
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            AnimatedBuilder(
              animation: _spring,
              builder: (context, child) {
                final position = _currentPosition(area);
                final tilt = _currentTilt();
                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.002)
                  ..rotateX(tilt.dy * math.pi / 180)
                  ..rotateY(tilt.dx * math.pi / 180);
                if (dragging) transform.scaleByDouble(1.08, 1.08, 1.08, 1);
                return Positioned(
                  left: position.dx,
                  top: position.dy,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: transform,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                // Dragging is a visual nicety; keep the button's own
                // semantics free of scroll actions.
                excludeFromSemantics: true,
                onPanStart: (details) => _onPanStart(details, area),
                onPanUpdate: (details) => _onPanUpdate(details, area),
                onPanEnd: (details) => _onPanEnd(details, area),
                onPanCancel: () {
                  if (_dragPosition == null) return;
                  _onPanEnd(DragEndDetails(), area);
                },
                child: HomiBubbleDockScope(
                  onRight: _onRight,
                  lifted: dragging,
                  child: widget.child,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
