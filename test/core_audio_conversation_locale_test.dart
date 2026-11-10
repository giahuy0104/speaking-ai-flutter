import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_conversation_locale');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<dynamic> events;
  late AndroidStreamingSpeechInput input;
  late List<Map<Object?, Object?>> starts;

  setUp(() {
    events = StreamController<dynamic>.broadcast();
    starts = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') return true;
      if (call.method == 'speech.start') {
        final arguments = call.arguments as Map<Object?, Object?>;
        starts.add(arguments);
        events.add({'type': 'speech.ready', 'turnId': arguments['turnId']});
      }
      return true;
    });
    input = AndroidStreamingSpeechInput(
      methodChannel: channel,
      eventStream: events.stream,
    );
  });

  tearDown(() async {
    await input.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'conversation turns use the chosen locale; commands keep theirs',
    () async {
      // Default conversation turns keep the native default (vi-VN).
      await input.start();
      expect(starts.last.containsKey('locale'), isFalse);
      await input.cancel();

      input.conversationLocale = 'ja-JP';
      await input.start();
      expect(starts.last['locale'], 'ja-JP');
      await input.cancel();

      // MAIN commands never take the conversation locale.
      await input.startCommandRecognition();
      expect(starts.last.containsKey('locale'), isFalse);
      await input.cancel();

      input.conversationLocale = null;
      await input.start();
      expect(starts.last.containsKey('locale'), isFalse);
    },
  );
}
