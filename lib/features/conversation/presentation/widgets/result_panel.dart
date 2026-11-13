import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

/// Study card: what the child said in Vietnamese (small, on top) and the
/// translation (large, the part to learn) underneath.
class ResultPanel extends StatelessWidget {
  /// Card height not given to the two sections: 14 + 16 px card padding and
  /// the 40 px divider row.
  static const double _cardChrome = 70;

  const ResultPanel({
    required this.result,
    required this.onPlay,
    this.outputLanguage = TranslationOutputLanguage.english,
    this.sectionMinHeight = 110,
    this.minCardHeight = 0,
    super.key,
  });

  final ConversationResult? result;
  final VoidCallback onPlay;
  final TranslationOutputLanguage outputLanguage;

  /// Minimum height of the translation part, so the card keeps its shape
  /// before the first sentence arrives.
  final double sectionMinHeight;

  /// Minimum height of the whole card; phones stretch it down to the main
  /// action so long sentences have room.
  final double minCardHeight;

  @override
  Widget build(BuildContext context) {
    final currentResult = result;
    final language = currentResult?.outputLanguage ?? outputLanguage;
    final vietnameseLanguageName = language.label.replaceFirst(
      'Tiếng',
      'tiếng',
    );
    final chineseLanguageName = switch (language) {
      TranslationOutputLanguage.english => '英语',
      TranslationOutputLanguage.chinese => '中文',
      TranslationOutputLanguage.japanese => '日语',
      TranslationOutputLanguage.korean => '韩语',
      TranslationOutputLanguage.french => '法语',
    };
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final canReplay =
        currentResult != null &&
        (currentResult.audioUri != null ||
            currentResult.audioSource == 'device_tts');
    final translation = currentResult?.displayedTranslation;
    // When the card is stretched, Vietnamese and translation share it evenly.
    final halfHeight = minCardHeight > 0
        ? (minCardHeight - _cardChrome) / 2
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const <Color>[
                      AppColors.darkSurfaceRaised,
                      Color(0xFF123F3C),
                    ]
                  : const <Color>[
                      Colors.white,
                      Colors.white,
                      Color(0xFFEDF9F3),
                      Color(0xFFD3F0E3),
                    ],
              stops: isDark ? null : const <double>[0, 0.3, 0.58, 1],
            ),
            border: Border.all(
              color: isDark ? AppColors.darkOutline : Colors.white,
              width: 1.5,
            ),
            boxShadow: isDark
                ? null
                : const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x14146B4A),
                      blurRadius: 2,
                      offset: Offset(0, 2),
                    ),
                    BoxShadow(
                      color: Color(0x170F2A63),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minCardHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Section(
                    key: const Key('conversation-vietnamese-bubble'),
                    code: 'VI',
                    isSource: true,
                    minHeight: halfHeight,
                    label: context.tr('Câu tiếng Việt', '越南语句子'),
                    text: currentResult?.vietnameseText,
                    placeholder: context.tr(
                      'Câu bạn nói sẽ hiện ở đây',
                      '你说的句子会显示在这里',
                    ),
                  ),
                  const _Divider(),
                  _Section(
                    key: const Key('conversation-english-bubble'),
                    code: language.badge,
                    minHeight: math.max(sectionMinHeight, halfHeight),
                    label: context.tr(
                      'Câu $vietnameseLanguageName',
                      '$chineseLanguageName句子',
                    ),
                    text: translation,
                    placeholder: context.tr(
                      'Bản dịch sẽ hiện ở đây',
                      '译文会显示在这里',
                    ),
                    trailing: !canReplay
                        ? null
                        : Semantics(
                            button: true,
                            label: context.tr(
                              'Phát lại câu $vietnameseLanguageName',
                              '重新播放$chineseLanguageName句子',
                            ),
                            child: IconButton(
                              key: const Key('conversation-replay-result'),
                              onPressed: onPlay,
                              tooltip: context.tr(
                                'Phát $vietnameseLanguageName',
                                '播放$chineseLanguageName',
                              ),
                              icon: const Icon(
                                Icons.volume_up_rounded,
                                size: 20,
                              ),
                              style: IconButton.styleFrom(
                                minimumSize: const Size.square(44),
                                backgroundColor: isDark
                                    ? colorScheme.surfaceContainerHighest
                                    : Colors.white,
                                foregroundColor: isDark
                                    ? colorScheme.primary
                                    : AppColors.primaryNavy,
                                elevation: 2,
                                shadowColor: const Color(0x330F2A63),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (currentResult?.textSource ==
            'mlkit_on_device_translation') ...<Widget>[
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Bản dịch tự động • Powered by Google Translate',
              key: const Key('google-translate-attribution'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.code,
    required this.label,
    required this.text,
    required this.placeholder,
    this.isSource = false,
    this.minHeight = 0,
    this.trailing,
    super.key,
  });

  final String code;
  final String label;
  final String? text;
  final String placeholder;
  final bool isSource;
  final double minHeight;
  final Widget? trailing;

  /// Short sentences read big; long ones shrink so they still fit their half.
  /// The translation stays a step larger than the Vietnamese source.
  static double _fontSize(String text, {required bool isSource}) {
    final length = text.characters.length;
    if (length <= 30) return isSource ? 21 : 26;
    if (length <= 70) return isSource ? 19 : 22;
    if (length <= 120) return isSource ? 17 : 19;
    return isSource ? 16 : 17;
  }

  @override
  Widget build(BuildContext context) {
    final hasText = text?.trim().isNotEmpty ?? false;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final navy = isDark ? colorScheme.onSurface : AppColors.primaryNavy;
    final accent = isSource
        ? (isDark ? AppColors.darkPink : AppColors.accentPink)
        : (isDark ? AppColors.darkMint : AppColors.success);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final textStyle = !hasText
        ? theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? colorScheme.onSurfaceVariant : AppColors.muted,
            fontWeight: FontWeight.w500,
          )
        : isSource
        ? theme.textTheme.bodyMedium?.copyWith(
            color: isDark
                ? colorScheme.onSurfaceVariant
                : const Color(0xFF4A5572),
            fontSize: _fontSize(text!, isSource: true),
            height: 1.35,
            fontWeight: FontWeight.w600,
          )
        : theme.textTheme.titleLarge?.copyWith(
            color: navy,
            fontSize: _fontSize(text!, isSource: false),
            height: 1.28,
            fontWeight: FontWeight.w800,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 22,
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSource
                      ? (isDark
                            ? const Color(0xFF3A2430)
                            : const Color(0xFFFFF1F4))
                      : navy,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: isSource
                        ? accent
                        : (isDark ? AppColors.darkSurface : Colors.white),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isSource
                        ? (isDark
                              ? colorScheme.onSurfaceVariant
                              : AppColors.muted)
                        : accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: isSource ? 6 : 8),
          AnimatedSwitcher(
            duration: duration,
            child: Text(
              hasText ? text! : placeholder,
              key: ValueKey<String>(text ?? placeholder),
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.darkOutline : const Color(0xFFBFE3D3);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(child: CustomPaint(painter: _DashPainter(color))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 16,
              color: isDark ? AppColors.darkMint : AppColors.success,
            ),
          ),
          Expanded(child: CustomPaint(painter: _DashPainter(color))),
        ],
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(x + 3.5, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
