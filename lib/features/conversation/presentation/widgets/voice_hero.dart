import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../app/homi_ui.dart';
import '../../../../app/mascot_assets.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

const _homeHeroBlobAsset = 'assets/images/home-hero-blob-option2.png';

class VoiceHero extends StatelessWidget {
  const VoiceHero({
    required this.phase,
    required this.processingStage,
    required this.amplitude,
    this.isPreparingMicrophone = false,
    this.needsDeviceConnection = false,
    required this.onStop,
    super.key,
  });

  final ConversationPhase phase;
  final ConversationProcessingStage processingStage;
  final double amplitude;
  final bool isPreparingMicrophone;
  final bool needsDeviceConnection;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRecording = phase == ConversationPhase.recording;
    final compact = MediaQuery.sizeOf(context).height < 900;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: compact ? 205 : 232,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Transform.scale(
                    scale: 1.32,
                    child: Opacity(
                      opacity: isDark ? 0.18 : 1,
                      child: Image.asset(
                        _homeHeroBlobAsset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
                AnimatedScale(
                  duration: motionDuration,
                  scale: isRecording ? 0.96 + (amplitude * 0.08) : 1,
                  child: Transform.scale(
                    scale: 1.12,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Image.asset(
                        MascotAssets.listen,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: compact ? 52 : 58,
            child: Center(
              child: HomiWaveform(
                key: Key(
                  isRecording ||
                          phase == ConversationPhase.processing ||
                          isPreparingMicrophone
                      ? 'conversation-animated-waveform'
                      : 'conversation-static-waveform',
                ),
                active:
                    isRecording ||
                    phase == ConversationPhase.processing ||
                    isPreparingMicrophone,
                amplitude: amplitude,
                width: compact ? 228 : 254,
                height: compact ? 44 : 50,
                semanticLabel: context.tr('Mức âm thanh', '音量'),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: compact ? 6 : 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24),
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _statusText(context),
                    key: const Key('conversation-wave-status'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? colorScheme.onSurfaceVariant
                          : AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      shadows: <Shadow>[
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 7,
                        ),
                        Shadow(
                          color: isDark ? Colors.black54 : Colors.white,
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (isPreparingMicrophone) {
      return context.tr('Đang chuẩn bị micro…', '正在准备麦克风…');
    }
    if (needsDeviceConnection &&
        (phase == ConversationPhase.idle ||
            phase == ConversationPhase.ready ||
            phase == ConversationPhase.error)) {
      return context.tr(
        'Kết nối với HOMI để bắt đầu sử dụng',
        '连接 HOMI 即可开始使用',
      );
    }
    return switch (phase) {
      ConversationPhase.idle => context.tr(
        'Bấm nút micro bên dưới để bắt đầu',
        '点击下方麦克风按钮开始',
      ),
      ConversationPhase.recording => context.tr('Mình đang nghe…', '正在聆听…'),
      ConversationPhase.processing => switch (processingStage) {
        ConversationProcessingStage.recognizing => context.tr(
          'Đang nhận giọng nói…',
          '正在识别语音…',
        ),
        ConversationProcessingStage.translating => context.tr(
          'Đang dịch…',
          '正在翻译…',
        ),
        ConversationProcessingStage.preparingAudio => context.tr(
          'Đang chuẩn bị âm thanh…',
          '正在准备语音…',
        ),
      },
      ConversationPhase.ready => context.tr(
        'Bấm “Nói câu mới” để tiếp tục',
        '点击“说新句子”继续',
      ),
      ConversationPhase.error => context.tr(
        'Bấm “Thử lại” khi bạn sẵn sàng',
        '准备好后点击“重试”',
      ),
    };
  }
}
