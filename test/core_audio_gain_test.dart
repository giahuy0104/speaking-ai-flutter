import 'dart:math' as math;

import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'child recording playback is 50 percent louder than its former level',
    () {
      const previousGainDb = 12.0;
      final expectedGainDb = previousGainDb + 20 * math.log(1.5) / math.ln10;

      expect(lessonRecordingPlaybackGainDb, closeTo(expectedGainDb, 1e-12));
      expect(lessonRecordingPlaybackGainDb, lessThan(androidMaxPlaybackGainDb));
    },
  );
}
