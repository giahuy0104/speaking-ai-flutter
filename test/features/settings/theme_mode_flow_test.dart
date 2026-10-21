import 'dart:async';

import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/app_theme_mode.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadGoldenFonts);
  const offlineSpeechChannel = MethodChannel('homi_offline_speech');
  const offlineTranslationChannel = MethodChannel(
    'homi_offline_translation_models',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(offlineSpeechChannel, (call) async {
          if (call.method == 'model.status') {
            return <String, Object?>{
              'state': 'installed',
              'strictOnDeviceAvailable': true,
              'appManaged': true,
              'progress': 100,
            };
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          offlineTranslationChannel,
          (call) async => call.method == 'model.status' ? true : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(offlineSpeechChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(offlineTranslationChannel, null);
  });

  for (final variant
      in <({Size size, double scale, ThemeMode mode, String name})>[
        (size: Size(390, 844), scale: 1, mode: ThemeMode.light, name: 'light'),
        (size: Size(390, 844), scale: 1, mode: ThemeMode.dark, name: 'dark'),
        (
          size: Size(320, 568),
          scale: 2,
          mode: ThemeMode.light,
          name: 'small-large-text',
        ),
      ]) {
    testWidgets('grouped Settings layout ${variant.name}', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ConversationController(
        audioInput: _FakeAudioInput(),
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 3,
      );
      final coordinator = DeviceConnectionCoordinator(
        onConnect: () async => false,
        onCancel: () async {},
        onOpenBluetoothSettings: () async {},
      );
      addTearDown(controller.dispose);
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: createAppRouter().onGenerateRoute,
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: variant.mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(variant.scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SettingsSheet(
              controller: controller,
              connectionCoordinator: coordinator,
              themeMode: variant.mode == ThemeMode.light
                  ? ThemeMode.system
                  : variant.mode,
              onThemeModeChanged: (_) {},
              onChildAgeChanged: controller.setChildAge,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('settings-homi-connect')).hitTestable(),
        findsOneWidget,
      );
      if (variant.scale == 1) {
        expect(
          find.byKey(const Key('settings-privacy-policy')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings-terms')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings-support')).hitTestable(),
          findsOneWidget,
        );
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings-grouped-${variant.name}.png'),
      );
      // Both preference sheets and legal rows remain reachable on narrow/large text screens.
      await tester.ensureVisible(
        find.byKey(const Key('settings-language-row')),
      );
      await tester.tap(find.byKey(const Key('settings-language-row')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/settings-language-picker-${variant.name}.png',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings-language-zh-Hans')));
      await tester.pumpAndSettle();
      expect(controller.displayLanguage, DisplayLanguage.simplifiedChinese);
      await tester.ensureVisible(find.byKey(const Key('settings-terms')));
      expect(
        find.byKey(const Key('settings-terms')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('theme mode is persisted and restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = AppThemeModeStore();

    expect(await store.read(), ThemeMode.system);

    await store.write(ThemeMode.dark);

    expect(await store.read(), ThemeMode.dark);
  });

  testWidgets('settings switches between dark and light immediately', (
    tester,
  ) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
    addTearDown(controller.dispose);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          onGenerateRoute: createAppRouter().onGenerateRoute,
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: value,
          home: Scaffold(
            body: SettingsSheet(
              controller: controller,
              themeMode: value,
              onThemeModeChanged: (nextMode) => mode.value = nextMode,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('appearance-settings-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Đóng').last);
    await tester.pumpAndSettle();
    expect(mode.value, ThemeMode.system);
    await tester.tap(find.byKey(const Key('appearance-settings-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(mode.value, ThemeMode.dark);
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('appearance-settings-card'))),
      ).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const Key('appearance-settings-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(mode.value, ThemeMode.light);
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('appearance-settings-card'))),
      ).brightness,
      Brightness.light,
    );
  });

  for (final largeText in [false, true]) {
    testWidgets('settings changes the child age group (large text: $largeText)', (
      tester,
    ) async {
      tester.view.physicalSize = largeText
          ? const Size(320, 568)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ConversationController(
        audioInput: _FakeAudioInput(),
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
      );
      addTearDown(controller.dispose);
      int? selectedAge;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: createAppRouter().onGenerateRoute,
          theme: buildAppTheme(),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: SettingsSheet(
              controller: controller,
              onChildAgeChanged: (age) {
                selectedAge = age;
                controller.setChildAge(age);
              },
            ),
          ),
        ),
      );

      expect(find.byType(ChoiceChip), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('settings-child-age-group')),
      );
      await tester.tap(find.byKey(const Key('settings-child-age-group')));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      if (!largeText) {
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('settings-age-3-5'))).dy,
          tester.getTopLeft(find.byKey(const ValueKey('settings-age-6-7'))).dy,
        );
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/settings-age-chips-${largeText ? 'large-text' : 'light'}.png',
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-age-8-10')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-age-8-10')));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
      expect(selectedAge, 8);
      expect(controller.childAge, 8);
      expect(find.text('8–10 tuổi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-child-age-group')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('settings-age-8-10')))
            .selected,
        isTrue,
      );
    });
  }

  testWidgets('settings hides the deferred background media control', (
    tester,
  ) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsSheet(
            controller: controller,
            stopMediaWhenBackgrounded: true,
            onStopMediaWhenBackgroundedChanged: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('settings-stop-media-background-switch')),
      findsNothing,
    );
  });

  testWidgets('turn settings use the shared HOMI visual system', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: _disableAnimations,
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings-turn-controls-390x844.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dark settings keep the shared HOMI visual system', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildDarkAppTheme(),
        themeMode: ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark-settings-turn-controls-390x844.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('H20 settings use one compact shared surface', (tester) async {
    await _usePhoneSurface(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      aiv0BleControl: _DiagnosticAiv0BleControl(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: _disableAnimations,
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final settingsScroll = _settingsScrollable();
    final audioSection = find.byKey(const Key('settings-audio-h20-section'));
    await tester.scrollUntilVisible(
      audioSection,
      260,
      scrollable: settingsScroll,
    );
    await tester.tap(audioSection);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-h20-group')),
      320,
      scrollable: settingsScroll,
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings-h20-390x844.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('device information hides redundant technical settings', (
    tester,
  ) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        theme: buildAppTheme(),
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-audio-h20-section')));
    await tester.pumpAndSettle();

    expect(find.text('Thông tin thiết bị HOMI'), findsOneWidget);
    expect(find.text('Pin thiết bị'), findsOneWidget);
    expect(find.text('Thiết bị điều khiển (BLE)'), findsOneWidget);
    expect(find.text('Chọn mic'), findsOneWidget);
    expect(find.byKey(const Key('settings-recognition-section')), findsNothing);
    expect(
      find.byKey(const Key('settings-stop-media-background-switch')),
      findsNothing,
    );
    expect(find.text('Mic điện thoại'), findsNothing);
    expect(find.text('Kết nối HOMI'), findsNothing);
    expect(find.text('Micro thực tế'), findsNothing);
    expect(find.text('Loa thực tế'), findsNothing);
    expect(find.text('Đường SCO'), findsNothing);
    expect(find.text('Kiểm tra phần cứng HOMI offline'), findsNothing);
  });

  testWidgets('device settings keep diagnostics out of the parent view', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      aiv0BleControl: _DiagnosticAiv0BleControl(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        theme: buildAppTheme(),
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('settings-audio-h20-section')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Thiết bị điều khiển (BLE)'), findsOneWidget);
    expect(find.byKey(const Key('aiv0-technical-details')), findsNothing);
    expect(find.byKey(const Key('aiv0-native-diagnostics')), findsNothing);
    expect(find.byKey(const Key('aiv0-packet-details')), findsNothing);
    expect(find.textContaining('CBErrorDomain:7'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('settings hides removed privacy and guide shortcuts', (
    tester,
  ) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsSheet(
            controller: controller,
            privacyConsentGranted: true,
            onRevokePrivacyConsent: () async {},
            onStartTutorial: () {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('settings-revoke-privacy-consent')),
      findsNothing,
    );
    expect(find.byKey(const Key('settings-start-user-tutorial')), findsNothing);
    expect(find.text('Xem lịch sử gần đây'), findsNothing);
    expect(find.byKey(const Key('settings-privacy-policy')), findsOneWidget);
    expect(find.byKey(const Key('settings-terms')), findsOneWidget);
    expect(find.byKey(const Key('settings-support')), findsOneWidget);
  });
}

Finder _settingsScrollable() => find
    .descendant(
      of: find.byKey(const Key('settings-scroll-view')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _disableAnimations(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true),
  child: child!,
);

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}

class _DiagnosticAiv0BleControl implements Aiv0BleControl {
  final StreamController<Aiv0BleStatus> _statuses =
      StreamController<Aiv0BleStatus>.broadcast();
  final StreamController<Aiv0ButtonEvent> _buttons =
      StreamController<Aiv0ButtonEvent>.broadcast();

  @override
  Aiv0BleStatus get status => Aiv0BleStatus.fromMap(<Object?, Object?>{
    'phase': 'connected',
    'deviceId': 'H20-BLE',
    'deviceName': 'H20',
    'peripheralState': 'disconnected',
    'mainNotificationState': 'unavailable',
    'lastDisconnectCode': 'CBErrorDomain:7',
    'lastDisconnectMessage': 'The specified device has disconnected.',
    'lastDisconnectEpochMs': 1_787_987_522_081,
    'lastNotificationRecovery':
        'reconnect • peripheral=disconnected • notify=unavailable',
    'deferredRecoveryRepeatCount': 12,
    'diagnosticTimeline': <Object?>[
      <Object?, Object?>{
        'stage': 'BLE_DISCONNECTED',
        'caller': 'Aiv0BleControlBridge',
        'eventEpochMs': 1_787_987_522_081,
        'systemIsReconnecting': false,
      },
    ],
  }, protocolConfirmed: false);

  @override
  Stream<Aiv0BleStatus> get statusStream => _statuses.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttons.stream;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> markParentDiagnosticsOpened() async {}

  @override
  Future<void> dispose() async {
    await _statuses.close();
    await _buttons.close();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Aiv0BleDevice>> scan({Duration timeout = Duration.zero}) async =>
      const <Aiv0BleDevice>[];

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {}
}

class _FakeAudioInput implements ChunkedAudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Mic điện thoại';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> startChunked() async {}

  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic điện thoại',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );
}

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async {}
}
