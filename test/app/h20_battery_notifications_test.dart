import 'package:ai_speaking_flutter_app/app/h20_battery_alert_policy.dart';
import 'package:ai_speaking_flutter_app/app/h20_battery_notifications.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var permission = true;
  var failShow = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    permission = true;
    failShow = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'show' && failShow) {
            throw PlatformException(code: 'NOT_ALLOWED');
          }
          if (call.method == 'requestNotificationsPermission' ||
              call.method == 'requestPermissions') {
            return permission;
          }
          if (call.method == 'initialize') {
            return defaultTargetPlatform != TargetPlatform.iOS;
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'battery sequence posts three reminders with a single tray ID',
    () async {
      final notifications = H20BatteryNotifications();
      final policy = H20BatteryAlertPolicy();
      for (final percent in [25, 20, 19, 19, 10, 9, 9, 5, 4, 4]) {
        for (final action in policy.observe(
          connected: true,
          deviceId: 'HOMI',
          batteryPercent: percent,
        )) {
          if (action != H20BatteryAction.disconnectDepleted) {
            await notifications.show(
              percent: percent,
              language: DisplayLanguage.vietnamese,
            );
          }
        }
      }
      expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
      expect(calls.where((c) => c.method.contains('Permission')), isEmpty);
      final shown = calls.where((c) => c.method == 'show').toList();
      expect(shown, hasLength(3));
      expect(shown.map((c) => c.arguments['id']).toSet(), {2085});
      expect(shown.map((c) => c.arguments['body']), [
        'Pin HOMI còn 19%. Hãy sạc thiết bị.',
        'Pin HOMI còn 9%. Hãy sạc thiết bị.',
        'Pin HOMI còn 4%. Hãy sạc thiết bị ngay.',
      ]);
      expect(
        shown.last.arguments['platformSpecifics']['channelId'],
        'homi_battery_alerts',
      );
    },
  );

  test('permission denial is returned without throwing', () async {
    permission = false;
    expect(await H20BatteryNotifications().requestPermission(), isFalse);
    expect(calls.last.method, 'requestNotificationsPermission');
  });

  test('posting failure does not propagate into BLE event handling', () async {
    failShow = true;
    await H20BatteryNotifications().show(
      percent: 4,
      language: DisplayLanguage.vietnamese,
    );
    expect(calls.last.method, 'show');
  });

  test(
    'iOS initialization is silent and content follows app language',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      final notifications = H20BatteryNotifications();
      await notifications.show(
        percent: 9,
        language: DisplayLanguage.simplifiedChinese,
      );
      final settings = calls.first.arguments as Map;
      expect(settings['requestAlertPermission'], isFalse);
      expect(settings['requestSoundPermission'], isFalse);
      expect(settings['requestBadgePermission'], isFalse);
      expect(calls.last.arguments['body'], 'HOMI 电量剩余 9%。请为设备充电。');
      expect(await notifications.requestPermission(), isTrue);
      expect(calls.last.method, 'requestPermissions');
    },
  );

  test('unsupported desktop makes no platform calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final notifications = H20BatteryNotifications();
    await notifications.show(percent: 4, language: DisplayLanguage.vietnamese);
    expect(await notifications.requestPermission(), isTrue);
    expect(calls, isEmpty);
  });
}
