import 'dart:math' as math;

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assistant speech is boosted above authored lesson audio', () {
    expect(androidSpeechBoostDb, 8.0);
    expect(androidAssistantSpeechBoostDb, 12.0);
    expect(androidAssistantSpeechBoostDb, greaterThan(androidSpeechBoostDb));
  });

  test(
    'child recording target gains 80 percent without the old 24 dB clamp',
    () {
      const previousGainDb = 23.480625354554377;
      final expectedGainDb = previousGainDb + 20 * math.log(1.8) / math.ln10;

      expect(lessonRecordingPlaybackGainDb, closeTo(expectedGainDb, 1e-12));
      expect(
        lessonRecordingPlaybackGainDb,
        lessThanOrEqualTo(androidMaxPlaybackGainDb),
      );
    },
  );
}
