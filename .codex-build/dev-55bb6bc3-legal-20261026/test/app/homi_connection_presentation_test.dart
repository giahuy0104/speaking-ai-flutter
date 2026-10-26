import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/scenic_app_header.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/device/homi_connection_state.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
    await Future.wait<void>(<Future<void>>[roboto.load(), icons.load()]);
    const cjkFont = String.fromEnvironment('HOMI_UI_CJK_FONT');
    if (cjkFont.isNotEmpty) {
      await ui.loadFontFromList(
        await File(cjkFont).readAsBytes(),
        fontFamily: 'HomiCaptureCjk',
      );
    }
  });
  for (final language in DisplayLanguage.values) {
    testWidgets(
      'Home and vocabulary show distinct partial connections at 390px ${language.code}',
      (tester) async {
        _mobileSurface(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final controller = _UiController()..setDisplayLanguage(language);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            onGenerateRoute: createAppRouter().onGenerateRoute,
            theme: _testTheme(),
            home: HomeLearningShell(
              controller: controller,
              config: AppConfig(
                backendBaseUri: Uri.parse('https://example.com'),
                useDemoBackend: true,
                childAge: 6,
                autoStartVoiceNavigation: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final entry in <(bool, bool, bool, String, String)>[
          (false, true, false, 'Mic chưa kết nối', '麦克风未连接'),
          (true, false, true, 'Mất kết nối MAIN', 'MAIN 未连接'),
          (true, true, false, 'Cần kiểm tra mic', '请检查麦克风'),
          (true, true, true, 'Sẵn sàng', '已就绪'),
          (false, false, false, 'Chưa kết nối', '未连接'),
        ]) {
          controller.updateConnection(
            _state(hfp: entry.$1, ble: entry.$2, matches: entry.$3),
          );
          await tester.pumpAndSettle();
          final expected = language.choose(entry.$4, entry.$5);
          final homeHeader = find.byType(ScenicAppHeader, skipOffstage: false);
          expect(
            find.descendant(
              of: homeHeader,
              matching: find.text(expected, skipOffstage: false),
            ),
            findsOneWidget,
          );
          // All three partial states have isHomiReady=false. The shell must
          // still rebuild its adjacent vocabulary page when the link changes.
          final vocabulary = find.byType(
            VocabularyHomeScreen,
            skipOffstage: false,
          );
          expect(
            tester.widget<VocabularyHomeScreen>(vocabulary).connectionState,
            same(controller.connection),
          );
          await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: vocabulary, matching: find.text(expected)),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const Key('vocabulary-home-back-button')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'full-session stop bypasses BLE gate in every speaking phase ${language.code}',
      (tester) async {
        _mobileSurface(tester);
        final controller = _UiController()
          ..setDisplayLanguage(language)
          ..updateConnection(_state(hfp: true, ble: false, matches: true));
        addTearDown(controller.dispose);
        var gateCalls = 0;
        var stopCalls = 0;
        Completer<void>? stopGate;
        for (final phase in <ConversationPhase>[
          ConversationPhase.idle,
          ConversationPhase.recording,
          ConversationPhase.processing,
          ConversationPhase.ready,
        ]) {
          controller.phase = phase;
          controller.playing = phase == ConversationPhase.ready;
          stopGate = Completer<void>();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('partial-connection-ui-capture'),
              child: MaterialApp(
                onGenerateRoute: createAppRouter().onGenerateRoute,
                debugShowCheckedModeBanner: false,
                theme: _testTheme(),
                home: ConversationScreen(
                  controller: controller,
                  onOpenHistory: () {},
                  onOpenSettings: () {},
                  sessionActive: true,
                  ensureDeviceConnected: () async {
                    gateCalls++;
                    return false;
                  },
                  onStopSession: () {
                    stopCalls++;
                    return stopGate!.future;
                  },
                ),
              ),
            ),
          );
          await tester.pump();
          if (phase == ConversationPhase.recording) {
            await _capture(tester, 'main-disconnected-${language.code}.png');
          }
          final stop = find.byKey(const Key('conversation-stop-session'));
          expect(stop.hitTestable(), findsOneWidget);
          expect(
            find.text(language.choose('Dừng phiên', '结束对话')),
            findsOneWidget,
          );
          final before = stopCalls;
          await tester.tap(stop);
          await tester.tap(stop);
          await tester.pump();
          expect(stopCalls, before + 1);
          expect(gateCalls, 0);
          expect(controller.ordinaryStopCalls, 0);
          if (phase == ConversationPhase.recording) {
            await tester.tap(find.text(language.choose('Dừng ghi âm', '停止录音')));
            expect(controller.ordinaryStopCalls, 0);
          }
          expect(tester.widget<OutlinedButton>(stop).onPressed, isNull);
          expect(
            find.text(language.choose('Đang dừng phiên…', '正在结束对话…')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          stopGate.complete();
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

ThemeData _testTheme() {
  final theme = buildAppTheme();
  final outlinedStyle = theme.outlinedButtonTheme.style!;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamilyFallback: const <String>['HomiCaptureCjk'],
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outlinedStyle.copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) => outlinedStyle.textStyle
              ?.resolve(states)
              ?.copyWith(fontFamilyFallback: const <String>['HomiCaptureCjk']),
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('HOMI_UI_CAPTURE_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    final context = tester.element(find.byType(ConversationScreen));
    await Future.wait<void>(
      const <AssetImage>[
        AssetImage('assets/images/learning-minimal-sky-background.png'),
        AssetImage('assets/images/mascot/penguin-avatar.png'),
        AssetImage('assets/images/mascot/penguin-listen.png'),
      ].map((image) => precacheImage(image, context)),
    );
  });
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('partial-connection-ui-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void _mobileSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

HomiConnectionState _state({
  required bool hfp,
  required bool ble,
  required bool matches,
}) => HomiConnectionState(
  phase: hfp && ble && matches
      ? HomiConnectionPhase.homiReady
      : hfp
      ? HomiConnectionPhase.hfpReady
      : ble
      ? HomiConnectionPhase.bleReady
      : HomiConnectionPhase.disconnected,
  hfpSelected: hfp,
  hfpReady: hfp,
  routeActive: false,
  bleReady: ble,
  hfpMatchesHomi: matches,
);

class _UiController extends ConversationController {
  _UiController()
    : super(
        audioInput: _UnusedAudioInput(),
        playbackService: _UnusedPlayback(),
        repository: const DemoConversationRepository(),
        childAge: 6,
      );

  HomiConnectionState connection = _state(
    hfp: false,
    ble: false,
    matches: false,
  );
  bool playing = false;
  int ordinaryStopCalls = 0;

  @override
  HomiConnectionState homiConnectionState({bool mainTurnActive = false}) =>
      connection;

  @override
  bool get isPlaybackPlaying => playing;

  void updateConnection(HomiConnectionState state) {
    connection = state;
    notifyListeners();
  }

  @override
  Future<void> stopRecording({bool manual = false}) async {
    ordinaryStopCalls++;
  }
}

class _UnusedAudioInput implements AudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();
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
  Future<void> start() async => throw StateError('Unexpected phone recording');
  @override
  Future<AudioCapture> stop() async => throw StateError('Unexpected stop');
}

class _UnusedPlayback implements AudioPlaybackService {
  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();
  @override
  Future<void> prepare() async {}
  @override
  Future<void> preload(Uri uri) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      throw StateError('Unexpected playback');
  @override
  Future<void> stop() async {}
}
