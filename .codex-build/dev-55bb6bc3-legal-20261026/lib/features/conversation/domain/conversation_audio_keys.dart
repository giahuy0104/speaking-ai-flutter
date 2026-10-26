import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class ConversationAudioKeys {
  static const englishVoiceProfile = 'Nhs7eitvQWFTQBsf0yiT|eleven_v3|0.75';
  static const vietnameseVoiceProfile = '5CVDNcIPiOYgRUQuxXd7|eleven_v3|0.9';

  static const notHeard = 'assistant.conversation.not_heard.vi';
  static const repeat = 'assistant.conversation.repeat.vi';
  static const connectionFailed = 'assistant.conversation.connection_failed.vi';
  static const conversationStopped = 'assistant.conversation.stopped.vi';
  static const translationStopped = 'assistant.translation.stopped.vi';
  static const recoveryError = 'assistant.conversation.recovery_error.vi';

  static String? fixedKeyForText(String text) => switch (text.trim()) {
    'Không nghe rõ.' => notHeard,
    'HOMI chưa nghe thấy bạn nói. Bạn nói lại nhé.' => notHeard,
    'HOMI chưa nghe rõ. Bạn nói lại nhé.' => notHeard,
    'Hãy nói lại.' => repeat,
    'Không kết nối được.' => connectionFailed,
    'Hội thoại đã dừng.' => conversationStopped,
    'Dịch đã dừng.' => translationStopped,
    'HOMI đang gặp lỗi. Bạn thử lại nhé.' => recoveryError,
    // Existing navigation copy remains backed by assistant-core.
    'Đã dừng.' => 'assistant.main.translation_stopped.vi',
    _ => null,
  };

  static String dynamic({
    required String text,
    required String locale,
    required String voiceProfile,
  }) {
    final normalized = text.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return sha256
        .convert(utf8.encode('$locale\u0000$voiceProfile\u0000$normalized'))
        .toString();
  }
}
