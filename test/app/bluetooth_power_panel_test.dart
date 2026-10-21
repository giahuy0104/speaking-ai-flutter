import 'dart:async';

import 'package:ai_speaking_flutter_app/app/bluetooth_power_panel.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in DisplayLanguage.values) {
    testWidgets('checks before showing actions in ${language.code}', (
      tester,
    ) async {
      final result = Completer<Aiv0BluetoothAdapterState>();
      final power = _power(read: () => result.future);
      addTearDown(power.dispose);
      await _pump(tester, power, language);
      await tester.pump();
      expect(
        find.text(language.choose('Đang kiểm tra Bluetooth…', '正在检查蓝牙…')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(power.canConnect, isFalse);
      result.complete(Aiv0BluetoothAdapterState.poweredOn);
      await tester.pumpAndSettle();
      expect(
        find.text(language.choose('Bluetooth đã bật', '蓝牙已开启')),
        findsOneWidget,
      );
      expect(power.canConnect, isTrue);
    });

    testWidgets('unsupported has no enable action in ${language.code}', (
      tester,
    ) async {
      final power = _power(
        read: () async => Aiv0BluetoothAdapterState.unsupported,
      );
      addTearDown(power.dispose);
      await _pump(tester, power, language);
      await tester.pumpAndSettle();
      expect(
        find.text(
          language.choose('Máy này không hỗ trợ Bluetooth', '此设备不支持蓝牙'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(power.canConnect, isFalse);
    });

    testWidgets(
      'cancelled enable stays off without opening settings in ${language.code}',
      (tester) async {
        var calls = 0;
        final enableResult = Completer<bool>();
        var permissionSettingsCalls = 0;
        final power = _power(
          read: () async => Aiv0BluetoothAdapterState.poweredOff,
          enable: () {
            calls++;
            return enableResult.future;
          },
          permissionSettings: () async {
            permissionSettingsCalls++;
            return true;
          },
        );
        addTearDown(power.dispose);
        await _pump(tester, power, language);
        await tester.pumpAndSettle();
        final toggle = find.byKey(const Key('bluetooth-enable-switch'));
        await tester.tap(toggle);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        enableResult.complete(false);
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(permissionSettingsCalls, 0);
        expect(
          find.byKey(const Key('bluetooth-open-permission-settings')),
          findsNothing,
        );
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
        expect(power.canConnect, isFalse);
        expect(
          find.byKey(const Key('bluetooth-action-failed')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'iOS explains system limitation and refreshes on resume in ${language.code}',
      (tester) async {
        var state = Aiv0BluetoothAdapterState.poweredOff;
        var reads = 0;
        var enableCalls = 0;
        final power = _power(
          read: () async {
            reads++;
            return state;
          },
          enable: () async {
            enableCalls++;
            return false;
          },
          canEnable: false,
        );
        addTearDown(power.dispose);
        await _pump(tester, power, language);
        await tester.pumpAndSettle();
        expect(find.byType(SwitchListTile), findsNothing);
        expect(
          find.textContaining(language.choose('Trung tâm điều khiển', '控制中心')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('bluetooth-refresh')), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        state = Aiv0BluetoothAdapterState.poweredOn;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(enableCalls, 0);
        expect(power.canConnect, isTrue);
        expect(
          find.text(language.choose('Bluetooth đã bật', '蓝牙已开启')),
          findsOneWidget,
        );
      },
    );

    testWidgets('resetting can refresh to powered on in ${language.code}', (
      tester,
    ) async {
      var state = Aiv0BluetoothAdapterState.resetting;
      final power = _power(read: () async => state);
      addTearDown(power.dispose);
      await _pump(tester, power, language);
      await tester.pump();
      expect(power.hasChecked, isTrue);
      expect(power.canConnect, isFalse);
      final refresh = find.byKey(const Key('bluetooth-refresh'));
      expect(refresh, findsOneWidget);
      expect(tester.widget<TextButton>(refresh).onPressed, isNotNull);
      state = Aiv0BluetoothAdapterState.poweredOn;
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(power.canConnect, isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text(language.choose('Bluetooth đã bật', '蓝牙已开启')),
        findsOneWidget,
      );
    });

    testWidgets(
      'blocked Bluetooth permission offers app permission settings in ${language.code}',
      (tester) async {
        var state = Aiv0BluetoothAdapterState.unauthorized;
        var permissionCalls = 0;
        var settingsCalls = 0;
        var enableCalls = 0;
        final power = _power(
          read: () async => state,
          permission: () async {
            permissionCalls++;
            return false;
          },
          enable: () async {
            enableCalls++;
            return false;
          },
          permissionRequiresSettings: () async => permissionCalls > 0,
          permissionSettings: () async {
            settingsCalls++;
            return true;
          },
        );
        addTearDown(power.dispose);
        await _pump(tester, power, language);
        await tester.pumpAndSettle();
        final settings = find.byKey(
          const Key('bluetooth-open-permission-settings'),
        );
        expect(settings, findsNothing);
        await tester.tap(find.byKey(const Key('bluetooth-authorize')));
        await tester.pumpAndSettle();
        expect(permissionCalls, 1);
        expect(settings, findsOneWidget);
        expect(
          find.text(language.choose('Mở cài đặt quyền HOMI', '打开 HOMI 权限设置')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('bluetooth-authorize')));
        await tester.pumpAndSettle();
        expect(permissionCalls, 2);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(settingsCalls, 1);
        expect(enableCalls, 0);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        state = Aiv0BluetoothAdapterState.poweredOn;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(power.canConnect, isTrue);
        expect(settings, findsNothing);
        expect(find.byKey(const Key('bluetooth-authorize')), findsNothing);
      },
    );

    testWidgets(
      'ordinary denial stays in app and can prompt again in ${language.code}',
      (tester) async {
        var state = Aiv0BluetoothAdapterState.unauthorized;
        var requests = 0;
        var settings = 0;
        final power = _power(
          read: () async => state,
          permissionRequiresSettings: () async => false,
          permission: () async {
            if (++requests == 1) return false;
            state = Aiv0BluetoothAdapterState.poweredOff;
            return true;
          },
          permissionSettings: () async {
            settings++;
            return true;
          },
        );
        addTearDown(power.dispose);
        await _pump(tester, power, language);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('bluetooth-authorize')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('bluetooth-open-permission-settings')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('bluetooth-authorize')));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(settings, 0);
        expect(
          find.byKey(const Key('bluetooth-enable-switch')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'permission action transitions to Bluetooth toggle in ${language.code}',
      (tester) async {
        var state = Aiv0BluetoothAdapterState.unauthorized;
        var permissionCalls = 0;
        final power = _power(
          read: () async => state,
          permission: () async {
            permissionCalls++;
            state = Aiv0BluetoothAdapterState.poweredOff;
            return true;
          },
        );
        addTearDown(power.dispose);
        await _pump(tester, power, language);
        await tester.pumpAndSettle();
        expect(find.byType(SwitchListTile), findsNothing);
        await tester.tap(find.byKey(const Key('bluetooth-authorize')));
        await tester.pumpAndSettle();
        expect(permissionCalls, 1);
        expect(
          find.byKey(const Key('bluetooth-enable-switch')),
          findsOneWidget,
        );
        expect(power.canConnect, isFalse);
      },
    );
  }
}

BluetoothPowerController _power({
  required Future<Aiv0BluetoothAdapterState> Function() read,
  Future<bool> Function()? enable,
  Future<bool> Function()? permission,
  Future<bool> Function()? permissionSettings,
  Future<bool> Function()? permissionRequiresSettings,
  bool canEnable = true,
}) => BluetoothPowerController(
  readState: read,
  requestEnable: enable ?? () async => false,
  requestPermission: permission ?? () async => false,
  openPermissionSettings: permissionSettings,
  permissionRequiresSettings: permissionRequiresSettings,
  canRequestEnable: canEnable,
);

Future<void> _pump(
  WidgetTester tester,
  BluetoothPowerController controller,
  DisplayLanguage language,
) => tester.pumpWidget(
  MaterialApp(
    home: DisplayLanguageScope(
      language: language,
      child: Scaffold(body: BluetoothPowerPanel(controller: controller)),
    ),
  ),
);
