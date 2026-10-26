import 'package:flutter/material.dart';

import '../core/device/homi_connection_state.dart';
import '../l10n/display_language.dart';

/// User-facing status for the independently connected microphone and MAIN.
/// Does not infer that a retry is running merely because a link is missing.
enum HomiConnectionPresentation {
  ready,
  mainUnavailable,
  microphoneUnavailable,
  microphoneMismatch,
  disconnected;

  static HomiConnectionPresentation from(
    HomiConnectionState? state, {
    required bool isReady,
  }) {
    if (state == null) return isReady ? ready : disconnected;
    if (state.isHomiReady) return ready;
    if (state.hfpReady && state.bleReady) return microphoneMismatch;
    if (state.hfpReady) return mainUnavailable;
    if (state.bleReady) return microphoneUnavailable;
    return disconnected;
  }

  bool get isPartial => this != ready && this != disconnected;

  Color partialColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFFD180)
      : const Color(0xFF946200);

  String label(BuildContext context) => switch (this) {
    ready => context.tr('Sẵn sàng', '已就绪'),
    mainUnavailable => context.tr('Mất kết nối MAIN', 'MAIN 未连接'),
    microphoneUnavailable => context.tr('Mic chưa kết nối', '麦克风未连接'),
    microphoneMismatch => context.tr('Cần kiểm tra mic', '请检查麦克风'),
    disconnected => context.tr('Chưa kết nối', '未连接'),
  };

  String? detail(BuildContext context) => switch (this) {
    mainUnavailable => context.tr(
      'Mic vẫn kết nối. Nút MAIN trên thiết bị tạm thời chưa dùng được.',
      '麦克风仍已连接，设备上的 MAIN 按钮暂时无法使用。',
    ),
    microphoneUnavailable => context.tr(
      'Nút MAIN đã kết nối. Cần kết nối mic của HOMI để nói chuyện.',
      'MAIN 按钮已连接。请连接 HOMI 麦克风后再开始对话。',
    ),
    microphoneMismatch => context.tr(
      'Mic đang chọn chưa được xác nhận thuộc HOMI. Kiểm tra mic trong Cài đặt.',
      '尚未确认所选麦克风属于 HOMI，请在设置中检查麦克风。',
    ),
    ready || disconnected => null,
  };
}

/// A non-modal explanation: an interrupted control link never hides controls
/// for a speaking session which can still be using the connected microphone.
class HomiConnectionNotice extends StatelessWidget {
  const HomiConnectionNotice({required this.status, super.key});

  final HomiConnectionPresentation status;

  @override
  Widget build(BuildContext context) {
    final detail = status.detail(context);
    if (detail == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = status.partialColor(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Semantics(
            liveRegion: true,
            child: Container(
              key: const Key('homi-partial-connection-notice'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF453619)
                    : const Color(0xFFFFF2D3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.info_outline_rounded, size: 20, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: foreground),
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
