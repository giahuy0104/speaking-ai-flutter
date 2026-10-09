import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_audio_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps authored conversation phrases into assistant-core', () {
    expect(
      ConversationAudioKeys.fixedKeyForText('Không nghe rõ.'),
      ConversationAudioKeys.notHeard,
    );
    expect(
      ConversationAudioKeys.fixedKeyForText('Dịch đã dừng.'),
      ConversationAudioKeys.translationStopped,
    );
    expect(
      ConversationAudioKeys.fixedKeyForText('A dynamic child response'),
      isNull,
    );
  });

  test('dynamic cache key normalizes case and whitespace', () {
    final first = ConversationAudioKeys.dynamic(
      text: '  I   NEED a pencil. ',
      locale: 'en-US',
      voiceProfile: ConversationAudioKeys.englishVoiceProfile,
    );
    final second = ConversationAudioKeys.dynamic(
      text: 'i need a pencil.',
      locale: 'en-US',
      voiceProfile: ConversationAudioKeys.englishVoiceProfile,
    );

    expect(first, hasLength(64));
    expect(first, second);
  });
}
