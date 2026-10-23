import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/homi_bluetooth_icon.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'connection retry keeps footer and content geometry at text $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var attempt = Completer<bool>();
        final model = _SetupModel()..permissions = true;
        model.connect = () => attempt.future;
        await _pump(tester, model, scale: scale);
        await _toDevice(tester);
        final footer = find.byKey(const Key('startup-action-footer'));
        final content = find.byKey(const Key('startup-content-scroll'));
        await tester.drag(content, const Offset(0, -200));
        await tester.pumpAndSettle();
        final footerRect = tester.getRect(footer);
        final contentRect = tester.getRect(content);
        final hero = find.byKey(const Key('startup-device-hero'));
        final panel = find.byKey(const Key('startup-device-status-panel'));
        final heroRect = tester.getRect(hero);
        final panelRect = tester.getRect(panel);
        void expectStable() {
          expect(tester.getRect(footer), footerRect);
          expect(tester.getRect(content), contentRect);
          expect(tester.getRect(hero), heroRect);
          expect(tester.getRect(panel), panelRect);
        }

        await tester.tap(find.byKey(const Key('startup-setup-h20')));
        await tester.pump();
        expectStable();
        model.requestingPermissions = true;
        model.rebuild();
        await tester.pump();
        expectStable();
        model.requestingPermissions = false;
        model.rebuild();
        attempt.complete(false);
        await tester.pumpAndSettle();
        expectStable();
        expect(find.text('Chưa tìm thấy HOMI'), findsOneWidget);
        attempt = Completer<bool>();
        await tester.tap(find.byKey(const Key('startup-setup-h20')));
        await tester.pump();
        expect(tester.getRect(footer), footerRect);
        await tester.tap(find.byKey(const Key('startup-cancel-connection')));
        await tester.pumpAndSettle();
        expect(tester.getRect(footer), footerRect);
        attempt.complete(false);
        await tester.pumpAndSettle();
        expectStable();
        attempt = Completer<bool>();
        await tester.tap(find.byKey(const Key('startup-setup-h20')));
        await tester.pump();
        model.ble = true;
        model.rebuild();
        attempt.complete(false);
        await tester.pumpAndSettle();
        expectStable();
        expect(find.text('Còn một bước kết nối'), findsOneWidget);
        model.mic = true;
        model.rebuild();
        await tester.pumpAndSettle();
        expectStable();
        expect(find.text('HOMI đã sẵn sàng!'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'adapter refresh and resume checks retain the settled connection UI',
    (tester) async {
      Completer<Aiv0BluetoothAdapterState>? radioRead;
      Completer<void>? permissionRead;
      final power = BluetoothPowerController(
        readState: () async => radioRead == null
            ? Aiv0BluetoothAdapterState.poweredOn
            : await radioRead.future,
        requestEnable: () async => true,
        requestPermission: () async => true,
        canRequestEnable: true,
      );
      addTearDown(power.dispose);
      final model = _SetupModel()
        ..permissions = true
        ..power = power;
      model.checkPermissions = () async {
        await permissionRead?.future;
      };
      await _pump(tester, model);
      await _toDevice(tester);
      final footer = find.byKey(const Key('startup-action-footer'));
      final hero = find.byKey(const Key('startup-device-hero'));
      final footerRect = tester.getRect(footer);
      final heroRect = tester.getRect(hero);
      final connect = find.byKey(const Key('startup-setup-h20'));
      radioRead = Completer<Aiv0BluetoothAdapterState>();
      final refresh = power.refresh();
      await tester.pump();
      expect(connect, findsOneWidget);
      expect(tester.widget<FilledButton>(connect).onPressed, isNull);
      expect(tester.getRect(footer), footerRect);
      expect(tester.getRect(hero), heroRect);
      radioRead.complete(Aiv0BluetoothAdapterState.poweredOn);
      await refresh;
      radioRead = null;
      await tester.pumpAndSettle();
      permissionRead = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        find.byKey(const Key('startup-checking-permissions')),
        findsNothing,
      );
      expect(connect, findsOneWidget);
      expect(tester.widget<FilledButton>(connect).onPressed, isNull);
      expect(tester.getRect(footer), footerRect);
      expect(tester.getRect(hero), heroRect);
      permissionRead.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final target in ['startup-accept-legal', 'startup-review-legal']) {
    testWidgets(
      '$target opens terms and only acknowledgement checks agreement',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final model = _SetupModel()..consent = false;
        await _pump(tester, model);
        final legal = find.byKey(const Key('startup-accept-legal'));
        final adult = find.byKey(const Key('startup-confirm-adult-role'));
        expect(tester.widget<Checkbox>(legal).value, isFalse);
        await tester.ensureVisible(find.byKey(Key(target)));
        await tester.tap(find.byKey(Key(target)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('startup-legal-scroll')), findsOneWidget);
        expect(tester.widget<Checkbox>(legal).value, isFalse);
        await tester.tap(find.byKey(const Key('startup-close-legal')));
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(legal).value, isFalse);
        await tester.tap(find.byKey(Key(target)));
        await tester.pumpAndSettle();
        await acknowledgeVisibleLegalReview(tester);
        expect(find.byKey(const Key('startup-legal-scroll')), findsNothing);
        expect(tester.widget<Checkbox>(legal).value, isTrue);
        expect(tester.widget<Checkbox>(adult).value, isFalse);
        expect(model.consent, isFalse);
      },
    );
  }

  testWidgets(
    'step 3 waits for permission check without flashing grant action',
    (tester) async {
      final pending = Completer<void>();
      final model = _SetupModel();
      model.checkPermissions = () async {
        await pending.future;
        model.permissions = true;
        model.rebuild();
      };
      await _pump(tester, model);
      await confirmVisibleOnboardingChoices(tester);
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pump();
      expect(
        find.byKey(const Key('startup-checking-permissions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(find.byKey(const Key('startup-setup-h20')), findsOneWidget);
    },
  );

  testWidgets(
    'consent checkboxes require explicit taps even with saved consent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final model = _SetupModel()..consent = true;
      await _pump(tester, model);
      final adult = find.byKey(const Key('startup-confirm-adult-role'));
      final legal = find.byKey(const Key('startup-accept-legal'));
      final next = find.byKey(const Key('startup-next'));
      expect(tester.widget<Checkbox>(adult).value, isFalse);
      expect(tester.widget<Checkbox>(legal).value, isFalse);
      expect(tester.widget<FilledButton>(next).onPressed, isNull);

      model.consent = false;
      model.rebuild();
      await tester.pumpAndSettle();
      model.consent = true;
      model.rebuild();
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(adult).value, isFalse);
      expect(tester.widget<Checkbox>(legal).value, isFalse);

      await tester.ensureVisible(adult);
      await tester.tap(adult);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.ensureVisible(legal);
      await tester.tap(legal);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(legal).value, isFalse);
      await acknowledgeVisibleLegalReview(tester);
      expect(tester.widget<Checkbox>(legal).value, isTrue);
      expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
      await tester.ensureVisible(legal);
      await tester.tap(legal);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-close-legal')));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(legal).value, isTrue);
    },
  );

  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'footer stays in safe area across steps and scroll at $size / $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final model = _SetupModel()..consent = false;
          await _pump(tester, model, scale: scale, bottomInset: 20);
          final footer = find.byKey(const Key('startup-action-footer'));
          final escape = find.byKey(
            const Key('startup-continue-without-voice'),
          );
          final bottom = tester.getBottomRight(escape).dy;
          expect(bottom, closeTo(size.height - 20 - 24, 1));
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byKey(const Key('startup-content-scroll')),
            const Offset(0, -450),
          );
          await tester.pumpAndSettle();
          expect(tester.getBottomRight(escape).dy, bottom);
          expect(tester.getBottomRight(footer).dy, size.height - 20);
          model.consent = true;
          model.rebuild();
          await tester.pumpAndSettle();
          await confirmVisibleOnboardingChoices(tester);
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
          expect(
            tester.getBottomRight(find.byKey(const Key('startup-next'))).dy,
            bottom,
          );
          await confirmVisibleOnboardingChoices(tester);
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
          expect(
            tester
                .getBottomRight(
                  find.byKey(
                    const Key('startup-continue-without-voice-after-consent'),
                  ),
                )
                .dy,
            bottom,
          );
          model.permissionError = 'Quyền chưa được cấp. ' * 15;
          model.rebuild();
          await tester.pumpAndSettle();
          expect(
            tester
                .getBottomRight(
                  find.byKey(
                    const Key('startup-continue-without-voice-after-consent'),
                  ),
                )
                .dy,
            bottom,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'system pairing is retained without claiming MAIN or microphone readiness',
    (tester) async {
      final model = _SetupModel()
        ..permissions = true
        ..paired = true;
      await _pump(tester, model);
      await _toDevice(tester);
      expect(find.text('Còn một bước kết nối'), findsOneWidget);
      expect(
        find.text('Bluetooth đã ghép đôi. Còn kết nối MAIN.'),
        findsOneWidget,
      );
      expect(find.text('Ghép đôi Bluetooth'), findsOneWidget);
      expect(find.text('Tiếp tục kết nối'), findsOneWidget);
      expect(find.text('Chưa tìm thấy HOMI'), findsNothing);
      expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
      final footer = tester.getBottomRight(
        find.byKey(const Key('startup-action-footer')),
      );
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await tester.pumpAndSettle();
      expect(find.text('Tiếp tục kết nối'), findsOneWidget);
      expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
      expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
      expect(
        tester.getBottomRight(find.byKey(const Key('startup-action-footer'))),
        footer,
      );
      expect(model.completed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'first pairing may outlast 45 seconds but stays cancellable and bounded',
    (tester) async {
      final pending = Completer<bool>();
      final model = _SetupModel()..permissions = true;
      var cancelled = 0;
      model.connect = () => pending.future;
      model.cancel = () async {
        cancelled++;
      };
      await _pump(tester, model);
      await _toDevice(tester);
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      expect(cancelled, 0);
      expect(
        find.byKey(const Key('startup-cancel-connection')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('startup-connection-progress')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(cancelled, 1);
      expect(
        find.byKey(const Key('startup-connection-progress')),
        findsNothing,
      );
      expect(find.text('Thử lại'), findsOneWidget);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(cancelled, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a round leaves retry available and ignores its late completion',
    (tester) async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      final model = _SetupModel()..permissions = true;
      var attempts = 0;
      var cancelled = 0;
      model.connect = () => ++attempts == 1 ? first.future : second.future;
      model.cancel = () async {
        cancelled++;
      };
      await _pump(tester, model);
      await _toDevice(tester);
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await tester.pump();
      expect(
        find.byKey(const Key('startup-connection-progress')),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.byKey(const Key('startup-cancel-connection')));
      await tester.pumpAndSettle();
      expect(cancelled, 1);
      expect(
        find.byKey(const Key('startup-connection-progress')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await tester.pump();
      first.complete(false);
      await tester.pump();
      expect(
        find.byKey(const Key('startup-connection-progress')),
        findsOneWidget,
      );
      expect(attempts, 2);
      model.ble = true;
      model.mic = true;
      model.rebuild();
      second.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('HOMI đã sẵn sàng!'), findsOneWidget);
      expect(find.byKey(const Key('startup-confirm-age')), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'MAIN and mic statuses remain independent and radio loss removes ready',
    (tester) async {
      var adapter = Aiv0BluetoothAdapterState.poweredOn;
      final power = BluetoothPowerController(
        readState: () async => adapter,
        requestEnable: () async => false,
        requestPermission: () async => true,
        canRequestEnable: true,
      );
      addTearDown(power.dispose);
      final model = _SetupModel()
        ..permissions = true
        ..mic = true
        ..power = power;
      await _pump(tester, model);
      await _toDevice(tester);
      final main = find.byKey(const Key('startup-main-status'));
      expect(
        find.descendant(of: main, matching: find.text('Chưa kết nối')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: main, matching: find.byType(HomiBluetoothIcon)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
      model.ble = true;
      model.rebuild();
      await tester.pumpAndSettle();
      expect(find.text('HOMI đã sẵn sàng!'), findsOneWidget);
      adapter = Aiv0BluetoothAdapterState.poweredOff;
      await power.refresh();
      await tester.pumpAndSettle();
      expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
      expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
      expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('bluetooth-enable-switch')))
            .value,
        isFalse,
      );
      expect(find.textContaining('đã được cấp quyền'), findsNothing);
      expect(model.completed, 0);
    },
  );

  testWidgets('one permission granted keeps only the remaining grant pending', (
    tester,
  ) async {
    final model = _SetupModel()..microphonePermission = true;
    await _pump(tester, model);
    await _toDevice(tester);
    expect(find.text('Đã cấp quyền'), findsOneWidget);
    expect(find.text('Chưa cấp quyền'), findsOneWidget);
    expect(find.text('Cấp quyền còn thiếu'), findsOneWidget);
    expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
    expect(find.byKey(const Key('bluetooth-enable-switch')), findsNothing);
  });
}

class _SetupModel {
  bool consent = true;
  bool permissions = false;
  bool requestingPermissions = false;
  bool microphonePermission = false;
  bool ble = false;
  bool mic = false;
  bool paired = false;
  int completed = 0;
  String? permissionError;
  BluetoothPowerController? power;
  Future<void> Function()? checkPermissions;
  Future<bool> Function() connect = () async => false;
  Future<void> Function() cancel = () async {};
  late VoidCallback rebuild;
}

Future<void> _pump(
  WidgetTester tester,
  _SetupModel model, {
  double scale = 1,
  double bottomInset = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: StatefulBuilder(
        builder: (context, setState) {
          model.rebuild = () => setState(() {});
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: EdgeInsets.only(bottom: bottomInset),
            ),
            child: StartupSetupScreen(
              profileLoading: false,
              permissionRequestInProgress: model.requestingPermissions,
              privacyConfigurationComplete: true,
              privacyConsentGranted: model.consent,
              limitedModeSelected: false,
              microphoneGranted:
                  model.permissions || model.microphonePermission,
              bluetoothRequired: true,
              bluetoothGranted: model.permissions,
              h20BleConnected: model.ble,
              h20HfpConfigured: model.mic,
              h20AudioPaired: model.paired,
              selectedAge: 6,
              aiSubprocessors: 'HOMI',
              dataRetentionSummary: 'Test',
              bluetoothPower: model.power,
              permissionError: model.permissionError,
              onGrantPrivacyConsent: () async {},
              onContinueWithoutVoice: () async {},
              onRetryPermissions: () {},
              onCheckPermissions: model.checkPermissions,
              onSetupH20: model.connect,
              onCancelH20Setup: model.cancel,
              onAgeSelected: (_) {},
              onCompleteSetup: () async {
                model.completed++;
              },
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toDevice(WidgetTester tester) async {
  for (var step = 0; step < 2; step++) {
    await confirmVisibleOnboardingChoices(tester);
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
  }
}
