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

import '../support/onboarding_actions.dart';

void main() {
  final android = TargetPlatformVariant({TargetPlatform.android});

  testWidgets(
    'failed MAIN connection never opens or connects a microphone',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      app.hfpDevices = [
        {'id': 'headset-1', 'name': 'HM-D001', 'isConnected': true},
      ];
      await _openPermissionStep(tester);
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await _drainConnectionRound(tester);
      expect(app.count('scan'), greaterThan(0));
      expect(find.text('Chọn micro HOMI'), findsNothing);
      expect(app.hfpCalls.where((call) => call.method == 'connect'), isEmpty);
      expect(find.text('Chưa tìm thấy HOMI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'microphone picker waits until the pending MAIN connection succeeds',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      final connected = Completer<void>();
      app.scanDevices = [
        {
          'id': _NativeApp.deviceId,
          'name': 'HM-D001',
          'rssi': -35,
          'advertisesControlService': true,
        },
      ];
      app.bleConnect = () async {
        await connected.future;
        app.bleConnected = true;
        return app.bleStatus;
      };
      app.hfpDevices = [
        {'id': 'other-mic', 'name': 'Tai nghe Bluetooth', 'isConnected': false},
      ];
      await _openPermissionStep(tester);
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(app.count('connect'), 1);
      expect(find.text('Chọn micro HOMI'), findsNothing);
      expect(app.hfpCalls.where((call) => call.method == 'connect'), isEmpty);
      connected.complete();
      await _drainConnectionRound(tester);
      expect(find.text('Chọn micro HOMI'), findsOneWidget);
      expect(
        tester
            .widget<StartupSetupScreen>(find.byType(StartupSetupScreen))
            .h20BleConnected,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('parent-homi-microphone-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'microphone sheet scrolls on a small screen and rejects lost MAIN at text $scale',
      (tester) async {
        final app = await _pumpApp(
          tester,
          bleConnected: true,
          setupCompleted: false,
        );
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        app.hfpDevices = List.generate(
          15,
          (index) => {
            'id': 'headset-$index',
            'name': 'Tai nghe Bluetooth $index',
            'isConnected': false,
          },
        );
        await _openPermissionStep(tester);
        await tester.tap(find.byKey(const Key('startup-setup-h20')));
        await _drainConnectionRound(tester);
        expect(find.text('Chọn micro HOMI'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final list = find.byKey(const Key('parent-homi-microphone-list'));
        await tester.scrollUntilVisible(
          find.text('Tai nghe Bluetooth 14'),
          250,
          scrollable: find.descendant(
            of: list,
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Tai nghe Bluetooth 14'), findsOneWidget);
        expect(tester.takeException(), isNull);
        app.bleConnected = false;
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'ailingo_aiv0_ble_control/events',
          const StandardMethodCodec().encodeSuccessEnvelope(app.bleStatus),
          (_) {},
        );
        await tester.pumpAndSettle();
        final lastTile = find.ancestor(
          of: find.text('Tai nghe Bluetooth 14'),
          matching: find.byType(ListTile),
        );
        expect(tester.widget<ListTile>(lastTile).onTap, isNull);
        expect(app.hfpCalls.where((call) => call.method == 'connect'), isEmpty);
        await tester.tap(
          find.byKey(const Key('parent-homi-microphone-cancel')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Chọn micro HOMI'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: android,
    );
  }

  for (final radio in ['poweredOn', 'poweredOff']) {
    testWidgets('step 3 reads existing grants before showing UI: $radio', (
      tester,
    ) async {
      final app = await _pumpApp(
        tester,
        adapterState: radio,
        setupCompleted: false,
      );
      await _openPermissionStep(tester);
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(app.count('hasPermissions'), greaterThan(0));
      expect(app.count('requestPermissions'), 0);
      expect(app.count('scan'), 0);
      expect(app.microphoneCalls, isNotEmpty);
      expect(
        app.microphoneCalls.every(
          (call) => (call.arguments as Map)['request'] == false,
        ),
        isTrue,
      );
      expect(
        find.byKey(
          Key(
            radio == 'poweredOn'
                ? 'startup-setup-h20'
                : 'bluetooth-enable-switch',
          ),
        ),
        findsOneWidget,
      );
    }, variant: android);
  }

  testWidgets(
    'step 3 refreshes granted and revoked permissions on resume without prompting',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      app.microphoneGranted = false;
      await _openPermissionStep(tester);
      expect(find.text('Cấp quyền còn thiếu'), findsOneWidget);
      expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
      expect(app.count('requestPermissions'), 0);
      app.microphoneGranted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(find.byKey(const Key('startup-setup-h20')), findsOneWidget);
      app.microphoneGranted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Cấp quyền còn thiếu'), findsOneWidget);
      expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
      expect(app.count('requestPermissions'), 0);
      expect(app.count('scan'), 0);
      expect(
        app.microphoneCalls.every(
          (call) => (call.arguments as Map)['request'] == false,
        ),
        isTrue,
      );
    },
    variant: android,
  );

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
        await confirmVisibleOnboardingChoices(tester);
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
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('bluetooth-enable-switch')))
            .value,
        isTrue,
      );
    },
    variant: android,
  );

  testWidgets(
    'cancelled first-setup round cannot start scanning after permission returns',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      final permission = Completer<bool>();
      app.bluetoothGranted = false;
      app.permissionRequest = () => permission.future;
      final screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      final connection = screen.onSetupH20();
      await tester.pump();
      expect(app.count('requestPermissions'), greaterThan(0));
      await screen.onCancelH20Setup!();
      permission.complete(true);
      await tester.pumpAndSettle();
      expect(await connection, isFalse);
      expect(app.count('cancelConnectionAttempt'), greaterThan(0));
      expect(app.count('scan'), 0);
      expect(app.count('requestDualModeBond'), 0);
      expect(app.count('openBluetoothSettings'), 0);
      expect(find.byType(BottomSheet), findsNothing);
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
    'real first-setup callback rejects MAIN-only readiness without a blocking guidance popup',
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
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Kết nối thành công'), findsNothing);

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

Future<void> _openPermissionStep(WidgetTester tester) async {
  await confirmVisibleOnboardingChoices(tester);
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
  }
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
  final hfpCalls = <MethodCall>[];
  List<Map<String, Object?>> hfpDevices = [];
  List<Map<String, Object?>> scanDevices = [];
  Future<Map<String, Object?>> Function()? bleConnect;
  String adapterState;
  bool bleConnected;
  bool enableAccepted = false;
  bool microphoneGranted = true;
  bool? bluetoothGranted;
  final microphoneCalls = <MethodCall>[];
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
        if (name == 'com.llfbandit.record/messages' &&
            call.method == 'hasPermission') {
          microphoneCalls.add(call);
          if ((call.arguments as Map)['request'] == true) {
            microphoneGranted = true;
          }
          return microphoneGranted;
        }
        if (name == 'ailingo_hfp_audio') {
          hfpCalls.add(call);
          if (call.method == 'findDevices') return hfpDevices;
        }
        if (name == 'ailingo_aiv0_ble_control') {
          bleCalls.add(call);
          switch (call.method) {
            case 'initialize':
            case 'cancelConnectionAttempt':
              return bleStatus;
            case 'hasPermissions':
              return bluetoothGranted ??
                  [
                    'poweredOn',
                    'poweredOff',
                    'resetting',
                  ].contains(adapterState);
            case 'requestPermissions':
              return await permissionRequest?.call() ?? true;
            case 'bluetoothAdapterState':
              return adapterState;
            case 'requestEnableBluetooth':
              if (enableRequest != null) return enableRequest!();
              if (enableAccepted) adapterState = 'poweredOn';
              return enableAccepted;
            case 'connect':
              return await bleConnect?.call() ?? bleStatus;
            case 'requestDualModeBond':
              return true;
            case 'scan':
              if (adapterState != 'poweredOn') {
                throw PlatformException(code: 'BLUETOOTH_DISABLED');
              }
              return scanDevices;
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
