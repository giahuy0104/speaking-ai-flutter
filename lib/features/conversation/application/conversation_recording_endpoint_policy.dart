/// Trailing silence for live translation, separate from lesson scoring windows.
abstract final class ConversationRecordingEndpointPolicy {
  static Duration quietWindow(String transcript, {required int baseSilenceMs}) {
    final words = transcript.trim().split(RegExp(r'\s+')).length;
    final adjustment = words == 1
        ? -200
        : words <= 4
        ? -100
        : words <= 8
        ? 0
        : 100;
    return Duration(
      milliseconds: (baseSilenceMs + adjustment).clamp(400, 900).toInt(),
    );
  }
}
