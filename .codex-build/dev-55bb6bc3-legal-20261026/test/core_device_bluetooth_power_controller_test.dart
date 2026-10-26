import 'dart:async';

import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initial and pending readings cannot expose connection actions',
    () async {
      final read = Completer<Aiv0BluetoothAdapterState>();
      final power = _power(read: () => read.future);
      addTearDown(power.dispose);
      expect(power.hasChecked, isFalse);
      expect(power.canConnect, isFalse);
      final refresh = power.refresh();
      expect(power.isBusy, isTrue);
      read.complete(Aiv0BluetoothAdapterState.poweredOn);
      await refresh;
      expect(power.canConnect, isTrue);
      expect(power.isBusy, isFalse);
    },
  );

  test('OS accepted enable is not success until adapter reports on', () async {
    final power = _power(enable: () async => true);
    addTearDown(power.dispose);
    expect(await power.enable(), isFalse);
    expect(power.state, Aiv0BluetoothAdapterState.poweredOff);
    expect(power.canConnect, isFalse);
    expect(power.actionFailed, isTrue);
  });

  test(
    'repeated enable taps share one system request and verify live state',
    () async {
      var state = Aiv0BluetoothAdapterState.poweredOff;
      var requests = 0;
      final enable = Completer<bool>();
      final power = _power(
        read: () async => state,
        enable: () {
          requests++;
          return enable.future;
        },
      );
      addTearDown(power.dispose);
      final first = power.enable();
      final second = power.enable();
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      expect(power.canConnect, isFalse);
      state = Aiv0BluetoothAdapterState.poweredOn;
      enable.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(power.canConnect, isTrue);
    },
  );

  test(
    'cancelled enable remains off and a later request can succeed',
    () async {
      var state = Aiv0BluetoothAdapterState.poweredOff;
      var requests = 0;
      final power = _power(
        read: () async => state,
        enable: () async {
          if (++requests == 1) return false;
          state = Aiv0BluetoothAdapterState.poweredOn;
          return true;
        },
      );
      addTearDown(power.dispose);
      expect(await power.enable(), isFalse);
      expect(power.canConnect, isFalse);
      expect(await power.enable(), isTrue);
      expect(power.actionFailed, isFalse);
      expect(requests, 2);
    },
  );

  test('permission grant while radio off does not mean connected', () async {
    var state = Aiv0BluetoothAdapterState.unauthorized;
    var enableCalls = 0;
    final power = _power(
      read: () async => state,
      permission: () async {
        state = Aiv0BluetoothAdapterState.poweredOff;
        return true;
      },
      enable: () async {
        enableCalls++;
        return false;
      },
    );
    addTearDown(power.dispose);
    expect(await power.authorize(), isTrue);
    expect(power.state, Aiv0BluetoothAdapterState.poweredOff);
    expect(power.canConnect, isFalse);
    expect(enableCalls, 0);
  });

  for (final state in <Aiv0BluetoothAdapterState>[
    Aiv0BluetoothAdapterState.unsupported,
    Aiv0BluetoothAdapterState.unknown,
    Aiv0BluetoothAdapterState.resetting,
    Aiv0BluetoothAdapterState.unauthorized,
  ]) {
    test('$state never requests enable or exposes Connect', () async {
      var enables = 0;
      final power = _power(
        read: () async => state,
        permission: () async => false,
        enable: () async {
          enables++;
          return true;
        },
      );
      addTearDown(power.dispose);
      expect(await power.enable(), isFalse);
      expect(power.canConnect, isFalse);
      expect(enables, 0);
    });
  }

  test('iOS cannot request programmatic enable', () async {
    var enables = 0;
    final power = _power(
      canEnable: false,
      enable: () async {
        enables++;
        return true;
      },
    );
    addTearDown(power.dispose);
    expect(await power.enable(), isFalse);
    expect(enables, 0);
  });

  test(
    'enable waits for a transitioning adapter without another OS request',
    () async {
      var reads = 0;
      var enables = 0;
      final power = _power(
        read: () async => switch (++reads) {
          1 => Aiv0BluetoothAdapterState.poweredOff,
          2 => Aiv0BluetoothAdapterState.resetting,
          _ => Aiv0BluetoothAdapterState.poweredOn,
        },
        enable: () async {
          enables++;
          return false;
        },
      );
      addTearDown(power.dispose);
      expect(await power.enable(), isTrue);
      expect(power.canConnect, isTrue);
      expect(enables, 1);
    },
  );

  test('live radio state wins over a failed enable request', () async {
    var state = Aiv0BluetoothAdapterState.poweredOff;
    final power = _power(
      read: () async => state,
      enable: () async {
        state = Aiv0BluetoothAdapterState.poweredOn;
        throw StateError('dialog unavailable');
      },
    );
    addTearDown(power.dispose);
    expect(await power.enable(), isTrue);
    expect(power.actionFailed, isFalse);
    expect(power.canConnect, isTrue);
  });

  test('adapter query failure invalidates previously ready radio', () async {
    var fail = false;
    final power = _power(
      read: () async {
        if (fail) throw StateError('radio service unavailable');
        return Aiv0BluetoothAdapterState.poweredOn;
      },
    );
    addTearDown(power.dispose);
    await power.refresh();
    expect(power.canConnect, isTrue);
    fail = true;
    await power.refresh();
    expect(power.state, Aiv0BluetoothAdapterState.unknown);
    expect(power.canConnect, isFalse);
  });

  test(
    'dispose while permission pending cannot open system enable later',
    () async {
      final permission = Completer<bool>();
      var enables = 0;
      var notifications = 0;
      final power = _power(
        read: () async => Aiv0BluetoothAdapterState.unauthorized,
        permission: () => permission.future,
        enable: () async {
          enables++;
          return true;
        },
      )..addListener(() => notifications++);
      final action = power.enable();
      await Future<void>.delayed(Duration.zero);
      power.dispose();
      final before = notifications;
      permission.complete(true);
      expect(await action, isFalse);
      expect(enables, 0);
      expect(notifications, before);
    },
  );
}

BluetoothPowerController _power({
  Future<Aiv0BluetoothAdapterState> Function()? read,
  Future<bool> Function()? enable,
  Future<bool> Function()? permission,
  bool canEnable = true,
}) => BluetoothPowerController(
  readState: read ?? () async => Aiv0BluetoothAdapterState.poweredOff,
  requestEnable: enable ?? () async => false,
  requestPermission: permission ?? () async => true,
  canRequestEnable: canEnable,
);
