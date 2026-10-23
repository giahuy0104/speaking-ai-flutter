import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/device/device_connection_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ConnectionDeviceRecord record(
    String id,
    ConnectionDeviceTransport transport, {
    String name = '',
    String? bleDeviceId,
    DateTime? connectedAt,
  }) => ConnectionDeviceRecord(
    id: id,
    name: name,
    transport: transport,
    connectedAt: connectedAt ?? DateTime.utc(2026, 10, 19, 8),
    platform: 'android',
    bleDeviceId: bleDeviceId,
  );

  test(
    'BLE and microphone history survive a new store independently',
    () async {
      final store = DeviceConnectionHistoryStore();
      await store.saveBle(record('ble-1', ConnectionDeviceTransport.ble));
      await store.saveMicrophone(
        record(
          'mic-1',
          ConnectionDeviceTransport.hfp,
          name: 'HM-D001',
          bleDeviceId: 'ble-1',
        ),
      );

      final restartedStore = DeviceConnectionHistoryStore();
      final ble = await restartedStore.readBle();
      final microphone = await restartedStore.readMicrophone();
      expect(ble?.id, 'ble-1');
      expect(ble?.name, isEmpty);
      expect(ble?.transport, ConnectionDeviceTransport.ble);
      expect(ble?.platform, 'android');
      expect(ble?.connectedAt, DateTime.utc(2026, 10, 19, 8));
      expect(microphone?.id, 'mic-1');
      expect(microphone?.name, 'HM-D001');
      expect(microphone?.transport, ConnectionDeviceTransport.hfp);
      expect(microphone?.bleDeviceId, 'ble-1');
    },
  );

  test(
    'serial writes keep the latest connection and preserve the mic',
    () async {
      final store = DeviceConnectionHistoryStore();
      final operations = <Future<void>>[
        store.saveBle(record('ble-old', ConnectionDeviceTransport.ble)),
        store.saveMicrophone(record('mic', ConnectionDeviceTransport.hfp)),
        store.saveBle(record('ble-new', ConnectionDeviceTransport.ble)),
      ];
      // Reads wait for already scheduled saves even when callers did not await.
      expect((await store.readBle())?.id, 'ble-new');
      await Future.wait(operations);
      expect((await store.readMicrophone())?.id, 'mic');
    },
  );

  test('a failed save does not block later connections from saving', () async {
    var failuresRemaining = 1;
    final store = DeviceConnectionHistoryStore(
      preferences: () async {
        if (failuresRemaining-- > 0) throw StateError('unavailable');
        return SharedPreferences.getInstance();
      },
    );
    await expectLater(
      store.saveBle(record('failed', ConnectionDeviceTransport.ble)),
      throwsStateError,
    );
    await store.saveBle(record('connected', ConnectionDeviceTransport.ble));
    expect((await store.readBle())?.id, 'connected');
  });

  test('wrong transport or empty ID cannot overwrite a good record', () async {
    final store = DeviceConnectionHistoryStore();
    await store.saveBle(record('ble', ConnectionDeviceTransport.ble));
    await expectLater(
      store.saveBle(record('mic', ConnectionDeviceTransport.hfp)),
      throwsArgumentError,
    );
    await expectLater(
      store.saveBle(record(' ', ConnectionDeviceTransport.ble)),
      throwsArgumentError,
    );
    expect((await store.readBle())?.id, 'ble');
    expect(await store.readMicrophone(), isNull);
  });

  test(
    'corrupt and incompatible history is ignored without deleting data',
    () async {
      const key = 'homi.device-connection-history.ble.v1';
      final preferences = await SharedPreferences.getInstance();
      final store = DeviceConnectionHistoryStore();
      for (final invalid in <String>[
        'not-json',
        '[]',
        '{}',
        jsonEncode(record('mic', ConnectionDeviceTransport.hfp).toJson()),
        jsonEncode(<String, Object?>{
          ...record('ble', ConnectionDeviceTransport.ble).toJson(),
          'version': 99,
        }),
        jsonEncode(<String, Object?>{
          ...record('ble', ConnectionDeviceTransport.ble).toJson(),
          'connectedAt': 'invalid',
        }),
      ]) {
        await preferences.setString(key, invalid);
        expect(await store.readBle(), isNull);
        expect(preferences.getString(key), invalid);
      }
    },
  );

  test('history encodes UTC timestamps and retains legacy BLE keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aiv0_ble_last_device_id': 'legacy-ble',
      'aiv0_ble_last_device_name': 'HM-D001',
    });
    final timestamp = DateTime.parse('2026-10-19T15:30:00+07:00');
    final saved = record(
      'ble',
      ConnectionDeviceTransport.ble,
      connectedAt: timestamp,
    );
    final store = DeviceConnectionHistoryStore();
    await store.saveBle(saved);
    final restored = await store.readBle();
    expect(restored?.connectedAt.isUtc, isTrue);
    expect(restored?.connectedAt, DateTime.utc(2026, 10, 19, 8, 30));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('aiv0_ble_last_device_id'), 'legacy-ble');
    expect(preferences.getString('aiv0_ble_last_device_name'), 'HM-D001');
  });
}
