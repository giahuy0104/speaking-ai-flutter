import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/core/audio/playback_trace.dart';

void main() {
  late DateTime now;
  PlaybackTraceRecorder recorder({int maxSamples = 3}) => PlaybackTraceRecorder(
    traceId: 7,
    source: 'https://api.test/api/audio/target',
    now: () => now,
    maxSamples: maxSamples,
  );

  Map<String, Object?>? observe(
    PlaybackTraceRecorder trace, {
    String state = 'ready',
    bool playing = true,
    int positionMs = 0,
    int bufferedMs = 0,
    int? durationMs = 1000,
    bool sample = false,
  }) => trace.observe(
    state: state,
    playing: playing,
    position: Duration(milliseconds: positionMs),
    bufferedPosition: Duration(milliseconds: bufferedMs),
    duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    sample: sample,
  );

  setUp(() => now = DateTime.utc(2026, 11, 17, 4));

  test('logs state changes immediately and skips repeats between samples', () {
    final trace = recorder();
    final first = observe(trace, state: 'loading', playing: false);
    expect(first?['event'], 'playback_trace_state');
    expect(first?['state'], 'loading');
    expect(observe(trace, state: 'loading', playing: false), isNull);

    now = now.add(const Duration(milliseconds: 1250));
    final ready = observe(trace, positionMs: 40, bufferedMs: 900);
    expect(ready?['event'], 'playback_trace_state');
    expect(ready?['elapsedMs'], 1250);
    expect(ready?['bufferedMs'], 900);
  });

  test(
    'periodic samples show position and buffering, capped by maxSamples',
    () {
      final trace = recorder(maxSamples: 2);
      observe(trace);
      expect(
        observe(trace, positionMs: 500, sample: true)?['event'],
        'playback_trace_sample',
      );
      expect(observe(trace, positionMs: 1000, sample: true), isNotNull);
      expect(observe(trace, positionMs: 1000, sample: true), isNull);
      expect(trace.samplesExhausted, isTrue);
      // A real state change is still recorded after the sample budget is spent.
      expect(observe(trace, state: 'completed')?['state'], 'completed');
    },
  );

  test('an unknown WAV length shows up as a huge duration', () {
    final trace = recorder();
    final record = observe(trace, durationMs: 0xffffffff ~/ 48);
    expect(record?['durationMs'], greaterThan(24 * 60 * 60 * 1000));
  });

  test('finish is printed once and stops later records', () {
    final trace = recorder();
    expect(trace.finish('completed')?['reason'], 'completed');
    expect(trace.finish('cancelled'), isNull);
    expect(observe(trace, state: 'completed'), isNull);
  });

  test('source never keeps the query string of signed URLs', () {
    expect(
      PlaybackTraceRecorder.describe(
        Uri.parse(
          'https://api-dev.example/api/audio/target?lang=zh&sig=abc&text=hi',
        ),
      ),
      'https://api-dev.example/api/audio/target',
    );
    expect(
      PlaybackTraceRecorder.describe(
        Uri.parse('file:///data/cache/audio/abc.mp3'),
      ),
      'file:abc.mp3',
    );
  });
}
