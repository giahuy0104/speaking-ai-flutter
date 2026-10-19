import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const translation = MethodChannel('google_mlkit_on_device_translator');
  const speech = MethodChannel('ailingo_speech');
  final installed = <String>{};
  final calls = <MethodCall>[];
  Future<bool> Function()? prepareSpeech;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installed.clear();
    calls.clear();
    prepareSpeech = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(translation, (call) async {
      calls.add(call);
      if (call.method == 'nlp#closeLanguageTranslator') return null;
      final args = call.arguments as Map;
      if (args['task'] == 'download') {
        installed.add(args['model'] as String);
        return 'success';
      }
      return installed.contains(args['model']);
    });
    messenger.setMockMethodCallHandler(
      speech,
      (call) async => prepareSpeech == null ? true : await prepareSpeech!(),
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(translation, null);
    messenger.setMockMethodCallHandler(speech, null);
  });

  Future<void> openSettings(WidgetTester tester) async {
    final controller = ConversationController(
      audioInput: _IdleAudio(),
      playbackService: _IdlePlayback(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final section = find.byKey(const Key('settings-recognition-section'));
    await tester.ensureVisible(section);
    await tester.tap(
      find.descendant(of: section, matching: find.text('Nhận dạng giọng nói')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'installed iOS packs show ready without downloading',
    (tester) async {
      installed.addAll(['en', 'vi']);
      await openSettings(tester);
      expect(
        find.textContaining('Dịch Việt–Anh và Anh–Việt đã sẵn sàng'),
        findsOneWidget,
      );
      expect(
        calls.where(
          (call) =>
              call.method == 'nlp#manageLanguageModelModels' &&
              (call.arguments as Map)['task'] == 'download',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'parent enables both iOS translation packs over Wi-Fi',
    (tester) async {
      await openSettings(tester);
      final toggle = find.byKey(
        const Key('settings-offline-language-packs-switch'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final downloads = calls
          .where(
            (call) =>
                call.method == 'nlp#manageLanguageModelModels' &&
                (call.arguments as Map)['task'] == 'download',
          )
          .toList();
      expect(downloads.map((call) => (call.arguments as Map)['model']), [
        'vi',
        'en',
      ]);
      expect(
        downloads.every((call) => (call.arguments as Map)['wifi'] == true),
        isTrue,
      );
      expect(
        find.textContaining('Dịch Việt–Anh và Anh–Việt đã sẵn sàng'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'disabling downloads while Apple prepares prevents new ML Kit downloads',
    (tester) async {
      final pending = Completer<bool>();
      prepareSpeech = () => pending.future;
      await openSettings(tester);
      final toggle = find.byKey(
        const Key('settings-offline-language-packs-switch'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(
        calls.where(
          (call) =>
              call.method == 'nlp#manageLanguageModelModels' &&
              (call.arguments as Map)['task'] == 'download',
        ),
        isEmpty,
      );
      expect((tester.widget(toggle) as Switch).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

class _IdleAudio implements AudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  bool get isAvailable => true;
  @override
  bool get isBluetooth => false;
  @override
  String get label => 'Mic iPhone';
  @override
  Future<void> start() async => throw StateError('Settings must not record');
  @override
  Future<AudioCapture> stop() async =>
      throw StateError('Settings must not record');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

class _IdlePlayback implements AudioPlaybackService {
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> prepare() async {}
  @override
  Future<void> preload(Uri uri) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      throw StateError('Settings must not play');
}
