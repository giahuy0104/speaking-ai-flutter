import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';

void main() {
  test(
    'one connection owns Settings and action retry, cancel ignores late success',
    () async {
      final result = Completer<bool>();
      var connects = 0;
      var cancels = 0;
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () {
          connects++;
          return result.future;
        },
        onCancel: () async {
          cancels++;
        },
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      final first = coordinator.connect();
      expect(coordinator.hasManualOperation, isTrue);
      expect(await coordinator.connect(), isFalse);
      expect(await coordinator.beginManualOperation(), isNull);
      await coordinator.cancel();
      expect(await first, isFalse);
      result.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.phase, DeviceConnectionPhase.disconnected);
      expect(coordinator.isBusy, isFalse);
      expect(connects, 1);
      expect(cancels, 1);
    },
  );

  test(
    'picker retains ownership and cancellation invalidates its token',
    () async {
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => true,
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      final token = (await coordinator.beginManualOperation())!;
      coordinator.setManualPhase(token, DeviceConnectionPhase.connecting);
      coordinator.updateStatus(DeviceConnectionPhase.ready);
      expect(coordinator.phase, DeviceConnectionPhase.connecting);
      expect(await coordinator.beginManualOperation(), isNull);
      await coordinator.cancel();
      expect(coordinator.isCurrent(token), isFalse);
      coordinator.setManualPhase(token, DeviceConnectionPhase.ready);
      coordinator.endManualOperation(token);
      expect(coordinator.phase, DeviceConnectionPhase.disconnected);
      expect(await coordinator.connect(), isTrue);
    },
  );

  test('a new request waits for cancellation to finish', () async {
    final cancelled = Completer<void>();
    final coordinator = DeviceConnectionCoordinator(
      onConnect: () async => true,
      onCancel: () => cancelled.future,
      onOpenBluetoothSettings: () async {},
    );
    addTearDown(coordinator.dispose);
    final pending = coordinator.beginManualOperation();
    final stop = coordinator.cancel();
    expect(await coordinator.connect(), isFalse);
    cancelled.complete();
    await stop;
    expect(await pending, isNull);
    expect(await coordinator.connect(), isTrue);
  });

  test(
    'failure releases ownership, background status can recover quietly',
    () async {
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => throw StateError('radio unavailable'),
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      expect(await coordinator.connect(), isFalse);
      expect(coordinator.phase, DeviceConnectionPhase.failed);
      expect(coordinator.isBusy, isFalse);
      coordinator.updateStatus(DeviceConnectionPhase.disconnected);
      expect(coordinator.phase, DeviceConnectionPhase.failed);
      coordinator.updateStatus(DeviceConnectionPhase.ready);
      expect(coordinator.phase, DeviceConnectionPhase.ready);
    },
  );
}
