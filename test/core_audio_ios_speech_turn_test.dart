import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// iOS lifecycle events now carry the integer turn id Dart sent with
/// `speech.start`, while `speech.stage` diagnostics keep the audio session's
/// own string id. Both shapes travel the same channel, so the guard has to
/// drop a replaced turn without silencing diagnostics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_ios_turns');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<dynamic> events;
  late IOSStreamingSpeechInput input;
  late List<int> turns;

  setUp(() {
    events = StreamController<dynamic>.broadcast();
    turns = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') return true;
      if (call.method == 'speech.start') {
        final turn = (call.arguments as Map)['turnId'] as int;
        turns.add(turn);
        events.add({'type': 'speech.ready', 'turnId': turn});
      }
      return true;
    });
    input = IOSStreamingSpeechInput(
      methodChannel: channel,
      eventStream: events.stream,
    );
  });

  tearDown(() async {
    await input.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a replaced turn cannot deliver the final result of its successor', () async {
    await input.start();
    final replaced = turns.single;

    await input.cancel();
    await input.start();
    expect(turns.last, isNot(replaced));

    events.add({
      'type': 'speech.final',
      'turnId': replaced,
      'text': 'câu của lượt cũ',
    });
    events.add({
      'type': 'speech.final',
      'turnId': turns.last,
      'text': 'câu của lượt hiện tại',
    });
    await pumpEventQueue();

    final capture = await input.stop();
    expect(capture.sourceText, 'câu của lượt hiện tại');
  });

  test('a replaced turn cannot fail its successor', () async {
    await input.start();
    final replaced = turns.single;
    await input.cancel();
    await input.start();

    events.add({'type': 'speech.error', 'turnId': replaced, 'code': 5});
    events.add({
      'type': 'speech.final',
      'turnId': turns.last,
      'text': 'lượt hiện tại vẫn sống',
    });
    await pumpEventQueue();

    final capture = await input.stop();
    expect(capture.sourceText, 'lượt hiện tại vẫn sống');
  });

  test('stage diagnostics keep the audio session string id and are not dropped',
      () async {
    await input.start();
    final diagnostics = <String>[];
    final subscription = input.nativeSpeechDiagnostics.listen(
      (value) => diagnostics.add(value.stage),
    );
    addTearDown(subscription.cancel);

    events.add({
      'type': 'speech.stage',
      'stage': 'setActive_true_completed',
      'turnId': 'ios-main-1790653450000-a3f9c1',
    });
    await pumpEventQueue();

    expect(diagnostics, contains('setActive_true_completed'));
  });
}
