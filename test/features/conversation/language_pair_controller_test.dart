import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/result_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConversationController buildController(_PairRepository repository) =>
      ConversationController(
        audioInput: _FakeAudioInput(),
        playbackService: const _FakePlaybackService(),
        repository: repository,
        childAge: 6,
      );

  test('defaults to Vietnamese → English and forwards each pair', () {
    final repository = _PairRepository();
    final controller = buildController(repository);
    addTearDown(controller.dispose);

    expect(controller.sourceLanguage, TranslationOutputLanguage.vietnamese);
    expect(controller.outputLanguage, TranslationOutputLanguage.english);
    expect(controller.isVietnameseToEnglish, isTrue);

    controller.setSourceLanguage(TranslationOutputLanguage.japanese);
    expect(controller.sourceLanguage, TranslationOutputLanguage.japanese);
    expect(controller.outputLanguage, TranslationOutputLanguage.english);
    expect(controller.isVietnameseToEnglish, isFalse);
    expect(repository.source, TranslationOutputLanguage.japanese);
    expect(repository.target, TranslationOutputLanguage.english);

    controller.setOutputLanguage(TranslationOutputLanguage.korean);
    expect(repository.target, TranslationOutputLanguage.korean);
  });

  test('choosing the other side of the pair swaps instead of duplicating', () {
    final repository = _PairRepository();
    final controller = buildController(repository);
    addTearDown(controller.dispose);

    controller.setSourceLanguage(TranslationOutputLanguage.english);
    expect(controller.sourceLanguage, TranslationOutputLanguage.english);
    expect(controller.outputLanguage, TranslationOutputLanguage.vietnamese);

    controller.setOutputLanguage(TranslationOutputLanguage.english);
    expect(controller.sourceLanguage, TranslationOutputLanguage.vietnamese);
    expect(controller.outputLanguage, TranslationOutputLanguage.english);

    controller.setOutputLanguage(TranslationOutputLanguage.french);
    controller.swapTranslationLanguages();
    expect(controller.sourceLanguage, TranslationOutputLanguage.french);
    expect(controller.outputLanguage, TranslationOutputLanguage.vietnamese);
    expect(repository.source, TranslationOutputLanguage.french);
    expect(repository.target, TranslationOutputLanguage.vietnamese);
  });

  test('the pair cannot change while a turn is being processed', () {
    final repository = _PairRepository();
    final controller = buildController(repository)
      ..phase = ConversationPhase.processing;
    addTearDown(controller.dispose);

    expect(controller.canChangeTranslationLanguages, isFalse);
    controller.setSourceLanguage(TranslationOutputLanguage.japanese);
    controller.setOutputLanguage(TranslationOutputLanguage.french);
    controller.swapTranslationLanguages();
    expect(controller.sourceLanguage, TranslationOutputLanguage.vietnamese);
    expect(controller.outputLanguage, TranslationOutputLanguage.english);
    expect(repository.source, TranslationOutputLanguage.vietnamese);
  });

  testWidgets('result labels follow the result, not the current selection', (
    tester,
  ) async {
    const result = ConversationResult(
      conversationId: 'conv_ja_ko',
      sessionId: 'sess',
      context: PracticeContext.home,
      vietnameseText: '',
      englishText: '',
      sourceLanguage: TranslationOutputLanguage.japanese,
      sourceText: 'お水が飲みたい',
      outputLanguage: TranslationOutputLanguage.korean,
      translatedText: '물 마시고 싶어요',
      audioUri: null,
      processingMode: 'ai',
      textSource: 'cloudflare',
      audioSource: 'device_tts',
      asrMode: 'text',
      latency: ConversationLatency(
        asrMs: 0,
        llmMs: 0,
        ttsMs: 0,
        timeToFirstAudioMs: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResultPanel(
              result: result,
              onPlay: () {},
              // The current selection differs from the result's pair.
              sourceLanguage: TranslationOutputLanguage.vietnamese,
              outputLanguage: TranslationOutputLanguage.english,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Câu tiếng Nhật'), findsOneWidget);
    expect(find.text('Câu tiếng Hàn'), findsOneWidget);
    expect(find.text('お水が飲みたい'), findsOneWidget);
    expect(find.text('Câu tiếng Việt'), findsNothing);
  });

  testWidgets('the screen shows both pickers and swaps the pair', (
    tester,
  ) async {
    final repository = _PairRepository();
    final controller = buildController(repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: controller,
          onOpenHistory: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('translation-source-language')), findsOne);
    expect(find.byKey(const Key('translation-output-language')), findsOne);

    await tester.tap(find.byKey(const Key('translation-swap-languages')));
    await tester.pumpAndSettle();
    expect(controller.sourceLanguage, TranslationOutputLanguage.english);
    expect(controller.outputLanguage, TranslationOutputLanguage.vietnamese);
    expect(repository.source, TranslationOutputLanguage.english);
  });
}

class _PairRepository extends DemoConversationRepository
    implements TranslationTargetRepository, TranslationSourceRepository {
  _PairRepository();

  TranslationOutputLanguage source = TranslationOutputLanguage.vietnamese;
  TranslationOutputLanguage target = TranslationOutputLanguage.english;

  @override
  void setTranslationSource(TranslationOutputLanguage language) =>
      source = language;

  @override
  void setTranslationTarget(TranslationOutputLanguage language) =>
      target = language;
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
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
