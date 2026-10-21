import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_actions.dart';

void main() {
  for (final state in [
    'first-privacy',
    'bluetooth-off',
    'device-powered',
    'searching',
    'partial-permission',
    'limited',
    'partial',
    'ready',
    'failed',
  ]) {
    testWidgets('approved $state state', (tester) async {
      await _loadGoldenFonts();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pendingConnection = Completer<bool>();
      final power = BluetoothPowerController(
        readState: () async => state == 'bluetooth-off'
            ? Aiv0BluetoothAdapterState.poweredOff
            : Aiv0BluetoothAdapterState.poweredOn,
        requestEnable: () async => false,
        requestPermission: () async => true,
        canRequestEnable: true,
      );
      addTearDown(power.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: state != 'first-privacy',
            limitedModeSelected: state == 'limited',
            microphoneGranted: true,
            bluetoothRequired: true,
            bluetoothGranted: state != 'partial-permission',
            h20BleConnected: state == 'partial' || state == 'ready',
            h20HfpConfigured: state == 'ready',
            bluetoothPower: power,
            selectedAge: 6,
            aiSubprocessors: 'HOMI',
            dataRetentionSummary: 'Test',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupH20: () => state == 'searching'
                ? pendingConnection.future
                : Future.value(false),
            onCancelH20Setup: () async {},
            onAgeSelected: (_) {},
            onCompleteSetup: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(StartupSetupScreen));
        for (final asset in [
          'assets/images/learning-minimal-sky-background-option2.png',
          'assets/images/mascot/penguin-avatar.png',
          'assets/images/mascot/penguin-wave.png',
        ]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      await tester.pumpAndSettle();
      if (state != 'first-privacy') {
        for (var step = 0; step < 2; step++) {
          await confirmVisibleOnboardingChoices(tester);
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
        }
      }
      if (state == 'failed' || state == 'searching') {
        await tester.tap(find.byKey(const Key('startup-setup-h20')));
        if (state == 'searching') {
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('startup-connection-progress')),
            findsOneWidget,
          );
        } else {
          await tester.pumpAndSettle();
        }
      }
      await expectLater(
        find.byType(StartupSetupScreen),
        matchesGoldenFile('goldens/startup-$state-390x844.png'),
      );
      if (state == 'searching') {
        pendingConnection.complete(false);
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
    'all three setup steps share the approved HOMI form',
    (tester) async {
      await _loadGoldenFonts();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var selectedAge = 6;
      var permissionsGranted = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: StartupSetupScreen(
              profileLoading: false,
              permissionRequestInProgress: false,
              privacyConfigurationComplete: true,
              privacyConsentGranted: true,
              limitedModeSelected: false,
              microphoneGranted: permissionsGranted,
              bluetoothRequired: true,
              bluetoothGranted: permissionsGranted,
              h20BleConnected: false,
              h20HfpConfigured: false,
              selectedAge: selectedAge,
              aiSubprocessors: 'HOMI AI',
              dataRetentionSummary: 'Lưu theo chính sách HOMI.',
              onGrantPrivacyConsent: () async {},
              onContinueWithoutVoice: () async {},
              onRetryPermissions: () =>
                  setState(() => permissionsGranted = true),
              onSetupH20: () async => false,
              onAgeSelected: (age) => setState(() => selectedAge = age),
              onCompleteSetup: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(StartupSetupScreen));
        await Future.wait<void>(
          const <AssetImage>[
            AssetImage('assets/images/mascot/penguin-avatar.png'),
            AssetImage('assets/images/mascot/penguin-wave.png'),
          ].map((provider) => precacheImage(provider, context)),
        );
      });
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StartupSetupScreen),
        matchesGoldenFile('goldens/startup-privacy-390x844.png'),
      );

      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StartupSetupScreen),
        matchesGoldenFile('goldens/startup-profile-390x844.png'),
      );

      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(StartupSetupScreen),
        matchesGoldenFile('goldens/startup-permissions-390x844.png'),
      );
      await tester.tap(find.byKey(const Key('startup-request-permissions')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(StartupSetupScreen),
        matchesGoldenFile('goldens/startup-device-390x844.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('all three setup steps share one dark HOMI form', (tester) async {
    await _loadGoldenFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedAge = 6;
    var permissionsGranted = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: ThemeMode.dark,
          home: StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: true,
            limitedModeSelected: false,
            microphoneGranted: permissionsGranted,
            bluetoothRequired: true,
            bluetoothGranted: permissionsGranted,
            h20BleConnected: false,
            h20HfpConfigured: false,
            selectedAge: selectedAge,
            aiSubprocessors: 'HOMI AI',
            dataRetentionSummary: 'Lưu theo chính sách HOMI.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () => setState(() => permissionsGranted = true),
            onSetupH20: () async => false,
            onAgeSelected: (age) => setState(() => selectedAge = age),
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(StartupSetupScreen));
      await Future.wait<void>(
        const <AssetImage>[
          AssetImage('assets/images/mascot/penguin-avatar.png'),
          AssetImage('assets/images/mascot/penguin-wave.png'),
        ].map((provider) => precacheImage(provider, context)),
      );
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-privacy-390x844.png'),
    );
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-profile-390x844.png'),
    );
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-permissions-390x844.png'),
    );
    await tester.tap(find.byKey(const Key('startup-request-permissions')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-device-390x844.png'),
    );
  });
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}
