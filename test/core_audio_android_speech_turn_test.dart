import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_android_turns');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<dynamic> events;
  late AndroidStreamingSpeechInput input;
  late List<int> turns;
  late int cancels;

  setUp(() {
    events = StreamController<dynamic>.broadcast();
    turns = <int>[];
    cancels = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') return true;
      if (call.method == 'speech.start') {
        final turn = (call.arguments as Map)['turnId'] as int;
        turns.add(turn);
        events.add({'type': 'speech.ready', 'turnId': turn});
      }
      if (call.method == 'speech.cancel') cancels++;
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
    'only current Android command endpoint emits a provisional candidate',
    () async {
      final candidates = <String>[];
      final completions = <void>[];
      final endpointSubscription = input.commandSpeechEnded.listen(
        candidates.add,
      );
      final completionSubscription = input.completed.listen(completions.add);
      addTearDown(endpointSubscription.cancel);
      addTearDown(completionSubscription.cancel);

      await input.start();
      final ordinaryTurn = turns.last;
      events.add({
        'type': 'speech.partial',
        'turnId': ordinaryTurn,
        'text': 'lesson answer',
      });
      events.add({'type': 'speech.end', 'turnId': ordinaryTurn});
      await Future<void>.delayed(Duration.zero);
      expect(candidates, isEmpty);
      expect(completions, isEmpty);

      await input.cancel();
      await input.startCommandRecognition();
      final commandTurn = turns.last;
      events.add({'type': 'speech.end', 'turnId': ordinaryTurn});
      events.add({
        'type': 'speech.partial',
        'turnId': commandTurn,
        'text': 'Chủ đề 3',
      });
      events.add({'type': 'speech.end', 'turnId': commandTurn});
      events.add({'type': 'speech.end', 'turnId': commandTurn});
      await Future<void>.delayed(Duration.zero);
      expect(candidates, ['Chủ đề 3']);
      expect(completions, isEmpty, reason: 'endpoint is not a final result');
    },
  );

  test(
    'ordinary Android turn reports native end-of-speech with its transcript',
    () async {
      final candidates = <String>[];
      final subscription = input.speechEnded.listen(candidates.add);
      addTearDown(subscription.cancel);

      await input.start();
      final turn = turns.last;
      events.add({'type': 'speech.end', 'turnId': turn});
      await Future<void>.delayed(Duration.zero);
      expect(candidates, isEmpty, reason: 'no transcript yet');

      events.add({
        'type': 'speech.partial',
        'turnId': turn,
        'text': 'Con muốn uống nước',
      });
      events.add({'type': 'speech.end', 'turnId': turn});
      await Future<void>.delayed(Duration.zero);
      expect(candidates, ['Con muốn uống nước']);

      await input.cancel();
      await input.startCommandRecognition();
      final commandTurn = turns.last;
      events.add({
        'type': 'speech.partial',
        'turnId': commandTurn,
        'text': 'Chủ đề 3',
      });
      events.add({'type': 'speech.end', 'turnId': commandTurn});
      await Future<void>.delayed(Duration.zero);
      expect(candidates, ['Con muốn uống nước'], reason: 'command turn');
    },
  );

  test(
    'command endpoint can finalize a stable one-word number promptly',
    () async {
      await input.startCommandRecognition();
      events.add({
        'type': 'speech.partial',
        'turnId': turns.single,
        'text': 'ba',
      });
      await Future<void>.delayed(const Duration(milliseconds: 360));
      events.add({'type': 'speech.end', 'turnId': turns.single});
      await Future<void>.delayed(Duration.zero);
      final stopwatch = Stopwatch()..start();
      final result = await input.stop();
      expect(result.sourceText, 'ba');
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 700)));
      expect(cancels, 1);
    },
  );

  test(
    'corrected final during endpoint grace replaces provisional topic number',
    () async {
      await input.startCommandRecognition();
      final turn = turns.single;
      events.add({
        'type': 'speech.partial',
        'turnId': turn,
        'text': 'Chủ đề 1',
      });
      await Future<void>.delayed(const Duration(milliseconds: 360));
      events.add({'type': 'speech.end', 'turnId': turn});
      await Future<void>.delayed(Duration.zero);
      final resultFuture = input.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      events.add({'type': 'speech.final', 'turnId': turn, 'text': 'Chủ đề 10'});
      final result = await resultFuture;
      expect(result.sourceText, 'Chủ đề 10');
      expect(cancels, 0);
    },
  );

  test('cancelled turn error and final cannot overwrite replacement', () async {
    await input.start();
    final old = turns.single;
    await input.cancel();
    await input.start();
    final current = turns.last;
    events.add({'type': 'speech.error', 'turnId': old, 'code': 5});
    events.add({'type': 'speech.final', 'turnId': old, 'text': 'câu cũ'});
    events.add({'type': 'speech.final', 'turnId': current, 'text': 'câu mới'});
    await Future<void>.delayed(Duration.zero);
    final result = await input.stop();
    expect(result.sourceText, 'câu mới');
  });

  test('stable partial drains native recognizer before returning', () async {
    await input.start();
    events.add({
      'type': 'speech.partial',
      'turnId': turns.single,
      'text': 'học chủ đề',
    });
    await Future<void>.delayed(const Duration(milliseconds: 360));
    final result = await input.stop();
    expect(result.sourceText, 'học chủ đề');
    expect(cancels, 1);
  });

  test('current recognizer error remains visible with its code', () async {
    await input.start();
    events.add({
      'type': 'speech.error',
      'turnId': turns.single,
      'code': 5,
      'message': 'Lỗi nhận dạng',
    });
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      input.stop(),
      throwsA(
        isA<StreamingSpeechInputException>().having(
          (e) => e.code,
          'code',
          'ANDROID_SPEECH_5',
        ),
      ),
    );
  });

  test('cancel during cold availability cannot open an obsolete mic', () async {
    final firstAvailability = Completer<bool>();
    var availabilityCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') {
        availabilityCalls++;
        return availabilityCalls == 1 ? firstAvailability.future : true;
      }
      if (call.method == 'speech.start') {
        final turn = (call.arguments as Map)['turnId'] as int;
        turns.add(turn);
        events.add({'type': 'speech.ready', 'turnId': turn});
      }
      if (call.method == 'speech.cancel') cancels++;
      return true;
    });
    final obsolete = expectLater(input.start(), throwsA(_isCancelled));
    await _waitUntil(() => availabilityCalls == 1);
    await input.cancel();
    await input.start();
    firstAvailability.complete(true);
    await obsolete;

    expect(turns, hasLength(1));
    await input.cancel();
    expect(cancels, 1, reason: 'the current microphone remained active');
  });

  test(
    'cancel before channel reply observes ready error and preserves new mic',
    () async {
      final firstStartReply = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'speech.isAvailable') return true;
        if (call.method == 'speech.start') {
          final turn = (call.arguments as Map)['turnId'] as int;
          turns.add(turn);
          if (turns.length == 1) return firstStartReply.future;
          events.add({'type': 'speech.ready', 'turnId': turn});
        }
        if (call.method == 'speech.cancel') cancels++;
        return true;
      });
      final obsolete = expectLater(input.start(), throwsA(_isCancelled));
      await _waitUntil(() => turns.isNotEmpty);
      await input.cancel();
      await input.start();
      firstStartReply.complete(true);
      await obsolete;

      expect(turns, hasLength(2));
      await input.cancel();
      expect(cancels, 2);
    },
  );

  for (final timeout in [false, true]) {
    test(
      'obsolete recorded-file ${timeout ? 'timeout' : 'error'} cannot cancel new mic',
      () async {
        await input.dispose();
        input = AndroidStreamingSpeechInput(
          methodChannel: channel,
          eventStream: events.stream,
          nativeCommandTimeout: const Duration(milliseconds: 40),
        );
        final fileReply = Completer<bool>();
        var fileRequested = false;
        var stops = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speech.isAvailable' ||
              call.method == 'speech.supportsAudioSource') {
            return true;
          }
          if (call.method == 'speech.recognizeFile') {
            fileRequested = true;
            return fileReply.future;
          }
          if (call.method == 'speech.start') {
            final turn = (call.arguments as Map)['turnId'] as int;
            turns.add(turn);
            events.add({'type': 'speech.ready', 'turnId': turn});
          }
          if (call.method == 'speech.stop') {
            stops++;
            events.add({
              'type': 'speech.final',
              'turnId': turns.last,
              'text': 'câu mới',
            });
          }
          if (call.method == 'speech.cancel') cancels++;
          return true;
        });
        final obsolete = expectLater(
          input.recognizeRecordedAudio(_recordedCapture),
          throwsA(timeout ? isA<TimeoutException>() : isA<PlatformException>()),
        );
        await _waitUntil(() => fileRequested);
        await input.cancel();
        await input.start();
        if (!timeout) {
          fileReply.completeError(PlatformException(code: 'SPEECH_REPLACED'));
        }
        await obsolete;
        if (timeout) fileReply.complete(true);

        expect(
          cancels,
          1,
          reason: 'obsolete timeout must not cancel the new mic',
        );
        final result = await input.stop();
        expect(
          stops,
          1,
          reason: 'obsolete error must not clear the active flag',
        );
        expect(result.sourceText, 'câu mới');
      },
    );
  }

  test('obsolete stop cannot read or clear the replacement capture', () async {
    final firstStopReply = Completer<bool>();
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') return true;
      if (call.method == 'speech.start') {
        final turn = (call.arguments as Map)['turnId'] as int;
        turns.add(turn);
        events.add({'type': 'speech.ready', 'turnId': turn});
      }
      if (call.method == 'speech.stop') {
        stops++;
        if (stops == 1) return firstStopReply.future;
        events.add({
          'type': 'speech.final',
          'turnId': turns.last,
          'text': 'bản ghi mới',
        });
      }
      if (call.method == 'speech.cancel') cancels++;
      return true;
    });
    await input.start();
    final obsolete = expectLater(input.stop(), throwsA(_isCancelled));
    await _waitUntil(() => stops == 1);
    await input.cancel();
    await input.start();
    firstStopReply.complete(true);
    await obsolete;

    final result = await input.stop();
    expect(stops, 2);
    expect(result.sourceText, 'bản ghi mới');
    expect(cancels, 1);
  });

  test('stalled native stop is bounded and releases recognition', () async {
    await input.dispose();
    input = AndroidStreamingSpeechInput(
      methodChannel: channel,
      eventStream: events.stream,
      nativeCommandTimeout: const Duration(milliseconds: 30),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speech.isAvailable') return true;
      if (call.method == 'speech.start') {
        events.add({
          'type': 'speech.ready',
          'turnId': (call.arguments as Map)['turnId'],
        });
      }
      if (call.method == 'speech.stop') return Completer<bool>().future;
      if (call.method == 'speech.cancel') cancels++;
      return true;
    });
    await input.start();
    await expectLater(input.stop(), throwsA(isA<TimeoutException>()));
    expect(cancels, 1);
  });

  testWidgets(
    'first Android bind has a longer ceiling but warm mic stays bounded',
    (tester) async {
      final nativeStartReplies = <Completer<bool>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'speech.isAvailable') return true;
        if (call.method == 'speech.start') {
          turns.add((call.arguments as Map)['turnId'] as int);
          final reply = Completer<bool>();
          nativeStartReplies.add(reply);
          return reply.future;
        }
        if (call.method == 'speech.cancel') cancels++;
        return true;
      });
      var firstCompleted = false;
      final first = input.start().then((_) => firstCompleted = true);
      await tester.pump();
      expect(nativeStartReplies, hasLength(1));
      // Finish the method-channel handshake before advancing the separate
      // speech.ready deadline. Otherwise this test could time out the command
      // itself rather than exercise cold recognizer readiness.
      nativeStartReplies.single.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(firstCompleted, isFalse);
      expect(cancels, 0);
      events.add({'type': 'speech.ready', 'turnId': turns.single});
      await tester.pump();
      await first;

      await input.cancel();
      final second = expectLater(
        input.start(),
        throwsA(
          isA<StreamingSpeechInputException>().having(
            (e) => e.code,
            'code',
            'SPEECH_READY_TIMEOUT',
          ),
        ),
      );
      await tester.pump();
      expect(nativeStartReplies, hasLength(2));
      nativeStartReplies.last.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      await second;
      expect(cancels, 2);
    },
  );
}

final _isCancelled = isA<StreamingSpeechInputException>().having(
  (error) => error.code,
  'code',
  'SPEECH_START_CANCELLED',
);

const _recordedCapture = AudioCapture(
  filePath: 'test-recording.wav',
  mimeType: 'audio/wav',
  duration: Duration(seconds: 1),
  inputLabel: 'H20',
  isBluetoothInput: true,
  initialNoiseRms: null,
  recordingSampleRate: 16000,
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}
