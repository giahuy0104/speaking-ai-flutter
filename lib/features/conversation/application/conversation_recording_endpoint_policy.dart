/// Trailing silence for live translation, separate from lesson scoring windows.
abstract final class ConversationRecordingEndpointPolicy {
  static Duration quietWindow(String transcript, {required int baseSilenceMs}) {
    final words = transcript.trim().split(RegExp(r'\s+')).length;
    final adjustment = words == 1
        ? -300
        : words <= 4
        ? -200
        : words <= 8
        ? -100
        : 0;
    return Duration(
      milliseconds: (baseSilenceMs + adjustment).clamp(400, 700).toInt(),
    );
  }
}
