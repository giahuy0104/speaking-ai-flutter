import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/native_audio_focus.dart';
import 'package:ai_speaking_flutter_app/core/platform/background_learning_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.native_audio_focus');
  late _BackgroundSession session;
  late NativeAudioFocus focus;
  late List<String> released;
  setUp(() {
    session = _BackgroundSession();
    focus = NativeAudioFocus(
      channel: channel,
      session: session,
      isAndroid: true,
    );
    released = [];
  });
  tearDown(() async {
    await focus.dispose();
    await session.controller.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'idle consumers do not open native channels before acquisition',
    () async {
      final subscription = focus.interruptions.listen((_) {});
      expect(session.eventReads, 0);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);
      final lease = await focus.acquire('capture');
      expect(session.eventReads, 1);
      await lease.release();
      await subscription.cancel();
    },
  );

  test('denied focus cannot produce a usable lease', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    await expectLater(
      focus.acquire('capture'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'AUDIO_FOCUS_DENIED',
        ),
      ),
    );
  });

  test('grant arriving after interruption is released and rejected', () async {
    final grant = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'acquireAudioFocus') return grant.future;
          released.add((call.arguments as Map)['ownerId'] as String);
          return null;
        });
    final starting = focus.acquire('capture');
    final assertion = expectLater(
      starting,
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'AUDIO_FOCUS_LOST',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.interrupt();
    grant.complete(true);
    await assertion;
    expect(released, hasLength(1));
  });

  test(
    'late release cannot release a new turn and resume cannot revive old lease',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'acquireAudioFocus') return true;
            released.add((call.arguments as Map)['ownerId'] as String);
            return null;
          });
      final first = await focus.acquire('main');
      session.interrupt();
      expect(first.isCurrent, isFalse);
      session.controller.add(
        const BackgroundLearningEvent(
          type: BackgroundLearningEventType.resumable,
        ),
      );
      expect(first.isCurrent, isFalse);
      final second = await focus.acquire('main');
      await first.release();
      await first.release();
      expect(second.isCurrent, isTrue);
      expect(released, [first.id]);
      await second.release();
      expect(released, [first.id, second.id]);
    },
  );
}

class _BackgroundSession implements BackgroundLearningSessionControl {
  final controller = StreamController<BackgroundLearningEvent>.broadcast(
    sync: true,
  );
  int eventReads = 0;
  @override
  Stream<BackgroundLearningEvent> get events {
    eventReads++;
    return controller.stream;
  }

  void interrupt() => controller.add(
    const BackgroundLearningEvent(
      type: BackgroundLearningEventType.interrupted,
    ),
  );
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
}
