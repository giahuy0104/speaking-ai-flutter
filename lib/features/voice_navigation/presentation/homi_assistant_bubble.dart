import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual state of the floating HOMI bubble that replaces the old MAIN FAB.
enum HomiBubbleVisual {
  idle,
  busy,
  preparing,
  homiSpeaking,
  listening,
  translating,
  playing,
  retrying,
  micError,
  commandError,
}

/// Tells the bubble which screen edge it is docked to and whether it is
/// being dragged, so the label and chip open toward the screen centre.
class HomiBubbleDockScope extends InheritedWidget {
  const HomiBubbleDockScope({
    required this.onRight,
    required this.lifted,
    required super.child,
    super.key,
  });

  final bool onRight;
  final bool lifted;

  static HomiBubbleDockScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HomiBubbleDockScope>();

  @override
  bool updateShouldNotify(HomiBubbleDockScope oldWidget) =>
      oldWidget.onRight != onRight || oldWidget.lifted != lifted;
}

enum _Pose { avatar, wave, listen, speak, sing }

enum _Effect { none, dottedRing, ripple, colorRing, orbit, arc }

const _sky = Color(0xFF8FC0F2);
const _amber = Color(0xFFFFB627);
const _blue = Color(0xFF3D63C9);
const _teal = Color(0xFF21C2A8);
const _coral = Color(0xFFFF7A59);
const _red = Color(0xFFE5484D);
const _ink = Color(0xFF14214A);

class _Spec {
  const _Spec({
    required this.pose,
    required this.color,
    this.effect = _Effect.none,
    this.chipIcon,
    this.chipText,
    this.animated = true,
    this.talk = false,
    this.notes = false,
    this.ears = false,
    this.sweat = false,
    this.think = false,
    this.breathe = false,
    this.grayscale = false,
    this.error = false,
  });

  final _Pose pose;
  final Color color;
  final _Effect effect;
  final IconData? chipIcon;
  final String? chipText;
  final bool animated;
  final bool talk;
  final bool notes;
  final bool ears;
  final bool sweat;
  final bool think;
  final bool breathe;
  final bool grayscale;
  final bool error;

  bool get hasChip => chipIcon != null || chipText != null;
}

_Spec _specFor(HomiBubbleVisual visual) => switch (visual) {
  HomiBubbleVisual.idle => const _Spec(
    pose: _Pose.wave,
    color: _sky,
    animated: false,
  ),
  HomiBubbleVisual.busy => const _Spec(
    pose: _Pose.avatar,
    color: _sky,
    animated: false,
    grayscale: true,
  ),
  HomiBubbleVisual.preparing => const _Spec(
    pose: _Pose.listen,
    color: _amber,
    effect: _Effect.dottedRing,
    chipIcon: Icons.mic_rounded,
    breathe: true,
  ),
  HomiBubbleVisual.homiSpeaking => const _Spec(
    pose: _Pose.speak,
    color: _blue,
    effect: _Effect.colorRing,
    talk: true,
  ),
  HomiBubbleVisual.listening => const _Spec(
    pose: _Pose.listen,
    color: _teal,
    effect: _Effect.ripple,
    ears: true,
  ),
  HomiBubbleVisual.translating => const _Spec(
    pose: _Pose.avatar,
    color: _amber,
    effect: _Effect.orbit,
    chipIcon: Icons.translate_rounded,
    think: true,
  ),
  HomiBubbleVisual.playing => const _Spec(
    pose: _Pose.sing,
    color: _coral,
    effect: _Effect.colorRing,
    talk: true,
    notes: true,
  ),
  HomiBubbleVisual.retrying => const _Spec(
    pose: _Pose.avatar,
    color: _red,
    effect: _Effect.arc,
    sweat: true,
  ),
  HomiBubbleVisual.micError => const _Spec(
    pose: _Pose.avatar,
    color: _red,
    chipText: '!',
    animated: false,
    error: true,
  ),
  HomiBubbleVisual.commandError => const _Spec(
    pose: _Pose.avatar,
    color: _red,
    chipText: '?',
    animated: false,
    error: true,
  ),
};

/// Source images are 1254 px squares; each viewport picks the part shown
/// inside the orb (upper body for full poses, whole head for the avatar).
const double _sourceSize = 1254;

class _PoseAsset {
  const _PoseAsset(this.path, this.left, this.top, this.width);
  final String path;
  final double left;
  final double top;
  final double width;
}

const _poseAssets = <_Pose, _PoseAsset>{
  _Pose.avatar: _PoseAsset(
    'assets/images/mascot/penguin-avatar.png',
    30,
    -18,
    1194,
  ),
  _Pose.wave: _PoseAsset('assets/images/mascot/penguin-wave.png', 237, 75, 779),
  _Pose.listen: _PoseAsset(
    'assets/images/mascot/penguin-listen.png',
    237,
    75,
    779,
  ),
  _Pose.speak: _PoseAsset(
    'assets/images/mascot/penguin-speak.png',
    237,
    75,
    779,
  ),
  _Pose.sing: _PoseAsset('assets/images/mascot/penguin-sing.png', 237, 75, 779),
};

const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// HOMI in a glossy 3D orb. Each [HomiBubbleVisual] gets its own pose,
/// orb colour, accessory and motion; the status [label] floats above it.
class HomiAssistantBubble extends StatefulWidget {
  const HomiAssistantBubble({
    required this.visual,
    this.label,
    this.onPressed,
    super.key,
  });

  /// Size of the orb as drawn.
  static const double size = 46;

  /// Tappable square around the orb; meets the 48 dp minimum touch target.
  static const double touchSize = 48;

  final HomiBubbleVisual visual;
  final String? label;
  final VoidCallback? onPressed;

  @override
  State<HomiAssistantBubble> createState() => _HomiAssistantBubbleState();
}

class _HomiAssistantBubbleState extends State<HomiAssistantBubble>
    with TickerProviderStateMixin {
  late final AnimationController _loop;
  late final AnimationController _shake;
  late final AnimationController _hello;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _pressed = false;
  bool _greeted = false;

  _Spec get _spec => _specFor(widget.visual);

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _hello = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncLoop();
    if (!_greeted) {
      _greeted = true;
      if (!_reduceMotion) _hello.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant HomiAssistantBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visual == widget.visual) return;
    _syncLoop();
    if (_reduceMotion) return;
    if (_spec.error) _shake.forward(from: 0);
    if (widget.visual == HomiBubbleVisual.idle) _hello.forward(from: 0);
  }

  void _syncLoop() {
    if (_spec.animated && !_reduceMotion && _tickerEnabled) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _shake.dispose();
    _hello.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final scope = HomiBubbleDockScope.maybeOf(context);
    final onRight = scope?.onRight ?? true;
    final lifted = scope?.lifted ?? false;
    final label = widget.label;
    final onPressed = widget.onPressed;
    const size = HomiAssistantBubble.size;

    return SizedBox.square(
      dimension: HomiAssistantBubble.touchSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        onTapDown: onPressed == null ? null : (_) => _setPressed(true),
        onTapUp: onPressed == null ? null : (_) => _setPressed(false),
        onTapCancel: onPressed == null ? null : () => _setPressed(false),
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: -9,
                  height: 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: lifted ? 0.45 : 1,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: lifted ? 0.7 : 1,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: <Color>[
                              Color(0x520F2A63),
                              Color(0x000F2A63),
                            ],
                          ),
                          borderRadius: BorderRadius.all(
                            Radius.elliptical(30, 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: size + 10,
                  right: onRight ? 0 : null,
                  left: onRight ? null : 0,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.88,
                            end: 1,
                          ).animate(animation),
                          alignment: onRight
                              ? Alignment.bottomRight
                              : Alignment.bottomLeft,
                          child: child,
                        ),
                      ),
                      child: label == null
                          ? const SizedBox.shrink()
                          : _LabelBubble(
                              key: ValueKey<String>(label),
                              label: label,
                              error: spec.error,
                              bars: spec.talk,
                              color: spec.color,
                              onRight: onRight,
                              loop: _loop,
                            ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutBack,
                    scale: _pressed ? 0.9 : 1,
                    child: AnimatedBuilder(
                      animation: Listenable.merge(<Listenable>[
                        _loop,
                        _shake,
                        _hello,
                      ]),
                      builder: (context, _) => _buildOrb(spec, onRight),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrb(_Spec spec, bool onRight) {
    const size = HomiAssistantBubble.size;
    final t = _loop.value;
    final s = _shake.value;
    final h = _hello.value;
    final shakeDx = s == 0 ? 0.0 : math.sin(s * math.pi * 6) * 5 * (1 - s);
    final helloTurn = h == 0 || h == 1
        ? 0.0
        : math.sin(h * math.pi * 3) * 0.12 * (1 - h);
    final amp = spec.talk ? _talkAmplitude(t) : 0.0;
    final breathe = spec.breathe ? 1 - 0.06 * _wave(t * 2) : 1.0;
    final think = spec.think ? -0.17 * _wave(t) : 0.0;
    final orbColor = spec.color;

    return Transform.translate(
      offset: Offset(shakeDx, 0),
      child: Transform.rotate(
        angle: helloTurn,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: -16,
              top: -16,
              right: -16,
              bottom: -16,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _EffectPainter(
                    spec: spec,
                    t: t,
                    radius: size / 2,
                    onRight: onRight,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Transform.scale(
                scale: breathe,
                child: _maybeGray(
                  spec.grayscale,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.44),
                        radius: 0.95,
                        colors: <Color>[
                          Colors.white,
                          Color.lerp(Colors.white, orbColor, 0.22)!,
                          Color.lerp(Colors.white, orbColor, 0.7)!,
                          orbColor,
                        ],
                        stops: const <double>[0, 0.4, 0.8, 1],
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x420F2A63),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Transform.translate(
                            offset: Offset(0, -amp * 4),
                            child: Transform.rotate(
                              angle: think,
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 380),
                                switchInCurve: Curves.easeOutBack,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.25),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: _PoseImage(
                                  key: ValueKey<_Pose>(spec.pose),
                                  pose: spec.pose,
                                  mirrored: !onRight,
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            left: size * 0.14,
                            top: size * 0.06,
                            width: size * 0.52,
                            height: size * 0.3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(
                                  Radius.elliptical(16, 9),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Color(0xBFFFFFFF),
                                    Color(0x00FFFFFF),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0x000F2A63),
                                  Color(0x330F2A63),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -2,
              top: -2,
              right: -2,
              bottom: -2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: spec.error || spec.ears ? orbColor : Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: orbColor.withValues(
                          alpha: spec.error ? 0.35 : 0.25,
                        ),
                        spreadRadius: spec.error ? 3 : 1.5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -8,
              right: onRight ? -8 : null,
              left: onRight ? null : -8,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.elasticOut,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: spec.hasChip
                      ? _Chip(
                          key: ValueKey<Object>(
                            spec.chipIcon ?? spec.chipText ?? '',
                          ),
                          color: orbColor,
                          icon: spec.chipIcon,
                          text: spec.chipText,
                          pulse: spec.error || spec.breathe
                              ? 1 + 0.12 * _wave(t * 2)
                              : 1,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _maybeGray(bool gray, Widget child) =>
      gray ? ColorFiltered(colorFilter: _grayscale, child: child) : child;
}

/// 0 → 1 → 0 once per unit of [x].
double _wave(double x) => 0.5 - 0.5 * math.cos(x * 2 * math.pi);

double _frac(double x) => x - x.floorToDouble();

double _talkAmplitude(double t) {
  final v =
      math.sin(t * 2 * math.pi * 9) * 0.5 +
      math.sin(t * 2 * math.pi * 14) * 0.3 +
      math.sin(t * 2 * math.pi * 4) * 0.2;
  return v.abs();
}

class _PoseImage extends StatelessWidget {
  const _PoseImage({required this.pose, required this.mirrored, super.key});

  final _Pose pose;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    const size = HomiAssistantBubble.size;
    final asset = _poseAssets[pose]!;
    final scale = size / asset.width;
    final imageSize = _sourceSize * scale;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        Positioned(
          left: -asset.left * scale,
          top: -asset.top * scale,
          width: imageSize,
          height: imageSize,
          child: Transform.flip(
            flipX: mirrored && pose != _Pose.avatar,
            child: Image.asset(
              asset.path,
              cacheWidth: (imageSize * dpr).round(),
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
              gaplessPlayback: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.color,
    required this.pulse,
    this.icon,
    this.text,
    super.key,
  });

  final Color color;
  final double pulse;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: pulse,
      child: Container(
        constraints: const BoxConstraints(minWidth: 19),
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(12)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x400F2A63),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: icon != null
            ? Icon(icon, size: 12, color: color)
            : Text(
                text!,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
      ),
    );
  }
}

class _LabelBubble extends StatelessWidget {
  const _LabelBubble({
    required this.label,
    required this.error,
    required this.bars,
    required this.color,
    required this.onRight,
    required this.loop,
    super.key,
  });

  final String label;
  final bool error;
  final bool bars;
  final Color color;
  final bool onRight;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = error
        ? (isDark ? const Color(0xFF4A1B1D) : const Color(0xFFFFF1F1))
        : (isDark ? const Color(0xFF1E2A44) : Colors.white);
    final foreground = error
        ? (isDark ? const Color(0xFFFFC9CB) : const Color(0xFF8A1C20))
        : (isDark ? Colors.white : _ink);
    final width = MediaQuery.sizeOf(context).width;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          bottom: -4,
          right: onRight ? 22 : null,
          left: onRight ? null : 22,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: SizedBox.square(
              dimension: 10,
              child: ColoredBox(color: background),
            ),
          ),
        ),
        Container(
          constraints: BoxConstraints(maxWidth: math.min(240, width - 48)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.all(Radius.circular(13)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x2E0F2A63),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (bars) ...<Widget>[
                AnimatedBuilder(
                  animation: loop,
                  builder: (context, _) => _Bars(t: loop.value, color: color),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < 4; i++)
            Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
              child: Container(
                width: 3,
                height: 3 + 9 * _wave(t * 4 - i * 0.1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EffectPainter extends CustomPainter {
  _EffectPainter({
    required this.spec,
    required this.t,
    required this.radius,
    required this.onRight,
  });

  final _Spec spec;
  final double t;
  final double radius;
  final bool onRight;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = radius;
    final color = spec.color;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (spec.effect) {
      case _Effect.none:
        break;
      case _Effect.dottedRing:
        stroke
          ..color = color
          ..strokeWidth = 2.5;
        final rect = Rect.fromCircle(center: c, radius: r + 5);
        const dashes = 18;
        for (var i = 0; i < dashes; i++) {
          final start = t * 2 * math.pi + i * 2 * math.pi / dashes;
          canvas.drawArc(rect, start, math.pi / dashes * 0.55, false, stroke);
        }
      case _Effect.ripple:
        for (var k = 0; k < 2; k++) {
          final p = _frac(t * 2 + k * 0.5);
          stroke
            ..color = color.withValues(alpha: 0.75 * (1 - p))
            ..strokeWidth = 2.5;
          canvas.drawCircle(c, r * (1 + 0.6 * p), stroke);
        }
      case _Effect.colorRing:
        final rect = Rect.fromCircle(center: c, radius: r + 4);
        stroke
          ..strokeWidth = 4
          ..shader = SweepGradient(
            colors: <Color>[_teal, _blue, color, _teal],
            transform: GradientRotation(t * 2 * math.pi),
          ).createShader(rect);
        canvas.drawCircle(c, r + 4, stroke);
      case _Effect.orbit:
        const alphas = <double>[1, 0.7, 0.45];
        for (var i = 0; i < 3; i++) {
          final a = t * 4 * math.pi + i * 2 * math.pi / 3;
          final p = c + Offset(math.sin(a), -math.cos(a)) * (r + 6.5);
          canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
          canvas.drawCircle(
            p,
            3,
            Paint()..color = color.withValues(alpha: alphas[i]),
          );
        }
      case _Effect.arc:
        stroke
          ..color = color
          ..strokeWidth = 3;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r + 5),
          t * 6 * math.pi,
          math.pi,
          false,
          stroke,
        );
    }

    if (spec.ears) {
      for (var side = -1; side <= 1; side += 2) {
        for (var k = 0; k < 2; k++) {
          final alpha = 0.25 + 0.75 * _wave(t * 3 - k * 0.2);
          stroke
            ..shader = null
            ..color = color.withValues(alpha: alpha)
            ..strokeWidth = 2.5;
          final arcRadius = 7.0 + k * 5;
          final center = c + Offset(side * (r - 4.0), -2);
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: arcRadius),
            side > 0 ? -math.pi / 4 : math.pi * 3 / 4,
            math.pi / 2,
            false,
            stroke,
          );
        }
      }
    }

    if (spec.notes) {
      const glyphs = <String>['♪', '♫', '♪'];
      const drift = <double>[-18, 14, -6];
      for (var i = 0; i < 3; i++) {
        final p = _frac(t * 2 + i / 3);
        final opacity = p < 0.2 ? p / 0.2 : 1 - (p - 0.2) / 0.8;
        final painter = TextPainter(
          text: TextSpan(
            text: glyphs[i],
            style: TextStyle(
              fontSize: 13 + 3 * p,
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: opacity.clamp(0, 1)),
              shadows: <Shadow>[
                Shadow(
                  color: Colors.white.withValues(alpha: opacity.clamp(0, 1)),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, c + Offset(drift[i] * p - 4, -r - 4 - 26 * p));
        painter.dispose();
      }
    }

    if (spec.sweat) {
      final p = _frac(t * 2);
      final opacity = p < 0.2 ? p / 0.2 : 1 - p;
      final x = c.dx + (onRight ? -1 : 1) * r * 0.58;
      final y = c.dy - r * 0.62 + 12 * p;
      final drop = Path()
        ..moveTo(x, y - 6)
        ..quadraticBezierTo(x + 5, y + 1, x, y + 5)
        ..quadraticBezierTo(x - 5, y + 1, x, y - 6)
        ..close();
      canvas.drawPath(
        drop,
        Paint()..color = const Color(0xFF5AA9E6).withValues(alpha: opacity),
      );
      canvas.drawPath(
        drop,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter old) =>
      old.t != t || old.spec != spec || old.onRight != onRight;
}
