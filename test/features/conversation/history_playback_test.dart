import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConversationController buildController(
    _RecordingPlaybackService playback,
    VoicePromptService? prompts,
  ) {
    final controller = ConversationController(
      audioInput: const _SilentAudioInput(),
      playbackService: playback,
      voicePromptService: prompts,
      repository: const DemoConversationRepository(),
      childAge: 6,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  ConversationHistoryItem historyItem({
    TranslationOutputLanguage language = TranslationOutputLanguage.japanese,
    String? translatedText = '水が飲みたいです。',
    Uri? audioUri,
  }) => ConversationHistoryItem(
    conversationId: 'conv_history',
    vietnameseText: 'Con muốn uống nước.',
    englishText: '',
    outputLanguage: language,
    translatedText: translatedText,
    createdAt: DateTime(2026, 11, 16),
    qualityApproved: null,
    audioUri: audioUri,
  );

  test('replays the stored backend audio when the record has one', () async {
    final playback = _RecordingPlaybackService();
    final prompts = _RecordingVoicePromptService();
    final controller = buildController(playback, prompts);
    final audioUri = Uri.parse('https://cdn.example.com/audio/ja.mp3');

    await controller.playHistoryItem(historyItem(audioUri: audioUri));

    expect(playback.played, <Uri>[audioUri]);
    expect(prompts.spoken, isEmpty);
  });

  test(
    'speaks the stored translation in its own language without audio',
    () async {
      final playback = _RecordingPlaybackService();
      final prompts = _RecordingVoicePromptService();
      final controller = buildController(playback, prompts);

      await controller.playHistoryItem(historyItem());

      expect(playback.played, isEmpty);
      expect(prompts.spoken, <(String, String)>[('水が飲みたいです。', 'ja-JP')]);
    },
  );

  test('reports a missing device voice instead of staying silent', () async {
    final controller = buildController(_RecordingPlaybackService(), null);

    await expectLater(
      controller.playHistoryItem(historyItem()),
      throwsA(isA<PlaybackException>()),
    );
  });

  test('rejects a record with neither audio nor translation', () async {
    final prompts = _RecordingVoicePromptService();
    final controller = buildController(_RecordingPlaybackService(), prompts);

    await expectLater(
      controller.playHistoryItem(historyItem(translatedText: null)),
      throwsA(isA<StateError>()),
    );
    expect(prompts.spoken, isEmpty);
  });
}

class _RecordingVoicePromptService implements VoicePromptService {
  final List<(String, String)> spoken = <(String, String)>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add((text, locale));
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _RecordingPlaybackService implements AudioPlaybackService {
  final List<Uri> played = <Uri>[];

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    played.add(uri);
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

class _SilentAudioInput implements AudioInput {
  const _SilentAudioInput();

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Mic test';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> start() async {}

  @override
  Future<AudioCapture> stop() => throw UnimplementedError();
}
