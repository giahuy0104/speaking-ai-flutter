import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_route_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explicit phone switch flushes retained HFP without a timer', (
    tester,
  ) async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(
      native,
      handoffGrace: const Duration(milliseconds: 750),
    );
    final main = coordinator.createScope('main');
    final lesson = coordinator.createScope('lesson');
    await main.startAudioRoute();
    await main.stopAudioRoute();
    await (lesson as HfpImmediateRouteReleaseControl)
        .stopAudioRouteImmediately();
    expect(native.stopCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(native.stopCalls, 1);
    await coordinator.dispose();
  });

  test('immediate release never closes another live owner', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(
      native,
      handoffGrace: const Duration(milliseconds: 750),
    );
    final main = coordinator.createScope('main');
    final lesson = coordinator.createScope('lesson');
    await main.startAudioRoute();
    await lesson.startAudioRoute();
    await (lesson as HfpImmediateRouteReleaseControl)
        .stopAudioRouteImmediately();
    expect(native.stopCalls, 0);
    await coordinator.dispose();
    expect(native.stopCalls, 1);
  });

  testWidgets(
    'Android handoff reuses SCO and stale timer cannot stop new owner',
    (tester) async {
      final native = _FakeHfpAudioControl();
      final coordinator = HfpAudioRouteCoordinator(
        native,
        handoffGrace: const Duration(milliseconds: 750),
        revalidateOnAcquire: true,
      );
      final main = coordinator.createScope('main');
      final vocabulary = coordinator.createScope('vocabulary');
      await main.startAudioRoute();
      await main.stopAudioRoute();
      expect(native.stopCalls, 0);
      await tester.pump(const Duration(milliseconds: 100));
      await vocabulary.startAudioRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(native.stopCalls, 0);
      expect(
        native.startCalls,
        2,
      ); // Revalidate the existing native route/mode.
      await vocabulary.stopAudioRoute();
      await tester.pump(const Duration(milliseconds: 751));
      expect(native.stopCalls, 1);
      await coordinator.dispose();
      expect(native.stopCalls, 1);
    },
  );

  testWidgets('disposing retained route releases it immediately once', (
    tester,
  ) async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(
      native,
      handoffGrace: const Duration(milliseconds: 750),
    );
    final scope = coordinator.createScope('main');
    await scope.startAudioRoute();
    await scope.stopAudioRoute();
    await coordinator.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(native.stopCalls, 1);
  });

  testWidgets('disconnect cancels pending handoff cleanup', (tester) async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(
      native,
      handoffGrace: const Duration(milliseconds: 750),
    );
    final scope = coordinator.createScope('main');
    await scope.startAudioRoute();
    await scope.stopAudioRoute();
    await coordinator.disconnect();
    await tester.pump(const Duration(seconds: 1));
    expect(native.stopCalls, 0); // disconnect owns teardown.
    await coordinator.dispose();
  });

  test(
    'disconnect cancels another scope start before a queued reconnect',
    () async {
      final native = _FakeHfpAudioControl()..startGate = Completer<void>();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      final settings = coordinator.createScope('settings');
      final starting = lesson.startAudioRoute();
      final cancelled = expectLater(
        starting,
        throwsA(isA<HfpAudioException>()),
      );
      await Future<void>.delayed(Duration.zero);

      final disconnecting = settings.disconnect();
      final reconnecting = settings.connect(
        const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
      );
      native.startGate!.complete();

      await cancelled;
      await disconnecting;
      await reconnecting;
      expect(native.connectionEvents, <String>['disconnect', 'connect:h20']);
      expect(
        (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken,
        isNull,
      );

      await lesson.startAudioRoute();
      expect(native.startCalls, 2);
    },
  );

  test(
    'disconnect cancels another scope revalidation before reconnect',
    () async {
      final native = _FakeHfpAudioControl();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      final settings = coordinator.createScope('settings');
      await lesson.startAudioRoute();
      native.startGate = Completer<void>();

      final revalidating = lesson.startAudioRoute();
      final cancelled = expectLater(
        revalidating,
        throwsA(isA<HfpAudioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final disconnecting = settings.disconnect();
      final reconnecting = settings.connect(
        const HfpAudioDevice(id: 'h20', name: 'H20', isConnected: true),
      );
      native.startGate!.complete();

      await cancelled;
      await disconnecting;
      await reconnecting;
      expect(native.connectionEvents, <String>['disconnect', 'connect:h20']);
      expect(
        (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken,
        isNull,
      );

      native.startGate = null;
      await lesson.startAudioRoute();
      expect(native.startCalls, 3);
    },
  );

  test(
    'stop during native start releases the late lease and cancels its caller',
    () async {
      final native = _FakeHfpAudioControl()..startGate = Completer<void>();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      final starting = lesson.startAudioRoute();
      final cancelled = expectLater(
        starting,
        throwsA(isA<HfpAudioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final stopping = lesson.stopAudioRoute();
      native.startGate!.complete();
      await cancelled;
      await stopping;
      expect(native.stopCalls, 1);
      expect(
        (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken,
        isNull,
      );
      await lesson.startAudioRoute();
      expect(native.startCalls, 2);
    },
  );

  test(
    'parallel starts in one scope cannot leak an extra route lease',
    () async {
      final native = _FakeHfpAudioControl();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      await Future.wait([lesson.startAudioRoute(), lesson.startAudioRoute()]);
      await lesson.stopAudioRoute();
      expect(native.stopCalls, 1);
    },
  );

  test(
    'next owner reopens a dropped native route despite an old Dart lease',
    () async {
      final native = _FakeHfpAudioControl();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      final speech = coordinator.createScope('speech');
      await lesson.startAudioRoute();
      native.routeActive = false;
      await speech.startAudioRoute();
      expect(native.startCalls, 2);
      await lesson.stopAudioRoute();
      expect(native.stopCalls, 0);
      await speech.stopAudioRoute();
      expect(native.stopCalls, 1);
    },
  );

  test(
    'disposing during native start leaves no owner or unobserved future',
    () async {
      final native = _FakeHfpAudioControl()..startGate = Completer<void>();
      final coordinator = HfpAudioRouteCoordinator(native);
      addTearDown(coordinator.dispose);
      final lesson = coordinator.createScope('lesson');
      final starting = expectLater(
        lesson.startAudioRoute(),
        throwsA(isA<HfpAudioException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final disposing = lesson.dispose();
      native.startGate!.complete();
      await starting;
      await disposing;
      expect(native.stopCalls, 1);
    },
  );

  test('coordinator dispose invalidates a pending native start', () async {
    final native = _FakeHfpAudioControl()..startGate = Completer<void>();
    final coordinator = HfpAudioRouteCoordinator(native);
    final lesson = coordinator.createScope('lesson');
    final starting = expectLater(
      lesson.startAudioRoute(),
      throwsA(isA<HfpAudioException>()),
    );
    await Future<void>.delayed(Duration.zero);

    final disposing = coordinator.dispose();
    native.startGate!.complete();

    await starting;
    await disposing;
    expect((lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken, isNull);
    expect(native.disposeCalls, 1);
  });

  test('first owner opens HFP and final owner closes it', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');
    final speech = coordinator.createScope('apple-speech');

    await lesson.startAudioRoute();
    await speech.startAudioRoute();
    expect(native.startCalls, 1);

    await lesson.stopAudioRoute();
    expect(native.stopCalls, 0);
    await speech.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('revalidating one scope keeps the same lease and route', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');

    await lesson.startAudioRoute();
    final firstToken =
        (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken;
    await lesson.startAudioRoute();

    expect(native.startCalls, 2);
    expect(
      (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken,
      firstToken,
    );
    await lesson.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('handoff does not close a route retained by native speech', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');
    final speech = coordinator.createScope('apple-speech');

    await lesson.startAudioRoute();
    await speech.startAudioRoute();
    await (lesson as HfpAudioRouteLeaseControl).handoffAudioRoute();
    expect(native.stopCalls, 0);

    await lesson.stopAudioRoute();
    expect(native.stopCalls, 0);
    await speech.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('disposing an old scope cannot close the next owner', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final oldLesson = coordinator.createScope('old-lesson');
    final nextLesson = coordinator.createScope('next-lesson');

    await oldLesson.startAudioRoute();
    await nextLesson.startAudioRoute();
    await oldLesson.dispose();
    expect(native.stopCalls, 0);

    await nextLesson.stopAudioRoute();
    expect(native.stopCalls, 1);
  });
}

class _FakeHfpAudioControl implements HfpAudioControl {
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Completer<void>? startGate;
  bool routeActive = true;
  final List<String> connectionEvents = <String>[];

  @override
  bool get usesBrowserAudioInput => false;

  @override
  BluetoothAudioStatus get status => BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    routeActive: routeActive,
  );

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      const Stream<BluetoothAudioStatus>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {
    connectionEvents.add('connect:${device.id}');
  }

  @override
  Future<void> disconnect() async {
    connectionEvents.add('disconnect');
    routeActive = false;
  }

  @override
  Future<void> startAudioRoute() async {
    startCalls += 1;
    await startGate?.future;
    routeActive = true;
  }

  @override
  Future<void> stopAudioRoute() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
