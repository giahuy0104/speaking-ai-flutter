import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/display_language.dart';

/// Immediate reminders from live HOMI telemetry. Does not schedule battery
/// estimates or request OS permission while handling a device event.
class H20BatteryNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<bool>? _initialization;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<bool> _initialize() => _initialization ??= _initializePlugin();

  Future<bool> _initializePlugin() async {
    if (!isSupported) return false;
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_battery_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      // On iOS initialize returns the permission result (false when prompts
      // are disabled), even though the plugin was successfully initialized.
      return defaultTargetPlatform == TargetPlatform.iOS || initialized == true;
    } catch (error) {
      debugPrint('Could not initialize HOMI battery notifications: $error');
      return false;
    }
  }

  /// Called only from the parent's explicit permission action in setup.
  Future<bool> requestPermission() async {
    if (!isSupported) return true;
    if (!await _initialize()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true, badge: false) ??
          false;
    } catch (error) {
      debugPrint('Could not request HOMI notification permission: $error');
      return false;
    }
  }

  static String message(
    int percent,
    DisplayLanguage language,
  ) => language.choose(
    'Pin HOMI còn $percent%. Hãy sạc thiết bị${percent < 5 ? ' ngay' : ''}.',
    'HOMI 电量剩余 $percent%。请${percent < 5 ? '立即' : ''}为设备充电。',
  );

  Future<void> show({
    required int percent,
    required DisplayLanguage language,
  }) async {
    if (!await _initialize()) return;
    try {
      await _plugin.show(
        // One tray entry, replaced as battery urgency increases. Separate from
        // the Android foreground learning service's ID (2084).
        id: 2085,
        title: language.choose('HOMI cần sạc pin', '请为 HOMI 充电'),
        body: message(percent, language),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'homi_battery_alerts',
            language.choose('Pin thiết bị HOMI', 'HOMI 设备电量'),
            channelDescription: language.choose(
              'Nhắc sạc khi pin HOMI dưới 20%, 10% và 5%.',
              'HOMI 电量低于 20%、10% 和 5% 时提醒充电。',
            ),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: false,
            presentBanner: true,
            presentList: true,
          ),
        ),
      );
    } catch (error) {
      // Notification denial/plugin failure must not interrupt BLE or learning.
      debugPrint('Could not show HOMI battery notification: $error');
    }
  }
}
