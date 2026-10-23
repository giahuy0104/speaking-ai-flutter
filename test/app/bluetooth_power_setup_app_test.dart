import 'package:ai_speaking_flutter_app/presentation/history/bloc/history_bloc.dart';
import 'package:ai_speaking_flutter_app/presentation/history/screen/history_screen.dart';
import 'dart:async';
import 'dart:io';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/presentation/settings/bloc/settings_bloc.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/data/settings/stored_settings_repository.dart';
import 'package:ai_speaking_flutter_app/app/di/app_dependencies.dart';
import 'package:ai_speaking_flutter_app/presentation/app/bloc/app_bloc.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ai_speaking_flutter_app/presentation/device/bloc/device_bloc.dart';
import 'package:ai_speaking_flutter_app/domain/device/device_connection.dart';

import 'package:ai_speaking_flutter_app/app/ai_speaking_app.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:ai_speaking_flutter_app/presentation/settings/screen/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/onboarding_actions.dart';

void main() {
  final android = TargetPlatformVariant({TargetPlatform.android});

  testWidgets(
    'Settings history creates and disposes an injected sheet Bloc on each opening',
    (tester) async {
      final app = await _pumpApp(tester, surfaceSize: const Size(460, 900));
      await app.openSettings();
      final openHistory = find.text('Xem lịch sử gần đây');
      await tester.ensureVisible(openHistory);
      await tester.tap(openHistory);
      // History may still be loading through the real app adapter. Verify
      // sheet ownership without waiting on its looping loading animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HistoryScreen), findsOneWidget);
      final consumer = find.byType(BlocConsumer<HistoryBloc, HistoryState>);
      final first = tester.element(consumer).read<HistoryBloc>();
      first.add(HistoryQueryChanged('test'));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(HistoryScreen),
          matching: find.byTooltip('Đóng'),
        ),
      );
      await tester.pumpAndSettle();
      expect(first.isClosed, isTrue);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.ensureVisible(openHistory);
      await tester.tap(openHistory);
      // History may still be loading through the real app adapter. Verify
      // sheet ownership without waiting on its looping loading animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final second = tester.element(consumer).read<HistoryBloc>();
      expect(second, isNot(same(first)));
      expect(second.state.query, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(HistoryScreen),
          matching: find.byTooltip('Đóng'),
        ),
      );
      await tester.pumpAndSettle();
      expect(second.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Settings audio options use Bloc while retaining VAD and persistence rules',
    (tester) async {
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      final savedMedia = !isIos;
      final app = await _pumpApp(
        tester,
        surfaceSize: const Size(460, 900),
        preferenceOverrides: {
          'homi.parent.stop-media-when-backgrounded.v1': savedMedia,
        },
      );
      final home = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      final bloc = home.settingsBloc!;
      await _settleSettings(tester, bloc);
      expect(bloc.state.vadSilenceMs, 700);
      expect(bloc.state.stopMediaWhenBackgrounded, savedMedia);
      await app.openSettings();
      if (isIos) {
        final media = find.byKey(
          const Key('settings-stop-media-background-switch'),
        );
        await tester.ensureVisible(media);
        await tester.tap(media);
        await tester.pump();
        await _settleSettings(tester, bloc);
        expect(bloc.state.stopMediaWhenBackgrounded, !savedMedia);
        expect(tester.widget<SwitchListTile>(media).value, !savedMedia);
        final recognition = find.byKey(
          const Key('settings-recognition-section'),
        );
        await tester.ensureVisible(recognition);
        await tester.tap(
          find.descendant(
            of: recognition,
            matching: find.text('Nhận dạng giọng nói'),
          ),
        );
        await tester.pumpAndSettle();
        final slider = find.byKey(const Key('settings-vad-silence-slider'));
        await tester.ensureVisible(slider);
        await tester.tapAt(tester.getCenter(slider));
        await tester.pump();
        expect(bloc.state.vadSilenceMs, isNot(700));
        expect(home.controller.vadSilenceMs, bloc.state.vadSilenceMs);
      } else {
        // No new Android controls: existing caller is delegated into Bloc.
        bloc.add(SettingsStopMediaWhenBackgroundedChanged(!savedMedia));
        await tester.pump();
        await _settleSettings(tester, bloc);
      }
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool('homi.parent.stop-media-when-backgrounded.v1'),
        !savedMedia,
      );
      home.controller.setVadSilence(2000);
      await tester.pump();
      expect(bloc.state.vadSilenceMs, 1600);
      expect(home.controller.vadSilenceMs, 1600);
      home.controller.phase = ConversationPhase.processing;
      home.controller.notifyListeners();
      await tester.pump();
      bloc.add(SettingsVadSilenceChanged(500));
      await tester.pump();
      expect(bloc.state.vadSilenceMs, 1600);
      expect(home.controller.vadSilenceMs, 1600);
      if (isIos) {
        expect(
          tester
              .widget<Slider>(
                find.byKey(const Key('settings-vad-silence-slider')),
              )
              .onChanged,
          isNull,
        );
      }
      home.controller.phase = ConversationPhase.idle;
      home.controller.notifyListeners();
      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pumpAndSettle();
      await app.openSettings();
      expect(bloc.state.vadSilenceMs, 1600);
      expect(bloc.state.stopMediaWhenBackgrounded, !savedMedia);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'unified Settings retains iOS HFP picker and diagnostics',
    (tester) async {
      final app = await _pumpApp(tester, surfaceSize: const Size(460, 900));
      app.hfpDevices = [
        {'id': 'ios-hfp-1', 'name': 'HM-D001', 'isConnected': true},
      ];
      await app.openSettings();
      final findHfp = find.text('Tìm HFP');
      await tester.ensureVisible(findHfp);
      await tester.tap(findHfp);
      await tester.pumpAndSettle();
      expect(find.text('Chọn thiết bị HFP'), findsOneWidget);
      expect(find.text('HM-D001'), findsOneWidget);
      expect(
        app.hfpCalls.where((call) => call.method == 'findDevices'),
        isNotEmpty,
      );
      final connects = app.hfpCalls
          .where((call) => call.method == 'connect')
          .length;
      Navigator.of(tester.element(find.text('Chọn thiết bị HFP'))).pop();
      await tester.pumpAndSettle();
      expect(
        app.hfpCalls.where((call) => call.method == 'connect').length,
        connects,
      );
      final diagnostics = find.byKey(
        const Key('open-hm-d001-control-diagnostics'),
      );
      await tester.ensureVisible(diagnostics);
      await tester.tap(diagnostics);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hm-d001-copy-log')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'SettingsBloc updates real Settings page, runtime and saved preferences',
    (tester) async {
      final app = await _pumpApp(tester, surfaceSize: const Size(460, 900));
      final home = tester.widget<HomeLearningShell>(
        find.byType(HomeLearningShell),
      );
      final bloc = BlocProvider.of<SettingsBloc>(
        tester.element(find.byType(HomeLearningShell)),
      );
      final appBloc = BlocProvider.of<AppBloc>(
        tester.element(find.byType(HomeLearningShell)),
      );
      // The language store uses a native file; let real IO complete outside the fake clock.
      await _settleSettings(tester, bloc);
      await tester.pumpAndSettle();
      expect(home.settingsBloc, same(bloc));
      expect(bloc.state.childAge, 6);
      final connectCount = app.count('connect');
      tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .onOpenSettings();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsScreen>(find.byType(SettingsScreen)).settingsBloc,
        same(bloc),
      );
      // Both platforms now use the same compact rows and choice dialogs.
      await tester.tap(find.byKey(const Key('appearance-settings-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
      await tester.pumpAndSettle();
      expect(bloc.state.themeMode, ThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.byKey(const Key('settings-child-age-group')));
      await tester.pumpAndSettle();
      final age = find.byWidgetPredicate(
        (widget) =>
            widget is ChoiceChip &&
            widget.key.toString().contains('settings-age-') &&
            (widget.label as Text).data!.startsWith('8'),
      );
      await tester.ensureVisible(age);
      await tester.tap(age);
      await tester.pumpAndSettle();
      expect(bloc.state.childAge, 8);
      expect(home.controller.childAge, 8);
      expect(appBloc.state.isReady, isTrue);

      await tester.tap(find.byKey(const Key('settings-language-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-language-zh-Hans')));
      await tester.pumpAndSettle();
      await _settleSettings(tester, bloc);
      await tester.pumpAndSettle();
      expect(bloc.state.displayLanguage, DisplayLanguage.simplifiedChinese);
      expect(
        home.controller.displayLanguage,
        DisplayLanguage.simplifiedChinese,
      );
      expect(bloc.state.saving, isFalse);
      expect(bloc.state.failures, isEmpty);
      await tester.runAsync(() async {
        const repository = StoredSettingsRepository();
        expect(await repository.readTheme(), ThemeMode.dark);
        expect(await repository.readChildAge(), 8);
        expect(
          await repository.readLanguage(),
          DisplayLanguage.simplifiedChinese,
        );
      });
      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pumpAndSettle();
      tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .onOpenSettings();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsScreen>(find.byType(SettingsScreen)).settingsBloc,
        same(bloc),
      );
      expect(bloc.state.childAge, 8);
      expect(appBloc.state.isReady, isTrue);
      expect(app.count('connect'), connectCount);
      // Older callers still go through the controller adapter, with Bloc as owner.
      home.controller.setDisplayLanguage(DisplayLanguage.vietnamese);
      await tester.pump();
      await _settleSettings(tester, bloc);
      await tester.pumpAndSettle();
      expect(bloc.state.displayLanguage, DisplayLanguage.vietnamese);
      expect(home.controller.displayLanguage, DisplayLanguage.vietnamese);
      await tester.runAsync(() async {
        expect(
          await const StoredSettingsRepository().readLanguage(),
          DisplayLanguage.vietnamese,
        );
      });
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'AppBloc limited setup enters Home and reopening consent returns to onboarding',
    (tester) async {
      final app = await _pumpApp(
        tester,
        setupCompleted: false,
        surfaceSize: const Size(460, 900),
        preferenceOverrides: {'homi.parental-privacy-consent.version': 0},
      );
      var screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      final bloc = BlocProvider.of<AppBloc>(
        tester.element(find.byType(StartupSetupScreen)),
      );
      expect(bloc.state.status, AppStatus.onboardingRequired);
      await screen.onContinueWithoutVoice();
      await tester.pumpAndSettle();
      screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(bloc.state.isLimited, isTrue);
      expect(bloc.state.isReady, isFalse);
      await screen.onCompleteSetup();
      await tester.pumpAndSettle();
      expect(find.byType(HomeLearningShell), findsOneWidget);
      expect(bloc.state.isReady, isTrue);
      expect(bloc.state.privacyConsentGranted, isFalse);
      expect(app.count('connect'), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('homi.parent-setup.version'), 1);
      tester
          .widget<HomeLearningShell>(find.byType(HomeLearningShell))
          .onManagePrivacyConsent!();
      await tester.pumpAndSettle();
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(bloc.state.isReady, isFalse);
      expect(bloc.state.isLimited, isFalse);
      expect(prefs.getInt('homi.parent-setup.version'), isNull);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'AppBloc restored Home stays ready without HOMI and on resume',
    (tester) async {
      final app = await _pumpApp(
        tester,
        surfaceSize: const Size(460, 900),
        preferenceOverrides: {
          'homi.parental-privacy-consent.version': 0,
          'homi.parental-privacy-consent.limited-mode': true,
        },
      );
      final bloc = BlocProvider.of<AppBloc>(
        tester.element(find.byType(HomeLearningShell)),
      );
      expect(bloc.state.isReady, isTrue);
      expect(app.bleConnected, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(bloc.state.isReady, isTrue);
      expect(bloc.state.isLimited, isTrue);
      expect(find.byType(HomeLearningShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'AppBloc startup failure displays retry and injected loader can recover',
    (tester) async {
      var loads = 0;
      await _pumpApp(
        tester,
        setupCompleted: false,
        appDependenciesFactory: ({required initialize, required onResumed}) {
          return AppDependencies(
            initialize: () async {
              if (++loads == 1) {
                throw StateError('local startup fixture failure');
              }
              return initialize();
            },
            onResumed: onResumed,
          );
        },
      );
      expect(find.byKey(const Key('app-startup-retry')), findsOneWidget);
      expect(find.byType(StartupSetupScreen), findsNothing);
      await tester.tap(find.byKey(const Key('app-startup-retry')));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.byKey(const Key('app-startup-retry')), findsNothing);
      expect(find.byType(StartupSetupScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'AppBloc full onboarding retains the existing HOMI completion gate',
    (tester) async {
      await _pumpApp(tester, setupCompleted: false);
      final screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      final bloc = BlocProvider.of<AppBloc>(
        tester.element(find.byType(StartupSetupScreen)),
      );
      expect(bloc.state.privacyConsentGranted, isTrue);
      expect(screen.homiBleConnected, isFalse);
      await screen.onCompleteSetup();
      await tester.pumpAndSettle();
      expect(bloc.state.status, AppStatus.onboardingRequired);
      expect(find.byType(HomeLearningShell), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          'homi.parent-setup.version',
        ),
        isNull,
      );
    },
    variant: android,
  );

  for (final invalidProfile in [true, false]) {
    testWidgets(
      'AppBloc rejects persisted setup with ${invalidProfile ? 'invalid age' : 'outdated consent'}',
      (tester) async {
        await _pumpApp(
          tester,
          preferenceOverrides: invalidProfile
              ? {'innotrik.child-age.v1': 99}
              : {'homi.parental-privacy-consent.version': 0},
        );
        final bloc = BlocProvider.of<AppBloc>(
          tester.element(find.byType(StartupSetupScreen)),
        );
        expect(bloc.state.status, AppStatus.onboardingRequired);
        expect(find.byType(HomeLearningShell), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: android,
    );
  }

  for (final useService in [true, false]) {
    testWidgets(
      'onboarding connection succeeds with verified MAIN and HFP; service=$useService',
      (tester) async {
        final app = await _pumpApp(
          tester,
          setupCompleted: false,
          useService: useService,
        );
        app.scanDevices = [
          {
            'id': _NativeApp.deviceId,
            'name': 'HM-D001',
            'rssi': -30,
            'advertisesControlService': true,
          },
        ];
        app.bleConnect = () async {
          app.bleConnected = true;
          return app.bleStatus;
        };
        app.hfpDevices = [
          {'id': _NativeApp.deviceId, 'name': 'HM-D001', 'isConnected': true},
        ];
        app.hfpConnectSucceeds = true;
        expect(
          find.byType(BlocConsumer<DeviceBloc, DeviceState>),
          useService ? findsOneWidget : findsNothing,
        );
        final result = tester
            .widget<StartupSetupScreen>(find.byType(StartupSetupScreen))
            .onSetupHomi();
        await _drainConnectionRound(tester);
        expect(await result, isTrue);
        final screen = tester.widget<StartupSetupScreen>(
          find.byType(StartupSetupScreen),
        );
        expect(
          BlocProvider.of<AppBloc>(
            tester.element(find.byType(StartupSetupScreen)),
          ).state.status,
          AppStatus.onboardingRequired,
          reason: 'Device ready does not complete parental onboarding',
        );
        expect(screen.homiBleConnected, isTrue);
        expect(screen.homiHfpConfigured, isTrue);
        expect(
          app.hfpCalls.where((c) => c.method == 'startAudioRoute'),
          isEmpty,
        );
        if (useService) {
          final bloc = BlocProvider.of<DeviceBloc>(
            tester.element(find.byType(StartupSetupScreen)),
          );
          expect(bloc.state.stage, DeviceStage.ready);
          expect(bloc.state.snapshot.routeActive, isFalse);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'new onboarding cancellation during audio inventory cannot start late BLE scan',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      final inventory = Completer<List<Map<String, Object?>>>();
      app.hfpFind = () => inventory.future;
      final screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      final pending = screen.onSetupHomi();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final cancellation = screen.onCancelHomiSetup!();
      await tester.pump();
      await cancellation;
      inventory.complete([]);
      await _drainConnectionRound(tester);
      expect(await pending, isFalse);
      expect(app.count('scan'), 0);
      expect(app.hfpCalls.where((c) => c.method == 'connect'), isEmpty);
    },
    variant: android,
  );

  testWidgets(
    'failed MAIN connection never opens or connects a microphone',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      app.hfpDevices = [
        {'id': 'headset-1', 'name': 'HM-D001', 'isConnected': true},
      ];
      await _openPermissionStep(tester);
      await _tapConnectHomi(tester);
      await _drainConnectionRound(tester);
      expect(app.count('scan'), greaterThan(0));
      expect(find.text('Chọn micro HOMI'), findsNothing);
      expect(app.hfpCalls.where((call) => call.method == 'connect'), isEmpty);
      if (defaultTargetPlatform == TargetPlatform.android) {
        expect(find.text('Còn một bước kết nối'), findsOneWidget);
        expect(find.text('Ghép đôi Bluetooth'), findsOneWidget);
        expect(find.text('Tiếp tục kết nối'), findsOneWidget);
      } else {
        expect(find.textContaining('Chưa kết nối'), findsWidgets);
      }
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
        {'id': 'other-mic', 'name': 'Tai nghe Bluetooth', 'isConnected': true},
      ];
      await _openPermissionStep(tester);
      await _tapConnectHomi(tester);
      for (var i = 0; i < 30; i++) {
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
            .homiBleConnected,
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
            'isConnected': true,
          },
        );
        await _openPermissionStep(tester);
        await tester.tap(find.byKey(const Key('startup-setup-hm-d001')));
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
                ? 'startup-setup-hm-d001'
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
      expect(find.byKey(const Key('startup-setup-hm-d001')), findsNothing);
      expect(app.count('requestPermissions'), 0);
      app.microphoneGranted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('startup-request-permissions')),
        findsNothing,
      );
      expect(find.byKey(const Key('startup-setup-hm-d001')), findsOneWidget);
      app.microphoneGranted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Cấp quyền còn thiếu'), findsOneWidget);
      expect(find.byKey(const Key('startup-setup-hm-d001')), findsNothing);
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
      final connection = screen.onSetupHomi();
      await tester.pump();
      expect(app.count('requestPermissions'), greaterThan(0));
      await screen.onCancelHomiSetup!();
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
      final sheet = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
      expect(sheet.controller.aiv0BleStatus.isConnected, isTrue);
      expect(sheet.controller.homiConnectionState().isHomiReady, isFalse);
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
      expect(sheet.controller.homiConnectionState().isHomiReady, isFalse);
      expect(find.text('HOMI đã sẵn sàng'), findsNothing);
      expect(find.text('Kết nối thành công'), findsNothing);
      expect(find.text('Mic chưa kết nối'), findsWidgets);
    },
    variant: android,
  );

  testWidgets(
    'Settings can discover and pair a new Classic HOMI through the shared retry action',
    (tester) async {
      final app = await _pumpApp(tester);
      app.classicDevices = [
        {'id': _NativeApp.deviceId, 'name': 'HM-D001', 'rssi': -35},
      ];
      app.scanDevicesAfterBond = app.classicDevices;
      app.bleConnect = () async {
        app.bleConnected = true;
        return app.bleStatus;
      };
      await app.openSettings();
      app.bleCalls.clear();
      final connect = find.byKey(const Key('settings-homi-connect'));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await _drainConnectionRound(tester);

      expect(app.count('scanClassic'), 1);
      expect(app.count('requestDualModeBond'), 1);
      expect(app.count('connect'), 1);
      final sheet = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
      expect(sheet.controller.aiv0BleStatus.isConnected, isTrue);
      expect(sheet.connectionCoordinator!.phase, DeviceConnectionPhase.failed);
      expect(sheet.controller.homiConnectionState().isHomiReady, isFalse);
    },
    variant: android,
  );

  testWidgets(
    'first setup connects MAIN before HOMI audio and guides each settings step',
    (tester) async {
      final app = await _pumpApp(tester, setupCompleted: false);
      // Simulate the reported observation: audio connected, no MAIN advert.
      // This fixture does not establish why the real radio failed.
      app.hfpDevices = [
        {'id': _NativeApp.deviceId, 'name': 'HM-D001', 'isConnected': true},
      ];
      app.bleConnect = () async {
        app.bleConnected = true;
        return app.bleStatus;
      };
      await _openPermissionStep(tester);
      await _tapConnectHomi(tester);
      await _drainConnectionRound(tester);
      await tester.pumpAndSettle();

      expect(app.count('scan'), greaterThan(0));
      expect(app.count('connect'), 0);
      expect(find.byKey(const Key('homi-guide-pause-audio')), findsOneWidget);
      expect(
        find.textContaining(
          'Âm thanh HOMI đã kết nối, nhưng chưa tìm thấy nút MAIN.',
        ),
        findsWidgets,
      );
      expect(find.textContaining('MAIN chỉ kết nối được'), findsNothing);
      final openSettings = find.byKey(const Key('homi-guide-open-settings'));
      await tester.ensureVisible(openSettings);
      await tester.tap(openSettings);
      await tester.pumpAndSettle();
      expect(app.count('openBluetoothSettings'), 1);

      // Parent turns HOMI audio off; MAIN advertises again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      app.hfpDevices = [
        {'id': _NativeApp.deviceId, 'name': 'HM-D001', 'isConnected': false},
      ];
      app.scanDevices = [
        {
          'id': _NativeApp.deviceId,
          'name': 'HM-D001',
          'rssi': -35,
          'advertisesControlService': true,
        },
      ];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _drainConnectionRound(tester);
      await tester.pumpAndSettle();

      var screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(screen.homiBleConnected, isTrue);
      expect(screen.homiHfpConfigured, isFalse);
      expect(app.count('connect'), 1);
      expect(find.byKey(const Key('homi-guide-enable-audio')), findsOneWidget);
      final enableAudioSettings = find.byKey(
        const Key('homi-guide-open-settings'),
      );
      await tester.ensureVisible(enableAudioSettings);
      await tester.tap(enableAudioSettings);
      await tester.pumpAndSettle();
      expect(app.count('openBluetoothSettings'), 2);

      // Parent turns HOMI audio back on while MAIN stays connected.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      app.hfpDevices = [
        {'id': _NativeApp.deviceId, 'name': 'HM-D001', 'isConnected': true},
      ];
      app.hfpConnectSucceeds = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _drainConnectionRound(tester);
      await tester.pumpAndSettle();

      screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(screen.homiBleConnected, isTrue);
      expect(screen.homiHfpConfigured, isTrue);
      expect(app.count('scanClassic'), 0);
      expect(tester.takeException(), isNull);
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
      expect(screen.homiBleConnected, isTrue);
      expect(screen.homiHfpConfigured, isFalse);
      final connection = screen.onSetupHomi();
      await _drainConnectionRound(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Kết nối thành công'), findsNothing);

      expect(await connection, isFalse);
      screen = tester.widget<StartupSetupScreen>(
        find.byType(StartupSetupScreen),
      );
      expect(screen.homiHfpConfigured, isFalse);
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
  for (var i = 0; i < 2; i++) {
    await confirmVisibleOnboardingChoices(tester);
    final next = find.byKey(const Key('startup-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
  }
}

/// Taps "Kết nối HOMI". MAIN connects first; audio guides open afterwards.
Future<void> _tapConnectHomi(WidgetTester tester) async {
  final setupHomi = find.byKey(const Key('startup-setup-hm-d001'));
  await tester.ensureVisible(setupHomi);
  await tester.tap(setupHomi);
}

Future<void> _drainConnectionRound(WidgetTester tester) async {
  for (var i = 0; i < 26; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump();
}

Future<void> _settleSettings(WidgetTester tester, SettingsBloc bloc) async {
  // Native file IO and Bloc handlers use real IO and the widget fake clock,
  // respectively. Drive both without waiting for a fake-zone future in runAsync.
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (!bloc.state.loading && !bloc.state.saving) return;
  }
  fail(
    'Settings did not settle: loading=${bloc.state.loading}, saving=${bloc.state.saving}',
  );
}

Future<_NativeApp> _pumpApp(
  WidgetTester tester, {
  String adapterState = 'poweredOn',
  bool bleConnected = false,
  bool setupCompleted = true,
  bool useService = true,
  Size surfaceSize = const Size(390, 844),
  Map<String, Object> preferenceOverrides = const {},
  AppDependenciesFactory? appDependenciesFactory,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{
    'innotrik.child-age.v1': 6,
    if (setupCompleted) 'homi.parent-setup.version': 1,
    'innotrik.user-onboarding.version': 1,
    'homi.parental-privacy-consent.version': 3,
    ...preferenceOverrides,
  });
  final app = _NativeApp(
    tester,
    adapterState: adapterState,
    bleConnected: bleConnected,
  );
  app.installChannels();
  addTearDown(app.close);
  await tester.pumpWidget(
    AiSpeakingApp(
      useDeviceConnectionService: useService,
      appDependenciesFactory: appDependenciesFactory,
    ),
  );
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
    'plugins.flutter.io/local_auth',
  ];
  final WidgetTester tester;
  final supportDirectory = Directory.systemTemp.createTempSync(
    'homi-power-app-test-',
  );
  final bleCalls = <MethodCall>[];
  final hfpCalls = <MethodCall>[];
  List<Map<String, Object?>> hfpDevices = [];
  List<Map<String, Object?>> scanDevices = [];
  List<Map<String, Object?>> classicDevices = [];
  List<Map<String, Object?>>? scanDevicesAfterBond;
  Future<Map<String, Object?>> Function()? bleConnect;
  Future<List<Map<String, Object?>>> Function()? bleScan;
  String adapterState;
  bool bleConnected;
  bool hfpConnectSucceeds = false;
  Future<List<Map<String, Object?>>> Function()? hfpFind;
  bool enableAccepted = false;
  bool microphoneGranted = true;
  bool? bluetoothGranted;
  final microphoneCalls = <MethodCall>[];
  Future<bool> Function()? enableRequest;
  Future<bool> Function()? permissionRequest;
  Future<bool> Function()? bondRequest;
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
        if (name == 'plugins.flutter.io/local_auth') return true;
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
          if (call.method == 'findDevices') {
            return hfpFind == null ? hfpDevices : await hfpFind!();
          }
          if (call.method == 'connect' && hfpConnectSucceeds) {
            return {
              'phase': 'ready',
              'deviceId': deviceId,
              'deviceName': 'HM-D001',
              'routeActive': false,
            };
          }
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
              return await bondRequest?.call() ?? true;
            case 'scanClassic':
              return classicDevices;
            case 'scan':
              if (adapterState != 'poweredOn') {
                throw PlatformException(code: 'BLUETOOTH_DISABLED');
              }
              if (bleScan != null) return await bleScan!();
              return count('requestDualModeBond') > 0
                  ? scanDevicesAfterBond ?? scanDevices
                  : scanDevices;
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
    await tester.tap(find.byKey(const Key('settings-audio-hm-d001-section')));
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
