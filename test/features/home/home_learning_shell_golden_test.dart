import 'dart:ui' as ui;

import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_mode_rail.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const backgroundEvents = MethodChannel('ailingo_background_learning/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(backgroundEvents, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(backgroundEvents, null);
  });

  testWidgets(
    'home communication matches image one',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        deviceReady: false,
        showTranslationTargets: true,
        initialResult: _homeReferenceResult,
      );
      addTearDown(controller.dispose);
      expect(find.byKey(const Key('home-main-button')), findsNothing);
      expect(find.byKey(const Key('home-conversation-tab')), findsNothing);
      expect(find.byKey(const Key('home-history-tab')), findsNothing);
      expect(find.text('Kết nối HOMI'), findsOneWidget);
      expect(find.text('Con muốn đi xem phim'), findsOneWidget);
      expect(find.text('I want to go watch a movie.'), findsOneWidget);
      expect(
        find.byKey(const Key('translation-output-language')),
        findsOneWidget,
      );

      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile('goldens/home-communication-390x844.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'translation menu overlays HOMI without moving the home content',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        deviceReady: false,
        showTranslationTargets: true,
        initialResult: _homeReferenceResult,
      );
      addTearDown(controller.dispose);
      final mascot = find.image(
        const AssetImage('assets/images/mascot/penguin-listen.png'),
      );
      final wave = find.byKey(const Key('conversation-static-waveform'));
      final result = find.byKey(const Key('conversation-vietnamese-bubble'));
      final mascotBefore = tester.getRect(mascot);
      final waveBefore = tester.getRect(wave);
      final resultBefore = tester.getRect(result);

      await tester.tap(find.byKey(const Key('translation-output-language')));
      await tester.pumpAndSettle();
      final menu = find.byKey(const Key('translation-language-menu'));
      expect(menu, findsOneWidget);
      expect(tester.getRect(menu).overlaps(mascotBefore), isTrue);
      expect(tester.getRect(mascot), mascotBefore);
      expect(tester.getRect(wave), waveBefore);
      expect(tester.getRect(result), resultBefore);
      for (final language in TranslationOutputLanguage.values) {
        expect(
          find.byKey(Key('translation-language-${language.apiValue}')),
          findsOneWidget,
        );
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/home-translation-menu-${defaultTargetPlatform.name}-390x844.png',
        ),
      );

      await tester.tap(find.byKey(const Key('translation-language-ja')));
      await tester.pumpAndSettle();
      expect(controller.outputLanguage, TranslationOutputLanguage.japanese);
      expect(menu, findsNothing);
      expect(find.text('Tiếng Nhật'), findsOneWidget);
      await tester.tap(find.byKey(const Key('translation-output-language')));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(wave));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(controller.outputLanguage, TranslationOutputLanguage.japanese);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'translation selector fits a small screen with large text',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        surfaceSize: const Size(320, 568),
        textScale: 2,
        showTranslationTargets: true,
      );
      addTearDown(controller.dispose);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('translation-output-language')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('translation-language-menu')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('disconnected home matches the approved cloud tabs', (
    tester,
  ) async {
    final controller = await _pumpGoldenApp(
      tester,
      surfaceSize: const Size(458, 954),
      deviceReady: false,
    );
    addTearDown(controller.dispose);
    expect(find.text('Kết nối HOMI'), findsOneWidget);
    expect(find.text('Kết nối với HOMI để bắt đầu sử dụng'), findsOneWidget);
    await expectLater(
      find.byType(HomeLearningShell),
      matchesGoldenFile('goldens/home-disconnected-cloud-tabs-458x954.png'),
    );
  });

  for (final device
      in <({String name, Size size, double dpr, EdgeInsets insets})>[
        (
          name: 'android-1080x2400',
          size: const Size(360, 800),
          dpr: 3,
          insets: const EdgeInsets.only(top: 36, bottom: 42),
        ),
        (
          name: 'android-1080x2400-411dp',
          size: const Size(1080 / 2.625, 2400 / 2.625),
          dpr: 2.625,
          insets: const EdgeInsets.only(top: 40, bottom: 24),
        ),
      ]) {
    testWidgets('cloud labels stay inside the face on ${device.name}', (
      tester,
    ) async {
      final controller = await _pumpGoldenApp(
        tester,
        surfaceSize: device.size,
        devicePixelRatio: device.dpr,
        safeInsets: device.insets,
        deviceReady: false,
      );
      addTearDown(controller.dispose);
      final tabs = find.byType(HomeModeRail);
      expect(tabs, findsNWidgets(2));
      final left = tester.getRect(tabs.at(0));
      final right = tester.getRect(tabs.at(1));
      expect(left.top, right.top);
      expect(left.left, 0);
      expect(right.right, closeTo(device.size.width, 0.01));
      for (final tab in [tabs.at(0), tabs.at(1)]) {
        final icon = tester.getRect(
          find.descendant(
            of: tab,
            matching: find.byKey(const Key('home-mode-rail-icon')),
          ),
        );
        final label = tester.getRect(
          find.descendant(
            of: tab,
            matching: find.byKey(const Key('home-mode-rail-label')),
          ),
        );
        expect(icon.center.dx, closeTo(label.center.dx, 0.01));
        expect(label.top - icon.bottom, inInclusiveRange(8, 30));
        expect(tester.getRect(tab).contains(label.topLeft), isTrue);
        expect(tester.getRect(tab).contains(label.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
      await _expectCloudContentOnWhiteFace(tester, device.dpr);
      await _expectRoundedCloudCaps(tester, device.dpr);
      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile('goldens/home-cloud-responsive-${device.name}.png'),
      );
    });
  }

  testWidgets(
    'small disconnected home keeps both tabs readable with large text',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        surfaceSize: const Size(320, 568),
        deviceReady: false,
        textScale: 2,
      );
      addTearDown(controller.dispose);
      expect(tester.takeException(), isNull);
      final left = tester.getRect(find.byKey(const Key('vocabulary-edge-tab')));
      final right = tester.getRect(
        find.byKey(const Key('topic-listening-edge-tab')),
      );
      expect(left.top, right.top);
      expect(left.right, lessThan(right.left));
      expect(
        find.byKey(const Key('vocabulary-edge-tab')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('topic-listening-edge-tab')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Kết nối HOMI').hitTestable(), findsOneWidget);
      await _expectCloudContentOnWhiteFace(tester, 1);
      await _expectRoundedCloudCaps(tester, 1);
      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile(
          'goldens/home-disconnected-cloud-tabs-320x568-large-text.png',
        ),
      );
    },
  );

  testWidgets('vocabulary page matches image two', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeLearningShell),
      matchesGoldenFile('goldens/home-vocabulary-390x844.png'),
    );
  });

  testWidgets(
    'topic rail opens the catalog directly',
    (tester) async {
      final controller = await _pumpGoldenApp(tester);
      addTearDown(controller.dispose);

      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();

      expect(find.byType(TopicListeningScreen), findsOneWidget);
      await expectLater(
        find.byType(TopicListeningScreen),
        matchesGoldenFile('goldens/home-topic-expanded-390x844.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('add vocabulary dialog matches image three', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home-add-vocabulary-390x844.png'),
    );
  });

  testWidgets(
    'dark communication matches the approved rail treatment',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        themeMode: ThemeMode.dark,
      );
      addTearDown(controller.dispose);
      expect(find.byKey(const Key('home-main-button')), findsNothing);

      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile('goldens/dark-home-communication-390x844.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'dark home keeps the approved option two composition',
    (tester) async {
      final controller = await _pumpGoldenApp(
        tester,
        themeMode: ThemeMode.dark,
      );
      addTearDown(controller.dispose);

      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile('goldens/dark-home-communication-390x844.png'),
      );

      await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HomeLearningShell),
        matchesGoldenFile('goldens/dark-home-vocabulary-390x844.png'),
      );

      await tester.tap(find.byKey(const Key('vocabulary-practice-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(TopicListeningScreen),
        matchesGoldenFile('goldens/dark-home-topics-390x844.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<ConversationController> _pumpGoldenApp(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
  Size surfaceSize = const Size(390, 844),
  double devicePixelRatio = 1,
  EdgeInsets safeInsets = EdgeInsets.zero,
  bool? deviceReady,
  double textScale = 1,
  bool showTranslationTargets = false,
  ConversationResult? initialResult,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await _loadGoldenFonts();
  tester.view.physicalSize = surfaceSize * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.padding = FakeViewPadding(
    top: safeInsets.top * devicePixelRatio,
    bottom: safeInsets.bottom * devicePixelRatio,
  );
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final controller = ConversationController(
    audioInput: _FakeAudioInput(),
    playbackService: const _FakePlaybackService(),
    repository: showTranslationTargets
        ? const _GoldenTranslationRepository()
        : const DemoConversationRepository(),
    childAge: 6,
  )..result = initialResult;
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: createAppRouter().onGenerateRoute,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('responsive-home-capture'),
        child: HomeLearningShell(
          controller: controller,
          ensureDeviceConnected: deviceReady == null
              ? null
              : () async => deviceReady,
          isDeviceConnectionReady: deviceReady == null
              ? null
              : () => deviceReady,
          config: AppConfig(
            backendBaseUri: Uri.parse('https://example.com'),
            useDemoBackend: true,
            childAge: 6,
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(HomeLearningShell));
    await Future.wait<void>(
      const <AssetImage>[
        AssetImage('assets/images/learning-minimal-sky-background.png'),
        AssetImage('assets/images/home-hero-blob.png'),
        AssetImage('assets/images/home-hero-blob-option2.png'),
        AssetImage('assets/images/home-navigation-rays.png'),
        AssetImage('assets/images/home-cloud-tab-left.png'),
        AssetImage('assets/images/home-cloud-tab-right.png'),
        AssetImage('assets/images/mascot/penguin-avatar.png'),
        AssetImage('assets/images/mascot/penguin-listen.png'),
        AssetImage('assets/images/mascot/penguin-wave.png'),
        AssetImage('assets/images/topics/my-family.jpg'),
        AssetImage('assets/images/topics/fun-alphabet.jpg'),
        AssetImage('assets/images/topics/numbers-time.jpg'),
        AssetImage('assets/images/topics/cute-animals.jpg'),
        AssetImage('assets/images/topics/favorite-food.jpg'),
        AssetImage('assets/images/vocabulary/golden-star.png'),
        AssetImage('assets/images/vocabulary/review-book.png'),
      ].map((provider) => precacheImage(provider, context)),
    );
  });
  await tester.pumpAndSettle();
  return controller;
}

class _GoldenTranslationRepository extends DemoConversationRepository
    implements TranslationTargetRepository {
  const _GoldenTranslationRepository();

  @override
  void setTranslationTarget(TranslationOutputLanguage language) {}
}

const _homeReferenceResult = ConversationResult(
  conversationId: 'golden-home-reference',
  sessionId: 'golden-session',
  context: PracticeContext.outside,
  vietnameseText: 'Con muốn đi xem phim',
  englishText: 'I want to go watch a movie.',
  audioUri: null,
  processingMode: 'rule',
  textSource: 'phrase_rule',
  audioSource: 'device_tts',
  asrMode: 'ios_native',
  latency: ConversationLatency(
    asrMs: 0,
    llmMs: 0,
    ttsMs: 0,
    timeToFirstAudioMs: 0,
  ),
);

Future<void> _expectCloudContentOnWhiteFace(
  WidgetTester tester,
  double dpr,
) async {
  final capture = find.byKey(const Key('responsive-home-capture'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(capture);
  final origin = tester.getTopLeft(capture);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // Check painted pixels around the content, rather than only verifying
      // that its rectangular bounds fit the (partly transparent) PNG bounds.
      for (final key in ['home-mode-rail-icon', 'home-mode-rail-label']) {
        final content = find.byKey(Key(key));
        for (final element in content.evaluate()) {
          final rect = tester
              .getRect(
                find.byElementPredicate(
                  (candidate) => identical(candidate, element),
                ),
              )
              .shift(-origin);
          for (var step = 1; step < 5; step++) {
            for (final x in [rect.left - 1, rect.right + 1]) {
              final y = rect.top + rect.height * step / 5;
              final index =
                  ((y * dpr).floor() * image.width + (x * dpr).floor()) * 4;
              expect(
                bytes.getUint8(index),
                greaterThan(210),
                reason: '$key at ($x, $y) must stay on the white cloud face',
              );
              expect(bytes.getUint8(index + 1), greaterThan(230));
              expect(bytes.getUint8(index + 2), greaterThan(235));
            }
          }
        }
      }
    } finally {
      image.dispose();
    }
  });
}

Future<void> _expectRoundedCloudCaps(WidgetTester tester, double dpr) async {
  for (final element
      in find.byKey(const Key('home-cloud-artwork')).evaluate()) {
    final boundary = element.renderObject! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: dpr);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final rowWidths = <int>[];
        for (var y = 0; y < image.height; y++) {
          var painted = 0;
          for (var x = 0; x < image.width; x++) {
            if (bytes.getUint8((y * image.width + x) * 4 + 3) > 210) {
              painted++;
            }
          }
          rowWidths.add(painted);
        }
        final top = rowWidths.indexWhere((width) => width > 0);
        final bottom = rowWidths.lastIndexWhere((width) => width > 0);
        expect(top, inInclusiveRange(0, (image.height * .12).ceil()));
        expect(bottom, greaterThan(image.height * .88));
        // A stretched white strip previously produced a broad, flat ledge
        // at each end. A rounded cap tapers to a narrow painted tip instead.
        for (final tip in [top, bottom]) {
          expect(
            rowWidths[tip],
            lessThan(image.width * .28),
            reason: 'Cloud end must taper, not terminate in a square ledge',
          );
        }
      } finally {
        image.dispose();
      }
    });
  }
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

class _FakeAudioInput implements ChunkedAudioInput {
  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

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

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
