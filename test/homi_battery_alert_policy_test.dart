import 'package:ai_speaking_flutter_app/app/homi_battery_alert_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HomiBatteryAlertPolicy policy;
  List<HomiBatteryAction> read(
    int? percent, {
    String? id = 'HOMI',
    bool connected = true,
  }) => policy.observe(
    connected: connected,
    deviceId: id,
    batteryPercent: percent,
  );
  setUp(() => policy = HomiBatteryAlertPolicy());

  test('strict 20, 10, 5 boundaries and one reminder per crossing', () {
    expect(read(20), isEmpty);
    expect(read(19), [HomiBatteryAction.chargeSoon]);
    expect(read(18), isEmpty);
    expect(read(10), isEmpty);
    expect(read(9), [HomiBatteryAction.chargeLow]);
    expect(read(8), isEmpty);
    expect(read(5), isEmpty);
    expect(read(4), [HomiBatteryAction.chargeCritical]);
    expect(read(3), isEmpty);
  });

  test('jump past several thresholds only emits most urgent reminder', () {
    expect(read(4), [HomiBatteryAction.chargeCritical]);
    expect(read(9), isEmpty);
    expect(read(19), isEmpty);
  });

  test('threshold noise and disconnect do not repeat alerts', () {
    read(19);
    expect(read(20), isEmpty);
    expect(read(19), isEmpty);
    read(9);
    expect(read(10), isEmpty);
    expect(read(9), isEmpty);
    read(4);
    expect(read(5), isEmpty);
    expect(read(null, id: null, connected: false), isEmpty);
    expect(read(4), isEmpty);
  });

  test('each device retains its own warning history', () {
    expect(read(9), [HomiBatteryAction.chargeLow]);
    expect(read(9, id: 'other'), [HomiBatteryAction.chargeLow]);
    expect(read(9), isEmpty);
  });

  test('recovery margins rearm each warning', () {
    read(4);
    read(8);
    expect(read(4), [HomiBatteryAction.chargeCritical]);
    read(13);
    expect(read(9), [HomiBatteryAction.chargeLow]);
    read(25);
    expect(read(19), [HomiBatteryAction.chargeSoon]);
  });

  test('zero alerts critical and preserves one depleted disconnect', () {
    expect(read(0), [
      HomiBatteryAction.chargeCritical,
      HomiBatteryAction.disconnectDepleted,
    ]);
    expect(read(0), isEmpty);
  });

  test('critical already shown does not alert again at zero', () {
    read(4);
    expect(read(0), [HomiBatteryAction.disconnectDepleted]);
  });

  test('disconnected, missing or invalid battery never triggers', () {
    expect(read(4, connected: false), isEmpty);
    expect(read(null), isEmpty);
    expect(read(-1), isEmpty);
    expect(read(101), isEmpty);
    expect(read(19), [HomiBatteryAction.chargeSoon]);
  });
}
