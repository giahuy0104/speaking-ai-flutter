import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/bluetooth_power_controller.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/onboarding_actions.dart';

void main() {
  testWidgets('iOS resumes an existing parent consent without asking again', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
          homiBleConnected: false,
          homiHfpConfigured: false,
          selectedAge: 8,
          aiSubprocessors: 'HOMI',
          dataRetentionSummary: 'Test',
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupHomi: () async => false,
          onAgeSelected: (_) {},
          onCompleteSetup: () async {},
        ),
      ),
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('startup-confirm-adult-role')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('startup-accept-legal')))
          .value,
      isTrue,
    );
    final next = find.byKey(const Key('startup-next'));
    expect(tester.widget<ButtonStyleButton>(next).onPressed, isNotNull);
    debugDefaultTargetPlatformOverride = null;
  });

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
                    homiBleConnected: !unsupported,
                    homiHfpConfigured: false,
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
                    onSetupHomi: () async {
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
            await confirmVisibleOnboardingChoices(tester);
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
            expect(
              find.byKey(const Key('startup-setup-hm-d001')),
              findsNothing,
            );
          } else {
            expect(
              find.text(
                language.choose(
                  'HOMI đang chờ kết nối micro.',
                  'HOMI 正在等待麦克风连接。',
                ),
              ),
              findsOneWidget,
            );
          }
          await tester.ensureVisible(escape);
          await tester.tap(escape);
          await tester.pump();
          expect(limitedCalls, 1);
          expect(tester.widget<OutlinedButton>(escape).onPressed, isNull);
          expect(completed, isFalse);
          pending.complete();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey<String>('startup-limited-step')),
            findsOneWidget,
          );
          expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
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
          permissionRequiresSettings: () async => true,
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
                homiBleConnected: false,
                homiHfpConfigured: false,
                selectedAge: 8,
                aiSubprocessors: 'HOMI',
                dataRetentionSummary: 'Test',
                onGrantPrivacyConsent: () async {},
                onContinueWithoutVoice: () async {},
                onRetryPermissions: () => unawaited(power.authorize()),
                onSetupHomi: () async => false,
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
          await confirmVisibleOnboardingChoices(tester);
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
        }
        expect(reads, 1);
        expect(
          find.byKey(const ValueKey<String>('startup-permissions-step')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('startup-setup-hm-d001')), findsNothing);
        expect(
          find.byKey(const Key('bluetooth-open-permission-settings')),
          findsOneWidget,
        );
        final authorize = find.byKey(const Key('startup-request-permissions'));
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
        expect(find.byKey(const Key('startup-setup-hm-d001')), findsNothing);
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
                  homiBleConnected: ble,
                  homiHfpConfigured: hfp,
                  selectedAge: 8,
                  aiSubprocessors: 'HOMI',
                  dataRetentionSummary: 'Test',
                  onGrantPrivacyConsent: () async {},
                  onContinueWithoutVoice: () async {},
                  onRetryPermissions: () {},
                  onSetupHomi: () async {
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
          await confirmVisibleOnboardingChoices(tester);
          await tester.tap(find.byKey(const Key('startup-next')));
          await tester.pumpAndSettle();
        }
        final connect = find.byKey(const Key('startup-setup-hm-d001'));
        expect(connect, findsNothing);
        expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
        final toggle = find.byKey(const Key('bluetooth-enable-switch'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(connect, findsOneWidget);
        expect(
          find.text(language.choose('Kết nối HOMI', '连接 HOMI')),
          findsNWidgets(2),
        );
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(attempts, 1);
        expect(
          find.text(
            language.choose('HOMI đang chờ kết nối micro.', 'HOMI 正在等待麦克风连接。'),
          ),
          findsOneWidget,
        );
        expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
        expect(find.byKey(const Key('startup-confirm-age')), findsNothing);
        expect(completed, 0);
        expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(
          find.text(language.choose('HOMI đã sẵn sàng!', 'HOMI 已准备就绪！')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('startup-confirm-age')));
        await tester.pumpAndSettle();
        expect(completed, 1);
      },
    );
  }

  testWidgets(
    'requires both BLE MAIN control and HM-D001 microphone before setup can finish',
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
              homiBleConnected: bleConnected,
              homiHfpConfigured: hfpConfigured,
              selectedAge: selectedAge,
              aiSubprocessors: 'HOMI backend trên Railway và Cloudflare',
              dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
              privacyPolicyUri: Uri.parse('https://example.com/privacy'),
              termsUri: Uri.parse('https://example.com/terms'),
              supportUri: Uri.parse('https://example.com/support'),
              onGrantPrivacyConsent: () async {
                setState(() => privacyConsentGranted = true);
              },
              onContinueWithoutVoice: () async {
                setState(() => limitedModeSelected = true);
              },
              onRetryPermissions: () {
                setState(() => permissionsGranted = true);
              },
              onSetupHomi: () async {
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
      expect(find.byKey(const Key('startup-accept-legal')), findsOneWidget);

      await _completeLegalReview(tester);
      await tester.ensureVisible(consentButton);
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNotNull);
      await tester.tap(consentButton);
      await tester.pumpAndSettle();

      expect(find.text('Bé đang ở độ tuổi nào?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('startup-next')));
      await confirmVisibleOnboardingChoices(tester);
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      expect(find.text('Cấp quyền cho HOMI'), findsOneWidget);
      expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
      expect(find.byKey(const Key('startup-setup-hm-d001')), findsNothing);
      expect(find.textContaining('HM-D001'), findsNothing);
      expect(find.textContaining('HFP'), findsNothing);
      expect(
        find.byKey(const Key('startup-android-offline-english-model')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const Key('startup-request-permissions')),
      );
      expect(find.text('Cấp quyền và tiếp tục'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-request-permissions')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('startup-setup-hm-d001')), findsOneWidget);
      expect(find.text('Kết nối HOMI'), findsNWidgets(2));
      expect(find.text('Cấp quyền cho HOMI'), findsNothing);
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );

      final completeButton = find.byKey(const Key('startup-confirm-age'));
      expect(completeButton, findsNothing);
      expect(find.byKey(const Key('startup-use-phone-mic')), findsNothing);
      expect(
        find.byKey(const Key('startup-choose-hm-d001-microphone')),
        findsNothing,
      );
      expect(find.text('Chưa kết nối'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('startup-setup-hm-d001')),
      );
      await tester.tap(find.byKey(const Key('startup-setup-hm-d001')));
      await tester.pumpAndSettle();
      expect(find.text('HOMI đã sẵn sàng!'), findsOneWidget);
      expect(completed, isFalse);
      await tester.tap(find.byKey(const Key('startup-confirm-age')));
      await tester.pump();

      expect(selectedAge, 8);
      expect(completed, isTrue);
      expect(limitedModeSelected, isFalse);
    },
  );

  testWidgets('limited mode can finish without microphone or HM-D001', (
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
            homiBleConnected: false,
            homiHfpConfigured: false,
            selectedAge: age,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {
              setState(() => limited = true);
            },
            onRetryPermissions: () {},
            onSetupHomi: () async => false,
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
    await confirmVisibleOnboardingChoices(tester);
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(limited, isTrue);
    expect(age, 6);
    expect(completed, isTrue);
  });

  testWidgets('iOS phone microphone fallback does not search before MAIN', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
          homiBleConnected: false,
          homiHfpConfigured: false,
          allowPhoneMicFallback: true,
          selectedAge: 8,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupHomi: () async => false,
          onChooseHomiMicrophone: () async {
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
    await confirmVisibleOnboardingChoices(tester);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();
    await tester.ensureVisible(nextButton);
    await confirmVisibleOnboardingChoices(tester);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Bạn có thể bắt đầu bằng micro iPhone'),
      findsOneWidget,
    );
    final microphonePicker = find.byKey(
      const Key('startup-choose-hm-d001-microphone'),
    );
    expect(microphonePicker, findsNothing);
    expect(microphonePickerOpened, isFalse);
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    await tester.ensureVisible(completeButton);
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
    await tester.tap(completeButton);
    await tester.pump();
    expect(completed, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('legacy iOS fallback accepts BLE without claiming HOMI success', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
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
            homiBleConnected: bleConnected,
            homiHfpConfigured: false,
            allowPhoneMicFallback: true,
            selectedAge: 8,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupHomi: () async {
              setState(() => bleConnected = true);
              return true;
            },
            onChooseHomiMicrophone: () async => false,
            onAgeSelected: (_) {},
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );

    for (var step = 0; step < 2; step += 1) {
      final nextButton = find.byKey(const Key('startup-next'));
      await tester.ensureVisible(nextButton);
      await confirmVisibleOnboardingChoices(tester);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final connectButton = find.byKey(const Key('startup-setup-hm-d001'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();
    expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
    expect(find.text('HOMI đang chờ kết nối micro.'), findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(connectButton).onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('startup-choose-hm-d001-microphone')),
      findsOneWidget,
    );
    expect(find.text('Tìm micro HOMI'), findsOneWidget);
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    await tester.ensureVisible(completeButton);
    expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
    debugDefaultTargetPlatformOverride = null;
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
              homiBleConnected: bleConnected,
              homiHfpConfigured: false,
              allowBleOnlySetup: true,
              selectedAge: 8,
              aiSubprocessors: 'Railway và Cloudflare',
              dataRetentionSummary: 'Theo chính sách công khai.',
              onGrantPrivacyConsent: () async {},
              onContinueWithoutVoice: () async {},
              onRetryPermissions: () {},
              onSetupHomi: () => connection.future,
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
      await confirmVisibleOnboardingChoices(tester);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final completeButton = find.byKey(const Key('startup-confirm-age'));
    expect(completeButton, findsNothing);

    final connectButton = find.byKey(const Key('startup-setup-hm-d001'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 13));
    expect(
      find.byKey(const Key('startup-connection-progress')),
      findsOneWidget,
    );
    expect(completeButton, findsNothing);

    rebuildSetup!(() => bleConnected = true);
    connection.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('HOMI đã sẵn sàng!'), findsNothing);
    expect(completed, isFalse);
    expect(find.text('HOMI đang chờ kết nối micro.'), findsOneWidget);
    expect(
      tester.widget<ButtonStyleButton>(connectButton).onPressed,
      isNotNull,
    );
    expect(
      find.byKey(const Key('startup-choose-hm-d001-microphone')),
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
            homiBleConnected: connected,
            homiHfpConfigured: connected,
            selectedAge: 8,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupHomi: () async {
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
      await confirmVisibleOnboardingChoices(tester);
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    }
    final connectButton = find.byKey(const Key('startup-setup-hm-d001'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pumpAndSettle();

    expect(find.text('Chưa tìm thấy HOMI'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Đã hiểu'), findsNothing);
    await tester.tap(find.byKey(const Key('startup-setup-hm-d001')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('HOMI đã sẵn sàng!'), findsOneWidget);
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
          homiBleConnected: false,
          homiHfpConfigured: false,
          selectedAge: null,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          privacyPolicyUri: Uri.parse('https://example.com/privacy'),
          termsUri: Uri.parse('https://example.com/terms'),
          supportUri: Uri.parse('https://example.com/support'),
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupHomi: () async => false,
          onAgeSelected: (_) {},
          onCompleteSetup: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('startup-review-legal')));
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

    expect(find.byKey(const Key('startup-accept-legal')), findsOneWidget);
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
  expect(
    tester
        .widget<Checkbox>(find.byKey(const Key('startup-accept-legal')))
        .value,
    isTrue,
  );
}
