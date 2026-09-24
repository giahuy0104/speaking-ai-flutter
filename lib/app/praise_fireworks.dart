import 'package:flutter/material.dart';

import '../l10n/display_language.dart';
import 'app_theme.dart';

class PraiseFireworks extends StatefulWidget {
  const PraiseFireworks({required this.keyPrefix, super.key});

  final String keyPrefix;

  @override
  State<PraiseFireworks> createState() => _PraiseFireworksState();
}

class _PraiseFireworksState extends State<PraiseFireworks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: Key(widget.keyPrefix),
      liveRegion: true,
      label: context.tr('Bạn làm tuyệt lắm!', '你做得太棒了！'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final leftProgress = _controller.value;
              final rightProgress = (_controller.value + 0.18) % 1.0;
              final top = constraints.maxHeight * 0.28;
              return Stack(
                children: <Widget>[
                  Positioned(
                    key: Key('${widget.keyPrefix}-left'),
                    left: 6,
                    top: top,
                    child: _PraiseFireworkBurst(
                      progress: leftProgress,
                      flipHorizontally: false,
                    ),
                  ),
                  Positioned(
                    key: Key('${widget.keyPrefix}-right'),
                    right: 6,
                    top: top,
                    child: _PraiseFireworkBurst(
                      progress: rightProgress,
                      flipHorizontally: true,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PraiseFireworkBurst extends StatelessWidget {
  const _PraiseFireworkBurst({
    required this.progress,
    required this.flipHorizontally,
  });

  final double progress;
  final bool flipHorizontally;

  @override
  Widget build(BuildContext context) {
    final rise = Curves.easeOutCubic.transform(progress);
    final fade = (1 - ((progress - 0.7) / 0.3)).clamp(0.0, 1.0).toDouble();
    final scale = 0.72 + (Curves.easeOutBack.transform(progress) * 0.34);
    return Transform.translate(
      offset: Offset(0, 70 - (rise * 132)),
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: scale,
          child: Transform.flip(
            flipX: flipHorizontally,
            child: const SizedBox(
              width: 104,
              height: 168,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 28,
                    bottom: 8,
                    child: Icon(
                      Icons.celebration_rounded,
                      color: Color(0xFFFFB84D),
                      size: 48,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 54,
                    child: Icon(
                      Icons.star_rounded,
                      color: AppColors.periwinkle,
                      size: 30,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 34,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.coral,
                      size: 28,
                    ),
                  ),
                  Positioned(
                    left: 39,
                    top: 2,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFFC75B),
                      size: 25,
                    ),
                  ),
                  Positioned(
                    right: 17,
                    top: 82,
                    child: Icon(
                      Icons.star_rounded,
                      color: AppColors.indigo,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
