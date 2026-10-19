import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in DisplayLanguage.values) {
    for (final unsupported in <bool>[true, false]) {
      testWidgets(
        'startup explicit no-voice escape ${unsupported ? 'unsupported' : 'partial'} in ${language.code}',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var limited = false;
          var limitedCalls = 0;
          var completed = false;
          var connectCalls = 0;
          var reads = 0;
          final pending = Completer<void>();
          final power = BluetoothPowerController(
            readState: () async {
              reads++;
              return unsupported
                  ? Aiv0BluetoothAdapterState.unsupported
                  : Aiv0BluetoothAdapterState.poweredOn;
            },
            requestEnable: () async => false,
            requestPermission: () async => false,
            canRequestEnable: true,
          );
          addTearDown(power.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: DisplayLanguageScope(
                language: language,
                child: StatefulBuilder(
                  builder: (context, setState) => StartupSetupScreen(
                    bluetoothPower: power,
                    profileLoading: false,
                    permissionRequestInProgress: false,
                    privacyConfigurationComplete: true,
                    privacyConsentGranted: !limited,
                    limitedModeSelected: limited,
                    microphoneGranted: true,
                    bluetoothRequired: true,
                    bluetoothGranted: !unsupported,
                    h20BleConnected: !unsupported,
                    h20HfpConfigured: false,
                    selectedAge: 8,
                    aiSubprocessors: 'HOMI',
                    dataRetentionSummary: 'Test',
                    onGrantPrivacyConsent: () async {},
                    onContinueWithoutVoice: () async {
                      limitedCalls++;
                      await pending.future;
                      setState(() => limited = true);
                    },
                    onRetryPermissions: () {},
                    onSetupH20: () async {
                      connectCalls++;
                      return false;
                    },
                    onAgeSelected: (_) {},
                    onCompleteSetup: () async {
                      completed = true;
                    },
                  ),
                ),
              ),
            ),
          );
          final escape = find.byKey(
            const Key('startup-continue-without-voice-after-consent'),
          );
          for (var i = 0; i < 2; i++) {
            expect(escape, findsNothing);
            expect(reads, 0);
            await tester.ensureVisible(find.byKey(const Key('startup-next')));
            await tester.tap(find.byKey(const Key('startup-next')));
            await tester.pumpAndSettle();
          }
          expect(escape, findsOneWidget);
          expect(
            find.text(
              language.choose('Tiếp tục không dùng giọng nói', '不使用语音继续'),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
          if (unsupported) {
            expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
          } else {
            expect(
              find.text(
                language.choose(
                  'Nút MAIN đã kết nối · Mic chưa kết nối',
                  'MAIN 按钮已连接 · 麦克风尚未连接',
                ),
              ),
              findsOneWidget,
            );
          }
          await tester.ensureVisible(escape);
          await tester.tap(escape);
          await tester.pump();
          expect(limitedCalls, 1);
          expect(tester.widget<TextButton>(escape).onPressed, isNull);
          expect(completed, isFalse);
          pending.complete();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('startup-limited-step')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('startup-connection-success-dialog')),
            findsNothing,
          );
          expect(connectCalls, 0);
          expect(
            find.text(
              language.choose(
                'HOMI sẽ mở bài học ở chế độ không dùng giọng nói.',
                'HOMI 将以不使用语音的模式打开课程。',
              ),
            ),
            findsOneWidget,
          );
          final complete = find.byKey(const Key('startup-confirm-age'));
          await tester.ensureVisible(complete);
          await tester.tap(complete);
          await tester.pumpAndSettle();
          expect(completed, isTrue);
          expect(limited, isTrue);
          expect(limitedCalls, 1);
        },
      );
    }

    testWidgets(
      'startup offers denied Bluetooth help only after parent steps in ${language.code}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var reads = 0;
        var settingsCalls = 0;
        final power = BluetoothPowerController(
          readState: () async {
            reads++;
            return Aiv0BluetoothAdapterState.unauthorized;
          },
          requestEnable: () async => false,
          requestPermission: () async => false,
          openPermissionSettings: () async {
            settingsCalls++;
            return true;
          },
          canRequestEnable: true,
        );
        addTearDown(power.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: DisplayLanguageScope(
              language: language,
              child: StartupSetupScreen(
                bluetoothPower: power,
                profileLoading: false,
                permissionRequestInProgress: false,
                privacyConfigurationComplete: true,
                privacyConsentGranted: true,
                limitedModeSelected: false,
                microphoneGranted: true,
                bluetoothRequired: true,
                bluetoothGranted: false,
                h20BleConnected: false,
                h20HfpConfigured: false,
                selectedAge: 8,
                aiSubprocessors: 'HOMI',
                dataRetentionSummary: 'Test',
                onGrantPrivacyConsent: () async {},
                onContinueWithoutVoice: () async {},
                onRetryPermissions: () {},
                onSetupH20: () async => false,
                onAgeSelected: (_) {},
                onCompleteSetup: () async {},
              ),
            ),
          ),
        );
        for (var i = 0; i < 2; i++) {
          expect(reads, 0);
          expect(find.byKey(const Key('bluetooth-power-panel')), findsNothing);
          await tester.ensureVisible(find.byKey(const Key('startup-next')));
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
        }
        expect(reads, 1);
        expect(
          find.byKey(const ValueKey<String>('startup-permissions-step')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
        expect(
          find.byKey(const Key('bluetooth-open-permission-settings')),
          findsNothing,
        );
        final authorize = find.byKey(const Key('bluetooth-authorize'));
        await tester.ensureVisible(authorize);
        await tester.tap(authorize);
        await tester.pumpAndSettle();
        final settings = find.byKey(
          const Key('bluetooth-open-permission-settings'),
        );
        expect(settings, findsOneWidget);
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(settingsCalls, 1);
        expect(find.byKey(const Key('startup-setup-h20')), findsNothing);
      },
    );

    testWidgets(
      'startup waits for Bluetooth and rejects BLE-only success in ${language.code}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var adapter = Aiv0BluetoothAdapterState.poweredOff;
        var ble = false;
        var hfp = false;
        var attempts = 0;
        var completed = 0;
        final power = BluetoothPowerController(
          readState: () async => adapter,
          requestEnable: () async {
            adapter = Aiv0BluetoothAdapterState.poweredOn;
            return true;
          },
          requestPermission: () async => true,
          canRequestEnable: true,
        );
        addTearDown(power.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: DisplayLanguageScope(
              language: language,
              child: StatefulBuilder(
                builder: (context, setState) => StartupSetupScreen(
                  bluetoothPower: power,
                  profileLoading: false,
                  permissionRequestInProgress: false,
                  privacyConfigurationComplete: true,
                  privacyConsentGranted: true,
                  limitedModeSelected: false,
                  microphoneGranted: true,
                  bluetoothRequired: true,
                  bluetoothGranted: true,
                  h20BleConnected: ble,
                  h20HfpConfigured: hfp,
                  selectedAge: 8,
                  aiSubprocessors: 'HOMI',
                  dataRetentionSummary: 'Test',
                  onGrantPrivacyConsent: () async {},
                  onContinueWithoutVoice: () async {},
                  onRetryPermissions: () {},
                  onSetupH20: () async {
                    attempts++;
                    setState(() {
                      ble = true;
                      hfp = attempts > 1;
                    });
                    return true;
                  },
                  onAgeSelected: (_) {},
                  onCompleteSetup: () async {
                    completed++;
                  },
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 2; i++) {
          await tester.ensureVisible(find.byKey(const Key('startup-next')));
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
        }
        final connect = find.byKey(const Key('startup-setup-h20'));
        expect(connect, findsNothing);
        expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
        final toggle = find.byKey(const Key('bluetooth-enable-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(connect, findsOneWidget);
        expect(
          find.text(language.choose('Kết nối HOMI', '连接 HOMI')),
          findsOneWidget,
        );
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(attempts, 1);
        expect(
          find.text(
            language.choose(
              'Nút MAIN đã kết nối · Mic chưa kết nối',
              'MAIN 按钮已连接 · 麦克风尚未连接',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('startup-connection-success-dialog')),
          findsNothing,
        );
        expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
        expect(completed, 0);
        expect(tester.widget<OutlinedButton>(connect).onPressed, isNotNull);
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(
          find.byKey(const Key('startup-connection-success-dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const Key('startup-start-after-connection')),
        );
        await tester.pumpAndSettle();
        expect(completed, 1);
      },
    );
  }

  testWidgets(
    'requires both BLE MAIN control and H20 microphone before setup can finish',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var privacyConsentGranted = false;
      var permissionsGranted = false;
      var limitedModeSelected = false;
      var bleConnected = false;
      var hfpConfigured = false;
      int? selectedAge;
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: StatefulBuilder(
            builder: (context, setState) => StartupSetupScreen(
              profileLoading: false,
              permissionRequestInProgress: false,
              privacyConfigurationComplete: true,
              privacyConsentGranted: privacyConsentGranted,
              limitedModeSelected: limitedModeSelected,
              microphoneGranted: permissionsGranted,
              bluetoothRequired: true,
              bluetoothGranted: permissionsGranted,
              h20BleConnected: bleConnected,
              h20HfpConfigured: hfpConfigured,
              selectedAge: selectedAge,
              aiSubprocessors: 'HOMI backend trên Railway và Cloudflare',
              dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
              privacyPolicyUri: Uri.parse('https://example.com/privacy'),
              termsUri: Uri.parse('https://example.com/terms'),
              supportUri: Uri.parse('https://example.com/support'),
              androidOfflineEnglishModelOptionAvailable: true,
              onGrantPrivacyConsent: () async {
                setState(() => privacyConsentGranted = true);
              },
              onContinueWithoutVoice: () async {
                setState(() => limitedModeSelected = true);
              },
              onRetryPermissions: () {
                setState(() => permissionsGranted = true);
              },
              onSetupH20: () async {
                setState(() {
                  bleConnected = true;
                  hfpConfigured = true;
                });
                return true;
              },
              onAgeSelected: (age) => setState(() => selectedAge = age),
              onCompleteSetup: () async {
                setState(() => completed = true);
              },
            ),
          ),
        ),
      );

      final consentButton = find.byKey(
        const Key('startup-grant-privacy-consent'),
      );
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNull);

      await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
      await tester.pump();
      await tester.ensureVisible(consentButton);
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNull);
      expect(find.byKey(const Key('startup-accept-legal')), findsNothing);

      await _completeLegalReview(tester);
      await tester.ensureVisible(consentButton);
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNotNull);
      await tester.tap(consentButton);
      await tester.pumpAndSettle();

      expect(find.text('Bé đang ở độ tuổi nào?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('startup-next')));
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      expect(find.text('Cho HOMI quyền cần thiết'), findsOneWidget);
      expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
      expect(find.text('Kết nối thiết bị'), findsNothing);
      expect(find.textContaining('H20'), findsNothing);
      expect(find.textContaining('HFP'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('startup-request-permissions')),
      );
      expect(find.text('Cấp quyền và tiếp tục'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-request-permissions')));
      await tester.pumpAndSettle();

      expect(find.text('Kết nối thiết bị'), findsOneWidget);
      expect(find.text('Kết nối HOMI'), findsOneWidget);
      expect(find.text('Cho HOMI quyền cần thiết'), findsNothing);
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('startup-android-offline-english-model')),
        findsNothing,
      );

      final completeButton = find.byKey(const Key('startup-confirm-age'));
      expect(completeButton, findsNothing);
      expect(find.byKey(const Key('startup-use-phone-mic')), findsNothing);
      expect(
        find.byKey(const Key('startup-choose-h20-microphone')),
        findsNothing,
      );
      expect(
        find.textContaining('Kết nối HOMI để bắt đầu bài học có giọng nói'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('startup-setup-h20')));
      await tester.tap(find.byKey(const Key('startup-setup-h20')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('startup-connection-success-dialog')),
        findsOneWidget,
      );
      expect(completed, isFalse);
      await tester.tap(find.byKey(const Key('startup-start-after-connection')));
      await tester.pump();

      expect(selectedAge, 8);
      expect(completed, isTrue);
      expect(limitedModeSelected, isFalse);
    },
  );

  testWidgets('limited mode can finish without microphone or H20', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var limited = false;
    int? age;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: false,
            limitedModeSelected: limited,
            microphoneGranted: false,
            bluetoothRequired: true,
            bluetoothGranted: false,
            h20BleConnected: false,
            h20HfpConfigured: false,
            selectedAge: age,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {
              setState(() => limited = true);
            },
            onRetryPermissions: () {},
            onSetupH20: () async => false,
            onAgeSelected: (value) => setState(() => age = value),
            onCompleteSetup: () async {
              setState(() => completed = true);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
    await tester.pump();
    await _completeLegalReview(tester);
    await tester.ensureVisible(
      find.byKey(const Key('startup-continue-without-voice')),
    );
    await tester.tap(find.byKey(const Key('startup-continue-without-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('startup-age-6-7')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('startup-next')));
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(limited, isTrue);
    expect(age, 6);
    expect(completed, isTrue);
  });

  testWidgets('iOS phone microphone fallback can finish without H20', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var completed = false;
    var microphonePickerOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          privacyConfigurationComplete: true,
          privacyConsentGranted: true,
          limitedModeSelected: false,
          microphoneGranted: true,
          bluetoothRequired: true,
          bluetoothGranted: true,
          h20BleConnected: false,
          h20HfpConfigured: false,
          allowPhoneMicFallback: true,
          selectedAge: 8,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupH20: () async => false,
          onChooseH20Microphone: () async {
            microphonePickerOpened = true;
            return false;
          },
          onAgeSelected: (_) {},
          onCompleteSetup: () async => completed = true,
        ),
      ),
    );

    final nextButton = find.byKey(const Key('startup-next'));
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Bạn có thể bắt đầu bằng micro iPhone'),
      findsOneWidget,
    );
    final microphonePicker = find.byKey(
      const Key('startup-choose-h20-microphone'),
    );
    await tester.ensureVisible(microphonePicker);
    expect(microphonePicker, findsOneWidget);
    await tester.tap(microphonePicker);
    await tester.pumpAndSettle();
    expect(microphonePickerOpened, isTrue);
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    await tester.ensureVisible(completeButton);
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
    await tester.tap(completeButton);
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('legacy iOS fallback accepts BLE without claiming HOMI success', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var bleConnected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: true,
            limitedModeSelected: false,
            microphoneGranted: true,
            bluetoothRequired: true,
            bluetoothGranted: true,
            h20BleConnected: bleConnected,
            h20HfpConfigured: false,
            allowPhoneMicFallback: true,
            selectedAge: 8,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupH20: () async {
              setState(() => bleConnected = true);
              return true;
            },
            onChooseH20Microphone: () async => false,
            onAgeSelected: (_) {},
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );

    for (var step = 0; step < 2; step += 1) {
      final nextButton = find.byKey(const Key('startup-next'));
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final connectButton = find.byKey(const Key('startup-setup-h20'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('startup-connection-success-dialog')),
      findsNothing,
    );
    expect(find.text('Nút MAIN đã kết nối · Mic chưa kết nối'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(connectButton).onPressed, isNotNull);
    expect(
      find.byKey(const Key('startup-choose-h20-microphone')),
      findsOneWidget,
    );
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    await tester.ensureVisible(completeButton);
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
  });

  testWidgets('legacy BLE-only opt-in never claims full HOMI success', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var bleConnected = false;
    var completed = false;
    final connection = Completer<bool>();
    StateSetter? rebuildSetup;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildSetup = setState;
            return StartupSetupScreen(
              profileLoading: false,
              permissionRequestInProgress: false,
              privacyConfigurationComplete: true,
              privacyConsentGranted: true,
              limitedModeSelected: false,
              microphoneGranted: true,
              bluetoothRequired: true,
              bluetoothGranted: true,
              h20BleConnected: bleConnected,
              h20HfpConfigured: false,
              allowBleOnlySetup: true,
              selectedAge: 8,
              aiSubprocessors: 'Railway và Cloudflare',
              dataRetentionSummary: 'Theo chính sách công khai.',
              onGrantPrivacyConsent: () async {},
              onContinueWithoutVoice: () async {},
              onRetryPermissions: () {},
              onSetupH20: () => connection.future,
              onAgeSelected: (_) {},
              onCompleteSetup: () async => completed = true,
            );
          },
        ),
      ),
    );

    for (var step = 0; step < 2; step += 1) {
      final nextButton = find.byKey(const Key('startup-next'));
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    expect(completeButton, findsNothing);

    final connectButton = find.byKey(const Key('startup-setup-h20'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    expect(
      find.byKey(const Key('device-connection-feedback-connecting')),
      findsOneWidget,
    );
    expect(completeButton, findsNothing);

    rebuildSetup!(() => bleConnected = true);
    connection.complete(true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('startup-connection-success-dialog')),
      findsNothing,
    );
    expect(completed, isFalse);
    expect(find.text('Nút MAIN đã kết nối · Mic chưa kết nối'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(connectButton).onPressed, isNotNull);
    expect(
      find.byKey(const Key('startup-choose-h20-microphone')),
      findsNothing,
    );
    await tester.ensureVisible(completeButton);
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
    await tester.tap(completeButton);
    expect(completed, isTrue);
  });

  testWidgets('connection failure offers a friendly retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var attempts = 0;
    var connected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: true,
            limitedModeSelected: false,
            microphoneGranted: true,
            bluetoothRequired: true,
            bluetoothGranted: true,
            h20BleConnected: connected,
            h20HfpConfigured: connected,
            selectedAge: 8,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupH20: () async {
              attempts += 1;
              if (attempts == 1) throw StateError('Temporary connection issue');
              setState(() => connected = true);
              return true;
            },
            onAgeSelected: (_) {},
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );

    for (var step = 0; step < 2; step += 1) {
      final nextButton = find.byKey(const Key('startup-next'));
      await tester.ensureVisible(nextButton);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final connectButton = find.byKey(const Key('startup-setup-h20'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('startup-connection-failure-sheet')),
      findsOneWidget,
    );
    expect(find.text('HOMI chưa thấy thiết bị'), findsOneWidget);
    expect(find.text('Đã hiểu'), findsNothing);
    await tester.tap(find.byKey(const Key('startup-retry-connection')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      find.byKey(const Key('startup-connection-success-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('closing legal review early does not unlock voice consent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          privacyConfigurationComplete: true,
          privacyConsentGranted: false,
          limitedModeSelected: false,
          microphoneGranted: false,
          bluetoothRequired: true,
          bluetoothGranted: false,
          h20BleConnected: false,
          h20HfpConfigured: false,
          selectedAge: null,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          privacyPolicyUri: Uri.parse('https://example.com/privacy'),
          termsUri: Uri.parse('https://example.com/terms'),
          supportUri: Uri.parse('https://example.com/support'),
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupH20: () async => false,
          onAgeSelected: (_) {},
          onCompleteSetup: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('startup-review-legal')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startup-legal-reviewed')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('startup-close-legal')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-accept-legal')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('startup-grant-privacy-consent')),
          )
          .onPressed,
      isNull,
    );
  });
}

Future<void> _completeLegalReview(WidgetTester tester) async {
  final legalReviewButton = find.byKey(const Key('startup-review-legal'));
  await tester.ensureVisible(legalReviewButton);
  await tester.tap(legalReviewButton);
  await tester.pumpAndSettle();

  expect(find.text('Bên thứ ba nhận dữ liệu và mục đích'), findsOneWidget);
  expect(
    find.textContaining('biện pháp bảo vệ dữ liệu tương đương'),
    findsOneWidget,
  );

  final reviewedButton = find.byKey(const Key('startup-legal-reviewed'));
  expect(tester.widget<FilledButton>(reviewedButton).onPressed, isNull);

  for (var attempt = 0; attempt < 6; attempt += 1) {
    if (tester.widget<FilledButton>(reviewedButton).onPressed != null) break;
    await tester.drag(
      find.byKey(const Key('startup-legal-scroll')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
  }

  expect(tester.widget<FilledButton>(reviewedButton).onPressed, isNotNull);
  await tester.tap(reviewedButton);
  await tester.pumpAndSettle();
}
