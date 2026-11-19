import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/ios_streaming_audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IosStreamingAudioEvent.fromRaw', () {
    test('parses a playing event', () {
      final event = IosStreamingAudioEvent.fromRaw({
        'type': 'playing',
        'value': true,
      });
      expect(event.type, IosStreamingAudioEventType.playing);
      expect(event.playing, isTrue);
    });

    test('parses a completed event', () {
      final event = IosStreamingAudioEvent.fromRaw({'type': 'completed'});
      expect(event.type, IosStreamingAudioEventType.completed);
    });

    test('parses an error event with code and message', () {
      final event = IosStreamingAudioEvent.fromRaw({
        'type': 'error',
        'code': -11850,
        'message': 'Operation Stopped',
      });
      expect(event.type, IosStreamingAudioEventType.error);
      expect(event.errorCode, -11850);
      expect(event.errorMessage, 'Operation Stopped');
    });

    test('treats an unrecognized or missing type as an error', () {
      expect(
        IosStreamingAudioEvent.fromRaw({'type': 'something-unexpected'}).type,
        IosStreamingAudioEventType.error,
      );
      expect(
        IosStreamingAudioEvent.fromRaw(null).type,
        IosStreamingAudioEventType.error,
      );
    });
  });

  group('IosStreamingAudioPlayerException', () {
    test('formats as "(code) message"', () {
      expect(
        const IosStreamingAudioPlayerException(
          -11850,
          'Operation Stopped',
        ).toString(),
        '(-11850) Operation Stopped',
      );
    });
  });

  group('mergeBroadcastStreams', () {
    test('forwards events from both sources to every listener', () async {
      final controllerA = StreamController<int>.broadcast();
      final controllerB = StreamController<int>.broadcast();
      final merged = mergeBroadcastStreams(
        controllerA.stream,
        controllerB.stream,
      );

      final received = <int>[];
      final subscription = merged.listen(received.add);
      // onListen on the merge controller is synchronous, but the underlying
      // subscriptions are only guaranteed attached after a microtask turn.
      await Future<void>.delayed(Duration.zero);

      controllerA.add(1);
      controllerB.add(2);
      controllerA.add(3);
      await Future<void>.delayed(Duration.zero);

      expect(received, [1, 2, 3]);

      await subscription.cancel();
      await controllerA.close();
      await controllerB.close();
    });

    test('stops forwarding once the listener cancels', () async {
      final controllerA = StreamController<int>.broadcast();
      final controllerB = StreamController<int>.broadcast();
      final merged = mergeBroadcastStreams(
        controllerA.stream,
        controllerB.stream,
      );

      final received = <int>[];
      final subscription = merged.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      controllerA.add(1);
      controllerB.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      await controllerA.close();
      await controllerB.close();
    });
  });
}
