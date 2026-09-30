import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android fallbacks keep separate bounds for prompts and H20 captures',
    () {
      expect(androidAssistantSpeechBoostDb, androidSpeechBoostDb);
      expect(androidSpeechBoostDb, inInclusiveRange(0.0, 8.0));
      expect(androidSpeechBoostDb, lessThanOrEqualTo(androidMaxPlaybackGainDb));
      // Android lesson WAVs are loudness-normalized when saved, so an
      // unmeasured replay must not add the full H20 boost on top.
      expect(lessonRecordingPlaybackGainDb, 0.0);
      expect(androidMaxPlaybackGainDb, 28.0);
    },
  );

  test('iOS attenuates synthesised speech instead of boosting it', () {
    // AVSpeechUtterance.volume cannot exceed 1.0, so a positive number here
    // would silently do nothing - which is exactly how the gap survived.
    expect(iosAssistantSpeechGainDb, lessThan(0));
    // Measured range for the compact voices was -3.7 to -6.5 dB.
    expect(iosAssistantSpeechGainDb, inInclusiveRange(-6.5, -3.7));
  });
}
