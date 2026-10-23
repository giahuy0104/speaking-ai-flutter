import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({required this.result, required this.onPlay, super.key});

  final ConversationResult? result;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final currentResult = result;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _TranslationSection(
          key: const Key('conversation-vietnamese-bubble'),
          icon: Icons.chat_bubble_rounded,
          label: context.tr('Câu tiếng Việt', '越南语句子'),
          text: currentResult?.vietnameseText,
          placeholder: context.tr('Câu bạn nói sẽ hiện ở đây', '你说的句子会显示在这里'),
        ),
        const SizedBox(height: 14),
        _TranslationSection(
          key: const Key('conversation-english-bubble'),
          isEnglish: true,
          icon: Icons.translate_rounded,
          label: context.tr('Câu tiếng Anh', '英语句子'),
          text: currentResult?.englishText,
          placeholder: context.tr('Bản dịch sẽ hiện ở đây', '译文会显示在这里'),
          trailing: currentResult?.audioUri == null
              ? null
              : Semantics(
                  button: true,
                  label: context.tr('Phát lại câu tiếng Anh', '重新播放英语句子'),
                  child: IconButton(
                    key: const Key('conversation-replay-result'),
                    onPressed: onPlay,
                    tooltip: context.tr('Phát tiếng Anh', '播放英语'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(44),
                      backgroundColor: AppColors.indigo,
                      foregroundColor: Colors.white,
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TranslationSection extends StatelessWidget {
  const _TranslationSection({
    required this.icon,
    required this.label,
    required this.text,
    required this.placeholder,
    this.isEnglish = false,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? text;
  final String placeholder;
  final bool isEnglish;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasText = text?.trim().isNotEmpty ?? false;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? isEnglish
              ? const Color(0xFF123F3C)
              : AppColors.darkSurfaceRaised
        : isEnglish
        ? const Color(0xFFDDFBED)
        : Colors.white;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return AnimatedContainer(
      duration: duration,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 110),
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 18),
      decoration: ShapeDecoration(
        color: fill,
        shape: _SpeechBubbleShape(tailOnRight: isEnglish),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.surfaceContainerHighest
                      : isEnglish
                      ? const Color(0xFFC8F7E5)
                      : const Color(0xFFEAF5FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: isDark ? colorScheme.primary : AppColors.primaryNavy,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isDark
                        ? colorScheme.onSurface
                        : AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: AnimatedSwitcher(
              duration: duration,
              child: Text(
                hasText ? text! : placeholder,
                key: ValueKey<String>(text ?? placeholder),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: hasText
                      ? isDark
                            ? colorScheme.onSurface
                            : AppColors.ink
                      : isDark
                      ? colorScheme.onSurfaceVariant
                      : const Color(0xFF5E6B82),
                  fontWeight: hasText ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard conversation-bubble surface. It grows with text instead of fixing
/// the height, including at large accessibility text sizes.
class _SpeechBubbleShape extends ShapeBorder {
  const _SpeechBubbleShape({required this.tailOnRight});

  final bool tailOnRight;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) => this;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Rect.fromLTRB(
      rect.left + (tailOnRight ? 0 : 8),
      rect.top,
      rect.right - (tailOnRight ? 8 : 0),
      rect.bottom,
    );
    final rounded = Path()
      ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(28)));
    final anchor = rect.top + 36;
    final tail = Path();
    if (tailOnRight) {
      tail
        ..moveTo(body.right - 3, anchor - 8)
        ..quadraticBezierTo(
          rect.right + 3,
          anchor - 9,
          rect.right - 1,
          anchor - 3,
        )
        ..quadraticBezierTo(
          rect.right - 4,
          anchor + 4,
          body.right - 4,
          anchor + 12,
        )
        ..close();
    } else {
      tail
        ..moveTo(body.left + 3, anchor - 8)
        ..quadraticBezierTo(
          rect.left - 3,
          anchor - 9,
          rect.left + 1,
          anchor - 3,
        )
        ..quadraticBezierTo(
          rect.left + 4,
          anchor + 4,
          body.left + 4,
          anchor + 12,
        )
        ..close();
    }
    return Path.combine(PathOperation.union, rounded, tail);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
