import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/adaptive_voice_activity_detector.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_endpoint_detector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ASR confirmation endpoints without RMS and renews on new words',
    (tester) async {
      final reasons = <LessonRecordingEndpointReason>[];
      final detector = LessonRecordingEndpointDetector();
      detector.start(amplitudeDbfs: null, onEndpoint: reasons.add);
      detector.confirmSpeech();
      expect(detector.speechDetected, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      detector.confirmSpeech();
      await tester.pump(const Duration(milliseconds: 699));
      expect(reasons, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reasons, <LessonRecordingEndpointReason>[
        LessonRecordingEndpointReason.silence,
      ]);
      detector.confirmSpeech();
      await tester.pump(const Duration(seconds: 6));
      expect(reasons, hasLength(1));
    },
  );

  testWidgets('keeps six seconds as the hard recording limit', (tester) async {
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector();

    detector.start(amplitudeDbfs: null, onEndpoint: reasons.add);
    await tester.pump(const Duration(milliseconds: 5999));
    expect(reasons, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.maximumDuration,
    ]);
  });

  testWidgets('stops after detected speech is silent for 700 milliseconds', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(
      voiceActivityDetector: _immediateVoiceDetector(),
      now: () => now,
    );
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    amplitudes
      ..add(-60)
      ..add(-60)
      ..add(-60);
    now = now.add(const Duration(milliseconds: 100));
    amplitudes.add(-20);
    expect(detector.speechDetected, isTrue);

    now = now.add(const Duration(milliseconds: 100));
    amplitudes.add(-60);
    await tester.pump(const Duration(milliseconds: 699));
    expect(reasons, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.silence,
    ]);
  });

  testWidgets('voice activity cancels a pending silence endpoint', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(
      silenceDuration: const Duration(milliseconds: 100),
      maximumDuration: const Duration(seconds: 6),
      voiceActivityDetector: _immediateVoiceDetector(),
      now: () => now,
    );
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    amplitudes
      ..add(-60)
      ..add(-60)
      ..add(-60);
    now = now.add(const Duration(milliseconds: 100));
    amplitudes.add(-20);
    now = now.add(const Duration(milliseconds: 100));
    amplitudes.add(-60);
    await tester.pump(const Duration(milliseconds: 50));

    now = now.add(const Duration(milliseconds: 50));
    amplitudes.add(-18);
    await tester.pump(const Duration(milliseconds: 100));
    expect(reasons, isEmpty);

    now = now.add(const Duration(milliseconds: 100));
    amplitudes.add(-60);
    await tester.pump(const Duration(milliseconds: 100));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.silence,
    ]);
  });

  testWidgets(
    'short flat HFP speech ends on silence instead of waiting for six seconds',
    (tester) async {
      final amplitudes = StreamController<double>.broadcast(sync: true);
      addTearDown(amplitudes.close);
      var now = DateTime(2026);
      final reasons = <LessonRecordingEndpointReason>[];
      final detector = LessonRecordingEndpointDetector(now: () => now);
      detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

      amplitudes
        ..add(-60)
        ..add(-60)
        ..add(-60);
      now = now.add(const Duration(milliseconds: 150));
      amplitudes.add(-20);
      now = now.add(const Duration(milliseconds: 280));
      amplitudes.add(-20);
      expect(detector.speechDetected, isTrue);

      now = now.add(const Duration(milliseconds: 90));
      amplitudes.add(-60);
      await tester.pump(const Duration(milliseconds: 700));

      expect(reasons, <LessonRecordingEndpointReason>[
        LessonRecordingEndpointReason.silence,
      ]);
    },
  );

  testWidgets('cancel prevents both silence and maximum callbacks', (
    tester,
  ) async {
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector();
    detector.start(amplitudeDbfs: null, onEndpoint: reasons.add);

    detector.cancel();
    await tester.pump(const Duration(seconds: 6));
    expect(reasons, isEmpty);
  });

  testWidgets('quiet H20 speech below -46 dBFS ends after its quiet tail', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(now: () => now);
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    for (final level in <double>[-75, -74, -75, -56, -53, -55, -75]) {
      amplitudes.add(level);
      now = now.add(const Duration(milliseconds: 90));
    }
    expect(detector.speechDetected, isTrue);
    await tester.pump(const Duration(milliseconds: 700));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.silence,
    ]);
  });

  testWidgets('speech in initial calibration samples is not lost', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(now: () => now);
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    for (final level in <double>[-39, -36, -38, -37, -70]) {
      amplitudes.add(level);
      now = now.add(const Duration(milliseconds: 90));
    }
    expect(detector.speechDetected, isTrue);
    await tester.pump(const Duration(milliseconds: 699));
    expect(reasons, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.silence,
    ]);
  });

  testWidgets(
    'opening speech still ends when its acoustic tail fades gradually',
    (tester) async {
      final amplitudes = StreamController<double>.broadcast(sync: true);
      addTearDown(amplitudes.close);
      var now = DateTime(2026);
      final reasons = <LessonRecordingEndpointReason>[];
      final detector = LessonRecordingEndpointDetector(now: () => now);
      detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

      for (final level in <double>[
        -39,
        -36,
        -38,
        -43,
        -48,
        -53,
        -58,
        -63,
        -68,
        -73,
      ]) {
        amplitudes.add(level);
        now = now.add(const Duration(milliseconds: 90));
      }
      expect(detector.speechDetected, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(reasons, <LessonRecordingEndpointReason>[
        LessonRecordingEndpointReason.silence,
      ]);
    },
  );

  testWidgets('an opening impact and invalid levels do not count as speech', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(now: () => now);
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    for (final level in <double>[-25, double.nan, -75, -75, -75]) {
      amplitudes.add(level);
      now = now.add(const Duration(milliseconds: 90));
    }
    expect(detector.speechDetected, isFalse);
    await tester.pump(const Duration(milliseconds: 700));
    expect(reasons, isEmpty);
    await tester.pump(const Duration(milliseconds: 5300));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.maximumDuration,
    ]);
  });

  testWidgets('continuous ambient sound still waits for the six-second cap', (
    tester,
  ) async {
    final amplitudes = StreamController<double>.broadcast(sync: true);
    addTearDown(amplitudes.close);
    var now = DateTime(2026);
    final reasons = <LessonRecordingEndpointReason>[];
    final detector = LessonRecordingEndpointDetector(now: () => now);
    detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);

    for (var sample = 0; sample < 50; sample++) {
      amplitudes.add(-35);
      now = now.add(const Duration(milliseconds: 90));
    }
    expect(detector.speechDetected, isFalse);
    await tester.pump(const Duration(milliseconds: 5999));
    expect(reasons, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(reasons, <LessonRecordingEndpointReason>[
      LessonRecordingEndpointReason.maximumDuration,
    ]);
  });

  testWidgets(
    'quiet iOS H20 speech ends after its quiet tail instead of six seconds',
    (tester) async {
      final amplitudes = StreamController<double>.broadcast(sync: true);
      addTearDown(amplitudes.close);
      var now = DateTime(2026);
      final reasons = <LessonRecordingEndpointReason>[];
      final detector = LessonRecordingEndpointDetector(now: () => now);
      detector.start(amplitudeDbfs: amplitudes.stream, onEndpoint: reasons.add);
      for (final level in <double>[-75, -74, -75, -56, -53, -55, -75]) {
        amplitudes.add(level);
        now = now.add(const Duration(milliseconds: 90));
      }
      expect(detector.speechDetected, isTrue);
      await tester.pump(const Duration(milliseconds: 699));
      expect(reasons, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reasons, <LessonRecordingEndpointReason>[
        LessonRecordingEndpointReason.silence,
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

AdaptiveVoiceActivityDetector _immediateVoiceDetector() =>
    AdaptiveVoiceActivityDetector(
      calibrationDuration: Duration.zero,
      minimumSpeechDuration: Duration.zero,
      minimumSpeechVariationDb: 0,
    );
