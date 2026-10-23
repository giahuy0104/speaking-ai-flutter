import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_history.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';
import 'package:ai_speaking_flutter_app/core/device/homi_connection_state.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_settings_port.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Bluetooth power controls fit phone Settings at 390x844', (
    tester,
  ) async {
    final textFont = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
    await Future.wait<void>(<Future<void>>[textFont.load(), iconFont.load()]);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var adapter = Aiv0BluetoothAdapterState.poweredOff;
    final power = BluetoothPowerController(
      readState: () async => adapter,
      requestEnable: () async {
        adapter = Aiv0BluetoothAdapterState.poweredOn;
        return true;
      },
      requestPermission: () async => true,
      canRequestEnable: true,
    );
    final coordinator = DeviceConnectionCoordinator(
      bluetoothPower: power,
      onConnect: () async => false,
      onCancel: () async {},
      onOpenBluetoothSettings: () async {},
    );
    addTearDown(coordinator.dispose);
    addTearDown(power.dispose);
    const captureKey = Key('bluetooth-settings-capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          onGenerateRoute: createAppRouter().onGenerateRoute,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: SettingsSheet(
              controller: _Settings(),
              connectionCoordinator: coordinator,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
    await tester.pumpAndSettle();
    for (final enabled in <bool>[false, true]) {
      if (enabled) {
        await _tapVisible(
          tester,
          find.byKey(const Key('bluetooth-enable-switch')),
        );
        await tester.pumpAndSettle();
      }
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('settings-hm-d001-group'))),
        alignment: 0.02,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-homi-connect')),
        enabled ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      const directory = String.fromEnvironment(
        'BLUETOOTH_SETTINGS_CAPTURE_DIR',
      );
      if (directory.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/bluetooth-${enabled ? 'on' : 'off'}-vi.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });

  for (final language in DisplayLanguage.values) {
    testWidgets(
      'Bluetooth power gates all connection actions in ${language.code}',
      (tester) async {
        var state = Aiv0BluetoothAdapterState.poweredOff;
        var enableCalls = 0;
        var connectCalls = 0;
        final pending = Completer<bool>();
        final power = BluetoothPowerController(
          readState: () async => state,
          requestEnable: () {
            enableCalls++;
            return pending.future;
          },
          requestPermission: () async => true,
          canRequestEnable: true,
        );
        final coordinator = DeviceConnectionCoordinator(
          bluetoothPower: power,
          onConnect: () async {
            connectCalls++;
            return false;
          },
          onCancel: () async {},
          onOpenBluetoothSettings: () async {},
        );
        addTearDown(coordinator.dispose);
        addTearDown(power.dispose);
        final settings = _Settings(language: language);
        coordinator.updateStatus(DeviceConnectionPhase.ready);
        await _openSettings(tester, settings, coordinator: coordinator);
        expect(find.byKey(const Key('settings-homi-connect')), findsNothing);
        expect(
          find.text(language.choose('HOMI đã sẵn sàng', 'HOMI 已就绪')),
          findsNothing,
        );
        coordinator.updateStatus(DeviceConnectionPhase.disconnected);
        await tester.pump();
        expect(
          find.text(language.choose('Bluetooth đang tắt', '蓝牙已关闭')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip ==
                          language.choose('Quét và kết nối', '扫描并连接'),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  language.choose('Chọn mic', '选择麦克风'),
                ),
              )
              .onPressed,
          isNull,
        );
        final toggle = find.byKey(const Key('bluetooth-enable-switch'));
        await _tapVisible(tester, toggle);
        await tester.pump();
        expect(enableCalls, 1);
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        expect(connectCalls, 0);
        state = Aiv0BluetoothAdapterState.poweredOn;
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('settings-homi-connect')), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip ==
                          language.choose('Quét và kết nối', '扫描并连接'),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  language.choose('Chọn mic', '选择麦克风'),
                ),
              )
              .onPressed,
          isNotNull,
        );
        await _tapVisible(
          tester,
          find.byKey(const Key('settings-homi-connect')),
        );
        await tester.pumpAndSettle();
        expect(connectCalls, 1);
        expect(settings.scanCalls, 0);
        expect(settings.findCalls, 0);
      },
    );
  }

  for (final language in DisplayLanguage.values) {
    final unknown = language.choose('Thiết bị không xác định', '未知设备');
    testWidgets('BLE picker localizes unknown name in ${language.code}', (
      tester,
    ) async {
      final controller = _Settings(language: language)
        ..bleDevices = const <Aiv0BleDevice>[
          Aiv0BleDevice(id: 'unknown-ble', name: '', rssi: -30),
          Aiv0BleDevice(
            id: 'homi-ble',
            name: 'HM-D001',
            rssi: -60,
            advertisesControlService: true,
          ),
        ];
      await _openSettings(tester, controller);
      await _tapVisible(
        tester,
        find.byTooltip(language.choose('Quét và kết nối', '扫描并连接')),
      );
      await tester.pumpAndSettle();
      expect(find.text(unknown), findsOneWidget);
      expect(find.text('HM-D001'), findsNothing);
      expect(
        tester.getTopLeft(find.text('HM-D001')).dy,
        lessThan(tester.getTopLeft(find.text(unknown)).dy),
      );
      await tester.tap(find.text(unknown));
      await tester.pumpAndSettle();
      expect(controller.connectedBle?.id, 'unknown-ble');
    });

    testWidgets(
      'microphone picker localizes unknown name in ${language.code}',
      (tester) async {
        final controller = _Settings(language: language)
          ..microphones = const <HfpAudioDevice>[
            HfpAudioDevice(id: 'anonymous-mic', name: '', isConnected: true),
          ];
        await _openSettings(tester, controller);
        await _tapVisible(
          tester,
          find.text(language.choose('Chọn mic', '选择麦克风')),
        );
        await tester.pumpAndSettle();
        expect(find.text(unknown), findsOneWidget);
        expect(find.text('anonymous-mic'), findsNothing);
        await tester.tap(find.text(unknown));
        await tester.pumpAndSettle();
        expect(controller.connectedMicrophone?.id, 'anonymous-mic');
      },
    );

    testWidgets('last BLE and microphone stay visible in ${language.code}', (
      tester,
    ) async {
      final controller = _Settings(language: language)
        ..lastConnectedBleDevice = ConnectionDeviceRecord(
          id: 'last-ble',
          name: '',
          transport: ConnectionDeviceTransport.ble,
          connectedAt: DateTime.utc(2026, 10, 19, 3),
        )
        ..lastConnectedMicrophone = ConnectionDeviceRecord(
          id: 'last-mic',
          name: 'AirPods',
          transport: ConnectionDeviceTransport.hfp,
          connectedAt: DateTime.utc(2026, 10, 19, 4),
        );
      await _openSettings(tester, controller);
      expect(find.byKey(const Key('settings-last-ble-device')), findsOneWidget);
      expect(find.byKey(const Key('settings-last-microphone')), findsOneWidget);
      expect(find.textContaining(unknown), findsOneWidget);
      expect(find.textContaining('AirPods'), findsOneWidget);
      expect(find.textContaining('last-ble'), findsOneWidget);
      expect(find.textContaining('last-mic'), findsOneWidget);
    });
  }

  testWidgets(
    'shared connection summary supports search cancel retry and Bluetooth settings',
    (tester) async {
      final pending = Completer<bool>();
      var attempts = 0;
      var cancellations = 0;
      var settingsCalls = 0;
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () {
          attempts++;
          return attempts == 1 ? pending.future : Future<bool>.value(false);
        },
        onCancel: () async {
          cancellations++;
        },
        onOpenBluetoothSettings: () async {
          settingsCalls++;
        },
      );
      addTearDown(coordinator.dispose);
      await _openSettings(tester, _Settings(), coordinator: coordinator);
      await _tapVisible(tester, find.byKey(const Key('settings-homi-connect')));
      await tester.pump();
      expect(attempts, 1);
      expect(find.text('Đang tìm thiết bị…'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('settings-homi-cancel')));
      await tester.pumpAndSettle();
      expect(cancellations, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('HOMI đã sẵn sàng'), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('settings-homi-connect')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Thử lại'), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const Key('settings-open-bluetooth-settings')),
      );
      await tester.pumpAndSettle();
      expect(settingsCalls, 1);
    },
  );

  testWidgets(
    'shared coordinator owns manual scan and ignores results after cancel',
    (tester) async {
      final pending = Completer<List<Aiv0BleDevice>>();
      final controller = _Settings()..scanFuture = pending.future;
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => false,
        onCancel: controller.cancelManualDeviceConnection,
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      await _openSettings(tester, controller, coordinator: coordinator);
      await _tapVisible(tester, find.byTooltip('Quét và kết nối'));
      await tester.pump();
      expect(coordinator.hasManualOperation, isTrue);
      expect(controller.scanCalls, 1);
      await _tapVisible(tester, find.byKey(const Key('settings-homi-cancel')));
      await tester.pumpAndSettle();
      pending.complete(const <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'late', name: 'Late', rssi: -30),
      ]);
      await tester.pumpAndSettle();
      expect(coordinator.hasManualOperation, isFalse);
      expect(find.text('Late'), findsNothing);
      expect(controller.cancelCalls, 2);
    },
  );

  testWidgets(
    'shared state descriptions are translated and show ready only on readiness',
    (tester) async {
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => false,
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      await _openSettings(
        tester,
        _Settings(language: DisplayLanguage.simplifiedChinese),
        coordinator: coordinator,
      );
      const labels = <DeviceConnectionPhase, String>{
        DeviceConnectionPhase.searching: '正在查找设备…',
        DeviceConnectionPhase.connecting: '正在连接设备…',
        DeviceConnectionPhase.preparingMicrophone: '设备已连接，正在准备麦克风…',
        DeviceConnectionPhase.failed: '设备和麦克风尚未全部连接，请重试。',
        DeviceConnectionPhase.ready: 'HOMI 已就绪',
      };
      for (final entry in labels.entries) {
        coordinator.updateStatus(entry.key);
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget);
        if (entry.key != DeviceConnectionPhase.ready) {
          expect(find.text('HOMI 已就绪'), findsNothing);
        }
      }
    },
  );

  testWidgets(
    'phone Settings connection card stays scrollable with recent devices',
    (tester) async {
      final textFont = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
      await Future.wait<void>(<Future<void>>[textFont.load(), iconFont.load()]);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _Settings()
        ..lastConnectedBleDevice = ConnectionDeviceRecord(
          id: 'AA:BB:CC:DD:EE:FF',
          name: 'HM-D001',
          transport: ConnectionDeviceTransport.ble,
          connectedAt: DateTime(2026, 10, 19, 15, 30).toUtc(),
        )
        ..lastConnectedMicrophone = ConnectionDeviceRecord(
          id: 'recent-microphone',
          name: '',
          transport: ConnectionDeviceTransport.hfp,
          connectedAt: DateTime(2026, 10, 19, 15, 32).toUtc(),
        );
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => false,
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      coordinator.updateStatus(DeviceConnectionPhase.failed);
      const captureKey = Key('settings-device-ui-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            onGenerateRoute: createAppRouter().onGenerateRoute,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: Scaffold(
              body: SettingsSheet(
                controller: controller,
                connectionCoordinator: coordinator,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('settings-hm-d001-group'))),
        alignment: 0.02,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-homi-connect')), findsOneWidget);
      expect(find.byKey(const Key('settings-last-microphone')), findsOneWidget);
      expect(tester.takeException(), isNull);
      const capturePath = String.fromEnvironment('SETTINGS_UI_CAPTURE_PATH');
      if (capturePath.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(capturePath).parent.create(recursive: true);
          await File(capturePath).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets(
    'selected unassociated microphone can be replaced without deselecting first',
    (tester) async {
      final controller = _Settings()
        ..microphoneSelected = true
        ..aiv0BleStatus = const Aiv0BleStatus(
          phase: Aiv0BlePhase.connected,
          protocolConfirmed: true,
          deviceId: 'ble-id',
          deviceName: 'HM-D001',
        )
        ..microphones = const <HfpAudioDevice>[
          HfpAudioDevice(id: 'hfp-id', name: 'HM-D001', isConnected: true),
        ]
        ..confirmationRequired = true;
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => false,
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(coordinator.dispose);
      coordinator.updateStatus(DeviceConnectionPhase.failed);
      await _openSettings(tester, controller, coordinator: coordinator);
      await _tapVisible(
        tester,
        find.byKey(const Key('settings-confirm-homi-microphone')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _tapVisible(tester, find.text('HM-D001'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Đúng thiết bị HOMI'));
      await tester.pumpAndSettle();
      expect(controller.confirmedAssociation, isTrue);
    },
  );

  testWidgets('busy connection never displays success', (tester) async {
    final controller = _Settings()
      ..bleDevices = const <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'homi', name: 'HM-D001', rssi: -30),
      ]
      ..bleResult = const DeviceConnectionResult(DeviceConnectionOutcome.busy);
    await _openSettings(tester, controller);
    await _tapVisible(tester, find.byTooltip('Quét và kết nối'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HM-D001'));
    await tester.pumpAndSettle();
    expect(find.text('Đã kết nối thiết bị điều khiển.'), findsNothing);
    expect(find.text('Ứng dụng đang bận. Hãy thử lại sau.'), findsWidgets);
  });

  testWidgets(
    'cancelled discovery ignores late devices and permits fresh search',
    (tester) async {
      final pending = Completer<List<Aiv0BleDevice>>();
      final controller = _Settings()..scanFuture = pending.future;
      await _openSettings(tester, controller);
      await _tapVisible(tester, find.byTooltip('Quét và kết nối'));
      await tester.pump();
      expect(controller.scanCalls, 1);
      await _tapVisible(
        tester,
        find.byKey(const Key('settings-device-manual-cancel')),
      );
      await tester.pumpAndSettle();
      expect(controller.cancelCalls, 1);
      pending.complete(const <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'late', name: 'Late', rssi: -30),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Late'), findsNothing);
      expect(controller.connectedBle, isNull);
      controller.scanFuture = null;
      await _tapVisible(tester, find.byTooltip('Quét và kết nối'));
      await tester.pumpAndSettle();
      expect(controller.scanCalls, 2);
    },
  );

  testWidgets('repeated taps cannot open overlapping discovery', (
    tester,
  ) async {
    final pending = Completer<List<HfpAudioDevice>>();
    final controller = _Settings()..findFuture = pending.future;
    await _openSettings(tester, controller);
    await _tapVisible(tester, find.text('Chọn mic'));
    await tester.tap(find.text('Chọn mic'));
    await tester.pump();
    expect(controller.findCalls, 1);
    await _tapVisible(
      tester,
      find.byKey(const Key('settings-device-manual-cancel')),
    );
    pending.complete(const <HfpAudioDevice>[]);
    await tester.pumpAndSettle();
    expect(find.text('Chưa có thiết bị HFP'), findsNothing);
  });

  testWidgets(
    'closing Settings cancels owned discovery without opening a late picker',
    (tester) async {
      final pending = Completer<List<Aiv0BleDevice>>();
      final controller = _Settings()..scanFuture = pending.future;
      await _openSettings(tester, controller);
      await _tapVisible(tester, find.byTooltip('Quét và kết nối'));
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: createAppRouter().onGenerateRoute,
          home: Scaffold(body: Text('Closed')),
        ),
      );
      expect(controller.cancelCalls, 1);
      pending.complete(const <Aiv0BleDevice>[
        Aiv0BleDevice(id: 'late', name: 'Late', rssi: -30),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Late'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different microphone identity needs explicit HOMI confirmation',
    (tester) async {
      final controller = _Settings()
        ..aiv0BleStatus = const Aiv0BleStatus(
          phase: Aiv0BlePhase.connected,
          protocolConfirmed: true,
          deviceId: 'ble-id',
          deviceName: 'HM-D001',
        )
        ..microphones = const <HfpAudioDevice>[
          HfpAudioDevice(id: 'hfp-id', name: 'HM-D001', isConnected: true),
        ]
        ..confirmationRequired = true;
      await _openSettings(tester, controller);
      await _tapVisible(tester, find.text('Chọn mic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HM-D001'));
      await tester.pumpAndSettle();
      expect(controller.connectedMicrophone, isNull);
      await tester.tap(find.text('Đúng thiết bị HOMI'));
      await tester.pumpAndSettle();
      expect(controller.confirmedAssociation, isTrue);
    },
  );
  for (final switchedDevice in <bool>[false, true]) {
    testWidgets(
      'microphone confirmation is rejected when BLE ${switchedDevice ? 'changes' : 'disconnects'} while dialog is open',
      (tester) async {
        final controller = _Settings()
          ..aiv0BleStatus = const Aiv0BleStatus(
            phase: Aiv0BlePhase.connected,
            protocolConfirmed: true,
            deviceId: 'ble-first',
            deviceName: 'HM-D001',
          )
          ..microphones = const <HfpAudioDevice>[
            HfpAudioDevice(id: 'hfp-id', name: 'HM-D001', isConnected: true),
          ]
          ..confirmationRequired = true;
        await _openSettings(tester, controller);
        await _tapVisible(tester, find.text('Chọn mic'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('HM-D001'));
        await tester.pumpAndSettle();
        expect(find.text('Xác nhận micro HOMI'), findsOneWidget);
        controller.aiv0BleStatus = switchedDevice
            ? const Aiv0BleStatus(
                phase: Aiv0BlePhase.connected,
                protocolConfirmed: true,
                deviceId: 'ble-second',
                deviceName: 'HM-D001',
              )
            : const Aiv0BleStatus(
                phase: Aiv0BlePhase.idle,
                protocolConfirmed: false,
              );
        controller.notifyListeners();
        await tester.pump();
        await tester.tap(find.text('Đúng thiết bị HOMI'));
        await tester.pumpAndSettle();
        expect(controller.connectedMicrophone, isNull);
        expect(controller.confirmedAssociation, isFalse);
        expect(
          find.text(
            'Thiết bị chưa khả dụng. Hãy kiểm tra kết nối Bluetooth rồi thử lại.',
          ),
          findsWidgets,
        );
      },
    );
  }
}

Future<void> _openSettings(
  WidgetTester tester,
  _Settings controller, {
  DeviceConnectionCoordinator? coordinator,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: createAppRouter().onGenerateRoute,
      theme: buildAppTheme(),
      home: Scaffold(
        body: SettingsSheet(
          controller: controller,
          connectionCoordinator: coordinator,
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

class _Settings extends ChangeNotifier implements ConversationSettingsPort {
  _Settings({DisplayLanguage language = DisplayLanguage.vietnamese})
    : displayLanguage = language;
  @override
  DisplayLanguage displayLanguage;
  @override
  int get childAge => 6;
  @override
  bool get isBusy => false;
  @override
  bool get isDeviceConnectionBusy => false;
  bool microphoneSelected = false;
  @override
  bool get usesHfpInput => microphoneSelected;
  @override
  bool get supportsBrowserHfp => false;
  @override
  bool get canUseAiv0Ble => true;
  @override
  Aiv0BleStatus aiv0BleStatus = const Aiv0BleStatus(
    phase: Aiv0BlePhase.idle,
    protocolConfirmed: false,
  );
  @override
  BluetoothAudioStatus get hfpAudioStatus =>
      const BluetoothAudioStatus(phase: BluetoothAudioConnectionPhase.idle);
  @override
  ConnectionDeviceRecord? lastConnectedBleDevice;
  @override
  ConnectionDeviceRecord? lastConnectedMicrophone;
  @override
  HomiConnectionState homiConnectionState({bool mainTurnActive = false}) =>
      HomiConnectionState.from(
        hfpStatus: hfpAudioStatus,
        bleStatus: aiv0BleStatus,
        hfpInputSelected: false,
      );

  List<Aiv0BleDevice> bleDevices = const <Aiv0BleDevice>[];
  List<HfpAudioDevice> microphones = const <HfpAudioDevice>[];
  Future<List<Aiv0BleDevice>>? scanFuture;
  Future<List<HfpAudioDevice>>? findFuture;
  int scanCalls = 0;
  int findCalls = 0;
  int cancelCalls = 0;
  Aiv0BleDevice? connectedBle;
  HfpAudioDevice? connectedMicrophone;
  bool confirmationRequired = false;
  bool confirmedAssociation = false;
  DeviceConnectionResult bleResult = const DeviceConnectionResult(
    DeviceConnectionOutcome.success,
  );

  @override
  Future<List<Aiv0BleDevice>> scanAiv0Devices() async {
    scanCalls++;
    return await (scanFuture ?? Future.value(bleDevices));
  }

  @override
  Future<List<HfpAudioDevice>> findHfpDevices() async {
    findCalls++;
    return await (findFuture ?? Future.value(microphones));
  }

  @override
  Future<DeviceConnectionResult> connectAiv0Device(Aiv0BleDevice device) async {
    connectedBle = device;
    return bleResult;
  }

  @override
  Future<DeviceConnectionResult> connectHfpDevice(
    HfpAudioDevice device, {
    bool confirmHomiAssociation = false,
  }) async {
    connectedMicrophone = device;
    confirmedAssociation = confirmHomiAssociation;
    return const DeviceConnectionResult(DeviceConnectionOutcome.success);
  }

  @override
  bool requiresHomiMicrophoneConfirmation(HfpAudioDevice device) =>
      confirmationRequired;
  @override
  Future<void> cancelManualDeviceConnection() async {
    cancelCalls++;
  }

  @override
  void setDisplayLanguage(DisplayLanguage language) {
    displayLanguage = language;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
