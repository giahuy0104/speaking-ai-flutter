import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unmeasurable sources share one bounded Android fallback', () {
    expect(androidAssistantSpeechBoostDb, androidSpeechBoostDb);
    expect(lessonRecordingPlaybackGainDb, androidSpeechBoostDb);
    expect(androidSpeechBoostDb, inInclusiveRange(0.0, 8.0));
    expect(androidSpeechBoostDb, lessThanOrEqualTo(androidMaxPlaybackGainDb));
    expect(androidMaxPlaybackGainDb, lessThanOrEqualTo(12.0));
  });
}
