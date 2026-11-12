import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/mascot_assets.dart';

/// What HOMI is doing on the translation screen.
enum HomiHeroMood { idle, listening, speaking }

/// HOMI on its cloud, gently turning in 3D so it never looks frozen.
///
/// HOMI itself plays a short animated WebP per mood. Idle: waves, blinks and
/// breathes. Listening: sways with headphones among ripples and music notes.
/// Speaking: talks into the mic while letters fly out of its beak.
///
/// Built to stay cool on long sessions: motion runs on a 30 fps timer, so
/// the screen redraws at most 30 times a second; idle motion rests after a
/// while (a tap wakes it) and HOMI then shows a still pose; only the visible
/// pose is animated, still parts are painted once and images are decoded at
/// the size they are shown.
class HomiHero3D extends StatefulWidget {
  const HomiHero3D({
    required this.mood,
    this.size = const Size(220, 150),
    super.key,
  });

  /// Width over height of the cloud stage.
  static const double aspectRatio = 1.47;

  /// Share of the stage width the cloud itself covers; halo and sparkles
  /// fill the rest.
  static const double cloudWidthFactor = 0.84;

  /// Tests turn this off so `pumpAndSettle` is not held by the endless loop.
  static bool motionEnabled = true;

  /// Tests turn this off: resized decoding finishes outside the fake clock,
  /// so goldens would miss the images.
  static bool decodeAtDisplaySize = true;

  final HomiHeroMood mood;
  final Size size;

  @override
  State<HomiHero3D> createState() => _HomiHero3DState();
}

class _HomiHero3DState extends State<HomiHero3D> {
  /// One loop drives every motion; each effect runs a whole number of times
  /// per loop so nothing jumps when it restarts.
  static const _loop = Duration(milliseconds: 8400);

  /// Time between motion frames (about 30 fps).
  static const _frameGap = Duration(milliseconds: 33);

  /// Idle HOMI moves for this long after waking, then rests at a loop end.
  static const _idleAwake = Duration(seconds: 20);

  /// Runs only while HOMI moves; null while it rests.
  Timer? _timer;

  /// Position in the loop, 0..1.
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Duration _shown = Duration.zero;
  Duration? _restAt;
  bool _canAnimate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final canAnimate =
        HomiHero3D.motionEnabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    // Other dependency changes (theme, size) must not wake a resting HOMI.
    if (canAnimate == _canAnimate) return;
    _canAnimate = canAnimate;
    canAnimate ? _wake() : _rest();
  }

  @override
  void didUpdateWidget(covariant HomiHero3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _wake();
  }

  /// Starts (or keeps) the motion; idle HOMI gets a fresh awake window.
  void _wake() {
    if (!_canAnimate) return;
    if (_timer == null) {
      _shown = Duration.zero;
      _timer = Timer.periodic(_frameGap, (_) => _onTick());
    }
    _restAt = widget.mood == HomiHeroMood.idle ? _shown + _idleAwake : null;
  }

  void _rest() {
    _timer?.cancel();
    _timer = null;
    _phase.value = 0;
  }

  void _onTick() {
    final elapsed = _shown + _frameGap;
    final loopMicros = _loop.inMicroseconds;
    final crossedLoopEnd =
        elapsed.inMicroseconds ~/ loopMicros !=
        _shown.inMicroseconds ~/ loopMicros;
    _shown = elapsed;
    // Rest only at a loop end, where every effect is back at its start.
    final restAt = _restAt;
    if (restAt != null && elapsed >= restAt && crossedLoopEnd) {
      // Rebuild so HOMI swaps its animated pose for the still one.
      setState(_rest);
      return;
    }
    _phase.value = (elapsed.inMicroseconds % loopMicros) / loopMicros;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  ImageProvider _image(String asset, double logicalWidth) {
    final provider = AssetImage(asset);
    if (!HomiHero3D.decodeAtDisplaySize) return provider;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(provider, width: (logicalWidth * dpr).round());
  }

  static String _stillPose(HomiHeroMood mood) => switch (mood) {
    HomiHeroMood.idle => MascotAssets.wave,
    HomiHeroMood.listening => MascotAssets.listen,
    HomiHeroMood.speaking => MascotAssets.speak,
  };

  static String _animatedPose(HomiHeroMood mood) => switch (mood) {
    HomiHeroMood.idle => MascotAssets.waveAnimated,
    HomiHeroMood.listening => MascotAssets.listenAnimated,
    HomiHeroMood.speaking => MascotAssets.speakAnimated,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = widget.size;
    final mood = widget.mood;
    final moving = _timer != null;
    final mascotSize = size.height * 0.79;
    final cloudWidth = size.width * HomiHero3D.cloudWidthFactor;

    // Built once per mood change; the loop below only moves them.
    final cloud = RepaintBoundary(
      child: Opacity(
        opacity: isDark ? 0.35 : 1,
        child: Image(
          image: _image(MascotAssets.heroCloud, cloudWidth),
          width: cloudWidth,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
      ),
    );
    final mascot = RepaintBoundary(
      child: SizedBox.square(
        dimension: mascotSize,
        child: Stack(
          children: <Widget>[
            for (final pose in HomiHeroMood.values)
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 260),
                  opacity: pose == mood ? 1 : 0,
                  child: Image(
                    // Only the shown pose plays; hidden ones stay still.
                    image: _image(
                      pose == mood && moving
                          ? _animatedPose(pose)
                          : _stillPose(pose),
                      mascotSize,
                    ),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return GestureDetector(
      // A tap makes resting HOMI move again.
      onTap: () => setState(_wake),
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: RepaintBoundary(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: isDark ? 0.08 : 0.9),
                        const Color(
                          0xFFD6ECFF,
                        ).withValues(alpha: isDark ? 0.05 : 0.6),
                        const Color(0x00D6ECFF),
                      ],
                      stops: const <double>[0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _phase,
                  builder: (context, t, _) =>
                      _scene(t, size, mood, mascotSize, cloud, mascot),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scene(
    double t,
    Size size,
    HomiHeroMood mood,
    double mascotSize,
    Widget cloud,
    Widget mascot,
  ) {
    final rotY = math.sin(t * 2 * math.pi) * 0.24;
    final rotX = math.cos(t * 2 * math.pi) * 0.07;
    final cloudLift = math.sin(t * 4 * math.pi) * 4;

    Widget layer(double depth, Widget child) => Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0019)
        ..rotateX(rotX)
        ..rotateY(rotY)
        ..translateByDouble(0, 0, -depth, 1),
      child: child,
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        Positioned(
          bottom: -4,
          child: _GroundShadow(
            scale: 1 - (cloudLift + 4) / 8 * 0.14,
            width: size.width * 0.58,
          ),
        ),
        layer(
          0,
          Transform.translate(offset: Offset(0, -cloudLift), child: cloud),
        ),
        if (mood == HomiHeroMood.listening)
          layer(
            10,
            CustomPaint(
              size: size,
              painter: _RipplePainter(t: t),
            ),
          ),
        Positioned(bottom: 4, child: layer(42, mascot)),
        if (mood == HomiHeroMood.listening)
          Positioned.fill(
            child: layer(60, CustomPaint(painter: _NotesPainter(t: t))),
          ),
        if (mood == HomiHeroMood.speaking)
          Positioned.fill(
            child: layer(
              60,
              CustomPaint(
                painter: _WordsPainter(t: t, mascotSize: mascotSize),
              ),
            ),
          ),
        Positioned.fill(
          child: layer(30, CustomPaint(painter: _SparkPainter(t: t))),
        ),
      ],
    );
  }
}

double _frac(double x) => x - x.floorToDouble();

/// 0 → 1 quickly, then back to 0: how bright a flying glyph is along its way.
double _fade(double p, double rise) =>
    (p < rise ? p / rise : 1 - (p - rise) / (1 - rise)).clamp(0.0, 1.0);

/// Laid-out glyphs shared by every frame, so painting never builds text.
///
/// Fading is baked into the glyph colour in ten steps, so painting needs no
/// extra compositing layer.
abstract final class _Glyphs {
  static const _fadeSteps = 10;

  static final Map<(String, int, int), TextPainter> _cache =
      <(String, int, int), TextPainter>{};

  /// Paints [text] centred on [center], scaled, turned and faded; it is laid
  /// out once at [baseFontSize] per fade step.
  static void paint(
    Canvas canvas,
    String text,
    Color color,
    double baseFontSize, {
    required Offset center,
    required double scale,
    required double turn,
    required double opacity,
  }) {
    final step = (opacity * _fadeSteps).round();
    if (step <= 0) return;
    final painter = _cache.putIfAbsent((text, color.toARGB32(), step), () {
      final alpha = step / _fadeSteps;
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: baseFontSize,
            fontWeight: FontWeight.w900,
            color: color.withValues(alpha: alpha),
            shadows: <Shadow>[
              Shadow(
                color: Colors.white.withValues(alpha: alpha),
                offset: const Offset(0, 2),
              ),
              Shadow(
                color: Colors.white.withValues(alpha: alpha),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(turn)
      ..scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
}

class _GroundShadow extends StatelessWidget {
  const _GroundShadow({required this.scale, required this.width});

  final double scale;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: scale,
      child: Container(
        width: width,
        height: 15,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.elliptical(80, 8)),
          gradient: RadialGradient(
            colors: <Color>[Color(0x3D0F2A63), Color(0x000F2A63)],
          ),
        ),
      ),
    );
  }
}

/// Listening ripples spreading from the cloud.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.t});

  final double t;

  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.56);
    final base = Size(size.width * 0.68, size.height * 0.72);
    for (var k = 0; k < 2; k++) {
      final p = _frac(t * 5 + k * 0.5);
      final scale = 0.7 + p * 0.65;
      _stroke.color = const Color(0xFF21C2A8).withValues(alpha: 0.6 * (1 - p));
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: base.width * scale,
          height: base.height * scale,
        ),
        _stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}

/// Speaking: letters pop out of HOMI's beak and float up to the right.
class _WordsPainter extends CustomPainter {
  _WordsPainter({required this.t, required this.mascotSize});

  final double t;
  final double mascotSize;

  static const _glyphs = <String>['A', 'b', '♪', 'Hi'];
  static const _colors = <Color>[
    Color(0xFF3D63C9),
    Color(0xFF16B995),
    Color(0xFFE23D5B),
    Color(0xFFFFB627),
  ];
  // Flight per glyph at a 118 px tall HOMI: end offset, turn, font size.
  static const _flight = <(double, double, double, double)>[
    (60, -64, -0.2, 26),
    (90, -22, 0.24, 22),
    (34, -94, 0.14, 24),
    (98, -54, -0.1, 21),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // The beak in the speaking pose sits at about 47% across and 35% down
    // the mascot image, which stands centred on the stage's bottom.
    final scale = mascotSize / 118;
    final beak = Offset(
      (size.width - mascotSize) / 2 + mascotSize * 0.47,
      size.height - 4 - mascotSize + mascotSize * 0.35,
    );
    for (var i = 0; i < _glyphs.length; i++) {
      // Five flights per loop, each glyph a quarter of a flight apart.
      final p = _frac(t * 5 + i / _glyphs.length);
      final (dx, dy, turn, fontSize) = _flight[i];
      _Glyphs.paint(
        canvas,
        _glyphs[i],
        _colors[i],
        fontSize,
        center: beak + Offset(dx, dy) * (scale * p),
        scale: scale * (0.55 + 0.55 * p),
        turn: turn * p,
        opacity: _fade(p, 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(_WordsPainter old) =>
      old.t != t || old.mascotSize != mascotSize;
}

/// Listening: music notes drifting up from HOMI's headphones.
class _NotesPainter extends CustomPainter {
  _NotesPainter({required this.t});

  final double t;

  static const _glyphs = <String>['♪', '♫', '♪'];
  static const _drift = <double>[-34, 30, -6];
  static const _startX = <double>[-10, 6, 0];
  static const _color = Color(0xFF21C2A8);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _glyphs.length; i++) {
      final p = _frac(t * 4 + i / _glyphs.length);
      _Glyphs.paint(
        canvas,
        _glyphs[i],
        _color,
        15,
        center: Offset(
          size.width / 2 + _startX[i] + _drift[i] * p,
          size.height * 0.12 - 46 * p,
        ),
        scale: 1 + p * 0.2,
        turn: 0,
        opacity: _fade(p, 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(_NotesPainter old) => old.t != t;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.t});

  final double t;

  static const _spots = <Offset>[
    Offset(0.08, 0.22),
    Offset(0.92, 0.08),
    Offset(0.86, 0.78),
  ];

  static final Paint _paint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _spots.length; i++) {
      final wave = 0.5 + 0.5 * math.sin((t * 3 + i / 3) * 2 * math.pi);
      final arm = 2 + wave * 4;
      _paint.color = const Color(
        0xFFFFCF4A,
      ).withValues(alpha: 0.25 + 0.75 * wave);
      final c = Offset(size.width * _spots[i].dx, size.height * _spots[i].dy);
      canvas
        ..drawLine(c.translate(-arm, 0), c.translate(arm, 0), _paint)
        ..drawLine(c.translate(0, -arm), c.translate(0, arm), _paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
