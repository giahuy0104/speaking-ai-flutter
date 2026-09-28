import 'package:ai_speaking_flutter_app/app/h20_battery_alert_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('warns once at 20 percent and once below 5 percent', () {
    final policy = H20BatteryAlertPolicy();

    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 20),
      const [H20BatteryAction.chargeSoon],
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 19),
      isEmpty,
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 4),
      const [H20BatteryAction.chargeCritical],
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 3),
      isEmpty,
    );
  });

  test('zero percent requests one disconnect without duplicate warnings', () {
    final policy = H20BatteryAlertPolicy();

    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 0),
      const [H20BatteryAction.disconnectDepleted],
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 0),
      isEmpty,
    );
  });

  test('charging hysteresis rearms the next discharge cycle', () {
    final policy = H20BatteryAlertPolicy();

    policy.observe(connected: true, deviceId: 'H20', batteryPercent: 20);
    policy.observe(connected: true, deviceId: 'H20', batteryPercent: 4);
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 10),
      isEmpty,
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 4),
      const [H20BatteryAction.chargeCritical],
    );
    policy.observe(connected: true, deviceId: 'H20', batteryPercent: 30);
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: 20),
      const [H20BatteryAction.chargeSoon],
    );
  });

  test('disconnected or unknown battery values never alert', () {
    final policy = H20BatteryAlertPolicy();

    expect(
      policy.observe(connected: false, deviceId: 'H20', batteryPercent: 4),
      isEmpty,
    );
    expect(
      policy.observe(connected: true, deviceId: 'H20', batteryPercent: null),
      isEmpty,
    );
  });
}
