import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_route_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {}

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
