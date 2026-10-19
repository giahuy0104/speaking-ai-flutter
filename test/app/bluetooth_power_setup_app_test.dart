import 'dart:async';
import 'dart:io';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final android = TargetPlatformVariant({TargetPlatform.android});

  testWidgets(
    'first setup requests nearby permission then system Bluetooth enable in app',
    (tester) async {
      final app = await _pumpApp(
        tester,
        adapterState: 'unauthorized',
        setupCompleted: false,
      );
      for (var i = 0; i < 2; i++) {
        final next = find.byKey(const Key('startup-next'));
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      app.permissionRequest = () async {
        app.adapterState = 'poweredOff';
        return true;
      };
      tester
          .widget<StartupSetupScreen>(find.byType(StartupSetupScreen))
          .onRetryPermissions();
      await tester.pumpAndSettle();
      expect(app.count('requestPermissions'), 1);
      expect(app.count('openPermissionSettings'), 0);
      expect(app.count('openBluetoothSettings'), 0);
      app.enableAccepted = true;
      final toggle = find.byKey(const Key('bluetooth-enable-switch'));
      expect(toggle, findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(app.count('requestEnableBluetooth'), 1);
      expect(app.count('openPermissionSettings'), 0);
      expect(app.count('openBluetoothSettings'), 0);
      expect(find.byKey(const Key('bluetooth-enable-switch')), findsNothing);
    },
    variant: android,
  );

  testWidgets(
    'startup and resume wait for Bluetooth before scanning and do not spend retry window',
    (tester) async {
      final app = await _pumpApp(tester, adapterState: 'poweredOff');
      expect(app.count('scan'), 0);
      await app.openSettings();
      final enable = Completer<bool>();
      app.enableRequest = () {
        app.adapterState = 'resetting';
        return enable.future;
      };
      final toggle = find.byKey(const Key('bluetooth-enable-switch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      // Android resumes the Activity before the radio finishes turning on.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(app.count('requestEnableBluetooth'), 1);
      expect(app.count('scan'), 0);
      expect(find.byKey(const Key('settings-homi-connect')), findsNothing);

      app.adapterState = 'poweredOn';
      enable.complete(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-homi-connect')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // No 10/60-second penalty for the skipped off/turning-on rounds.
      expect(app.count('scan'), 1);
      expect(app.count('requestDualModeBond'), 0);
    },
    variant: android,
  );

  testWidgets(
    'late radio-on event reveals Connect without reopening Settings or retrying scan',
    (tester) async {
      final app = await _pumpApp(tester, adapterState: 'poweredOff');
      await app.openSettings();
      app.enableRequest = () async {
        app.adapterState = 'resetting';
        return false;
      };
      final toggle = find.byKey(const Key('bluetooth-enable-switch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byKey(const Key('settings-homi-connect')), findsNothing);
      expect(app.count('scan'), 0);
      // STATE_ON arrives later than the bounded power-controller polling.
      app.adapterState = 'poweredOn';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'ailingo_aiv0_ble_control/events',
        const StandardMethodCodec().encodeSuccessEnvelope(app.bleStatus),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-homi-connect')), findsOneWidget);
      expect(app.count('requestEnableBluetooth'), 1);
      expect(app.count('scan'), 0);
      expect(app.count('requestDualModeBond'), 0);
    },
    variant: android,
  );

  for (final accepted in [false, true]) {
    testWidgets(
      'Android enable ${accepted ? 'reveals connect after adapter turns on' : 'cancellation keeps connect hidden'} without opening Settings',
      (tester) async {
        final app = await _pumpApp(tester, adapterState: 'poweredOff');
        app.enableAccepted = accepted;
        await app.openSettings();
        expect(find.byKey(const Key('settings-homi-connect')), findsNothing);
        final toggle = find.byKey(const Key('bluetooth-enable-switch'));
        expect(toggle, findsOneWidget);
        expect(app.count('bluetoothAdapterState'), greaterThan(0));
        expect(app.count('readBluetoothAdapterState'), 0);

        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(app.count('requestEnableBluetooth'), 1);
        expect(app.count('openBluetoothSettings'), 0);
        expect(
          find.byKey(const Key('settings-homi-connect')),
          accepted ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('bluetooth-enable-switch')),
          accepted ? findsNothing : findsOneWidget,
        );
        expect(app.count('requestDualModeBond'), 0);
      },
      variant: android,
    );
  }

  testWidgets(
    'explicit HOMI connection pairs existing MAIN but does not claim ready without HFP',
    (tester) async {
      final app = await _pumpApp(tester, bleConnected: true);
      await app.openSettings();
      final sheet = tester.widget<SettingsSheet>(find.byType(SettingsSheet));
      expect(sheet.controller.aiv0BleStatus.isConnected, isTrue);
      expect(sheet.controller.h20ConnectionState().isH20Ready, isFalse);
      // Background MAIN/HFP recovery must not open a system-pairing dialog.
      expect(app.count('requestDualModeBond'), 0);
      app.bleCalls.clear();

      final connect = find.byKey(const Key('settings-homi-connect'));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await _drainConnectionRound(tester);

      expect(app.count('requestDualModeBond'), 1);
      expect(
        (app.bleCalls
                .singleWhere((call) => call.method == 'requestDualModeBond')
                .arguments
            as Map)['deviceId'],
        _NativeApp.deviceId,
      );
      expect(app.count('connect'), 0);
      expect(app.count('scan'), 0);
      expect(app.count('disconnect'), 0);
      expect(sheet.connectionCoordinator!.phase, DeviceConnectionPhase.failed);
      expect(sheet.controller.h20ConnectionState().isH20Ready, isFalse);
      expect(find.text('HOMI đã sẵn sàng'), findsNothing);
      expect(find.text('Kết nối thành công'), findsNothing);
      expect(find.text('Mic chưa kết nối'), findsWidgets);
    },
    variant: android,
  );

  testWidgets(
    'real first-setup callback rejects MAIN-only readiness after microphone guidance is dismissed',
    (tester) async {
      final app = await _pumpApp(
        tester,
        bleConnected: true,
        setupCompleted: false,
      );
      var screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(screen.h20BleConnected, isTrue);
      expect(screen.h20HfpConfigured, isFalse);
      final connection = screen.onSetupH20();
      await _drainConnectionRound(tester);
      expect(find.text('Chưa tìm thấy micro HOMI'), findsOneWidget);
      expect(find.text('Kết nối thành công'), findsNothing);
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();

      expect(await connection, isFalse);
      screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(screen.h20HfpConfigured, isFalse);
      expect(
        find.byKey(const Key('startup-connection-success-dialog')),
        findsNothing,
      );
      expect(app.count('requestDualModeBond'), 1);
      expect(app.count('openBluetoothSettings'), 0);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'homi.parent-setup.version',
        ),
        isNull,
      );
    },
    variant: android,
  );
}

Future<void> _drainConnectionRound(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pumpAndSettle();
}

Future<_NativeApp> _pumpApp(
  WidgetTester tester, {
  String adapterState = 'poweredOn',
  bool bleConnected = false,
  bool setupCompleted = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'innotrik.child-age.v1': 6,
    if (setupCompleted) 'homi.parent-setup.version': 1,
    'innotrik.user-onboarding.version': 1,
    'homi.parental-privacy-consent.version': 3,
  });
  final app = _NativeApp(
    tester,
    adapterState: adapterState,
    bleConnected: bleConnected,
  );
  app.installChannels();
  addTearDown(app.close);
  await tester.pumpWidget(const AiSpeakingApp());
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 15));
  await tester.pumpAndSettle();
  return app;
}

class _NativeApp {
  _NativeApp(
    this.tester, {
    required this.adapterState,
    required this.bleConnected,
  });

  static const deviceId = 'AA:BB:CC:DD:EE:FF';
  static const channels = <String>[
    'ailingo_aiv0_ble_control',
    'ailingo_aiv0_ble_control/events',
    'ailingo_hfp_audio',
    'ailingo_hfp_audio/events',
    'ailingo_background_learning',
    'ailingo_background_learning/events',
    'dexterous.com/flutter/local_notifications',
    'ailingo_speech',
    'ailingo_speech/events',
    'ailingo_voice_prompt',
    'ailingo_offline_intent',
    'com.llfbandit.record/messages',
    'com.ryanheise.audio_session',
    'plugins.flutter.io/path_provider',
  ];
  final WidgetTester tester;
  final supportDirectory = Directory.systemTemp.createTempSync(
    'homi-power-app-test-',
  );
  final bleCalls = <MethodCall>[];
  String adapterState;
  bool bleConnected;
  bool enableAccepted = false;
  Future<bool> Function()? enableRequest;
  Future<bool> Function()? permissionRequest;
  bool _closed = false;

  int count(String method) =>
      bleCalls.where((call) => call.method == method).length;

  Map<String, Object?> get bleStatus => <String, Object?>{
    'phase': bleConnected ? 'connected' : 'idle',
    if (bleConnected) 'deviceId': deviceId,
    if (bleConnected) 'deviceName': 'HM-D001',
  };

  void installChannels() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (name == 'dexterous.com/flutter/local_notifications') {
          return call.method == 'show' ? null : true;
        }
        if (name == 'plugins.flutter.io/path_provider') {
          return supportDirectory.path;
        }
        if (name == 'ailingo_aiv0_ble_control') {
          bleCalls.add(call);
          switch (call.method) {
            case 'initialize':
            case 'cancelConnectionAttempt':
              return bleStatus;
            case 'requestPermissions':
              return await permissionRequest?.call() ?? true;
            case 'bluetoothAdapterState':
              return adapterState;
            case 'requestEnableBluetooth':
              if (enableRequest != null) return enableRequest!();
              if (enableAccepted) adapterState = 'poweredOn';
              return enableAccepted;
            case 'requestDualModeBond':
              return true;
            case 'scan':
              if (adapterState != 'poweredOn') {
                throw PlatformException(code: 'BLUETOOTH_DISABLED');
              }
              return <Object?>[];
          }
        }
        return switch (call.method) {
          'initialize' => <String, Object?>{'phase': 'idle'},
          'findDevices' => <Object?>[],
          'requestPermissions' ||
          'hasPermission' ||
          'requestNotificationPermission' => true,
          _ => null,
        };
      });
    }
  }

  Future<void> openSettings() async {
    tester
        .widget<ConversationScreen>(find.byType(ConversationScreen))
        .onOpenSettings();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-audio-h20-section')));
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    for (final name in channels) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  }
}
