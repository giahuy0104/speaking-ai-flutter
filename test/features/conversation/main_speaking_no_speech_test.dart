import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/vietnamese_transcript_corrector.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_recording_endpoint_policy.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translation quiet window adapts to short versus long speech', () {
    for (final item in <(String, int)>[
      ('apple', 400),
      ('Con muốn uống nước', 500),
      ('Con muốn đi chơi ở công viên cùng với ba mẹ', 700),
    ]) {
      expect(
        ConversationRecordingEndpointPolicy.quietWindow(
          item.$1,
          baseSilenceMs: 700,
        ),
        Duration(milliseconds: item.$2),
      );
    }
    expect(ConversationController.translatedSpeechPlaybackRate, 0.8);
  });

  test(
    'Main speaking turn waits for its configured no-speech timeout',
    () async {
      final audioInput = _SilentAudioInput();
      final promptService = _FakeVoicePromptService(
        onReadyCue: () => expect(audioInput.startCount, greaterThan(0)),
      );
      final controller = ConversationController(
        audioInput: audioInput,
        playbackService: const _FakePlaybackService(),
        voicePromptService: promptService,
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.batchChunks,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);

      await controller.startRecording(
        noSpeechTimeout: const Duration(milliseconds: 550),
        speakNoSpeechPrompt: false,
      );
      expect(controller.isRecording, isTrue);
      expect(promptService.readyCueCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(promptService.spokenTexts, isEmpty);

      await controller.speakAssistantPrompt('tạm biệt con nhé');
      expect(promptService.spokenTexts, <String>['tạm biệt con nhé']);
    },
  );

  test('long MAIN cancels a single sentence without translating it', () async {
    final audioInput = _SilentAudioInput();
    final promptService = _FakeVoicePromptService();
    final controller = ConversationController(
      audioInput: audioInput,
      playbackService: const _FakePlaybackService(),
      voicePromptService: promptService,
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await controller.startRecording(
      noSpeechTimeout: const Duration(seconds: 10),
    );
    expect(controller.isRecording, isTrue);

    final result = await controller.cancelSingleSentenceMainAction();

    expect(result, MainButtonActionResult.accepted);
    expect(controller.phase, ConversationPhase.idle);
    expect(
      controller.lastTurnEndReason,
      ConversationTurnEndReason.commandHandled,
    );
    expect(audioInput.cancelCount, 1);
    expect(promptService.spokenTexts, isEmpty);
  });

  test(
    'manual MAIN stop asks the child to retry when Android reports no speech',
    () async {
      final promptService = _FakeVoicePromptService();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: const _NoSpeechStreamingSpeechInput(),
        playbackService: const _FakePlaybackService(),
        voicePromptService: promptService,
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, ConversationPhase.idle);
      expect(controller.lastTurnEndReason, ConversationTurnEndReason.noSpeech);
      expect(promptService.spokenTexts, <String>[
        'HOMI chưa nghe thấy bạn nói. Bạn nói lại nhé.',
      ]);
    },
  );

  test('D10 long MAIN stops active playback immediately', () async {
    final playback = _ControllablePlaybackService();
    final controller = ConversationController(
      audioInput: _SilentAudioInput(),
      playbackService: playback,
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.batchChunks,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await playback.play(Uri.parse('https://example.com/result.mp3'));
    final result = await controller.cancelCurrentMainAction();

    expect(result, MainButtonActionResult.accepted);
    expect(playback.stopCount, 1);
    expect(controller.phase, ConversationPhase.idle);
  });

  test('long MAIN suppresses a translation already processing', () async {
    final controller = ConversationController(
      audioInput: _SilentAudioInput(),
      streamingSpeechInput: const _ImmediateStreamingSpeechInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);

    await controller.startRecording(
      noSpeechTimeout: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final stopFuture = controller.stopRecording(manual: true);
    for (var attempt = 0; attempt < 50; attempt += 1) {
      if (controller.phase == ConversationPhase.processing) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.phase, ConversationPhase.processing);

    final cancelResult = await controller.cancelSingleSentenceMainAction();
    expect(cancelResult, MainButtonActionResult.accepted);
    expect(controller.phase, ConversationPhase.idle);

    await stopFuture;
    expect(controller.phase, ConversationPhase.idle);
    expect(controller.result, isNull);
  });

  test(
    'native transcript is corrected before online conversation translation',
    () async {
      final repository = _CapturingStreamingRepository();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: const _CorrectableStreamingSpeechInput(),
        playbackService: const _FakePlaybackService(),
        repository: repository,
        vietnameseTranscriptCorrector: MapVietnameseTranscriptCorrector(
          const <String, String>{
            'Con ngửa tay xong rồi': 'Con rửa tay xong rồi',
          },
        ),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await controller.stopRecording(manual: true);

      expect(repository.capture?.sourceText, 'Con rửa tay xong rồi');
      expect(
        repository.capture?.extraBenchmark?['transcriptCorrectionApplied'],
        isTrue,
      );
      expect(controller.result?.vietnameseText, 'Con rửa tay xong rồi');
    },
  );

  test(
    'Android partial transcript ends the turn after a quiet window even without further RMS events',
    () async {
      final speechInput = _PartialOnlyStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: speechInput,
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);
      controller.setVadSilence(400);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      speechInput.emitPartial('Con muốn đi công viên');
      await Future<void>.delayed(const Duration(milliseconds: 550));

      expect(speechInput.stopCount, 1);
      expect(controller.isRecording, isFalse);
    },
  );

  test('one-word Android partial also ends after the quiet window', () async {
    final speechInput = _PartialOnlyStreamingSpeechInput();
    final controller = ConversationController(
      audioInput: _SilentAudioInput(),
      streamingSpeechInput: speechInput,
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
      initialAsrMode: AsrMode.androidStreaming,
      webRuntimeOverride: false,
    );
    addTearDown(controller.dispose);
    controller.setVadSilence(400);

    await controller.startRecording(
      noSpeechTimeout: const Duration(seconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    speechInput.emitPartial('apple');
    await Future<void>.delayed(const Duration(milliseconds: 550));

    expect(speechInput.stopCount, 1);
    expect(controller.isRecording, isFalse);
  });

  test(
    'Android native end-of-speech ends translation while RMS noise stays high',
    () async {
      final speechInput = _EndpointStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: speechInput,
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);
      addTearDown(speechInput.dispose);
      controller.setVadSilence(400);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      // Quiet calibration, then steady background noise that the RMS VAD
      // keeps classifying as voice after the partial confirms speech.
      for (var i = 0; i < 4; i += 1) {
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      speechInput.emitPartial('Con muốn đi công viên');
      for (var i = 0; i < 10; i += 1) {
        speechInput.emitAmplitude(-20);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(speechInput.stopCount, 0, reason: 'RMS noise defers endpoint');

      speechInput.emitSpeechEnded('Con muốn đi công viên');
      speechInput.emitAmplitude(-20);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(speechInput.stopCount, 1);
      expect(controller.isRecording, isFalse);
    },
  );

  test(
    'late Android partials do not push back the RMS quiet endpoint',
    () async {
      final speechInput = _EndpointStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: speechInput,
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);
      addTearDown(speechInput.dispose);
      controller.setVadSilence(400);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      for (var i = 0; i < 4; i += 1) {
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      speechInput.emitPartial('Con muốn');
      for (final level in <double>[-20, -26, -20, -24, -20]) {
        speechInput.emitAmplitude(level);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // The child stopped speaking; Android keeps publishing the words it
      // heard earlier for roughly another second.
      for (var i = 0; i < 5; i += 1) {
        if (i == 2) speechInput.emitPartial('Con muốn đi');
        if (i == 4) speechInput.emitPartial('Con muốn đi công viên');
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(speechInput.stopCount, 1);
      expect(controller.isRecording, isFalse);
    },
  );

  test(
    'RMS quiet endpoint keeps the configured silence for a short phrase',
    () async {
      final speechInput = _EndpointStreamingSpeechInput();
      final controller = ConversationController(
        audioInput: _SilentAudioInput(),
        streamingSpeechInput: speechInput,
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
        initialAsrMode: AsrMode.androidStreaming,
        webRuntimeOverride: false,
      );
      addTearDown(controller.dispose);
      addTearDown(speechInput.dispose);
      controller.setVadSilence(700);

      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 5),
      );
      for (var i = 0; i < 4; i += 1) {
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      speechInput.emitPartial('Con muốn');
      for (final level in <double>[-20, -26, -20]) {
        speechInput.emitAmplitude(level);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // A child hesitating mid-sentence: the word-count window for two words
      // would already have ended the turn.
      for (var i = 0; i < 5; i += 1) {
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(speechInput.stopCount, 0);

      for (var i = 0; i < 4; i += 1) {
        speechInput.emitAmplitude(-60);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(speechInput.stopCount, 1);
    },
  );
}

class _SilentAudioInput implements ChunkedAudioInput {
  int cancelCount = 0;
  int startCount = 0;

  @override
  String get label => 'Mic kiểm thử';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> startChunked() async {
    startCount += 1;
  }

  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic kiểm thử',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

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

class _ControllablePlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int stopCount = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    _playing.add(true);
    await Future<void>.delayed(Duration.zero);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _playing.add(false);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await _playing.close();
  }
}

class _FakeVoicePromptService
    implements VoicePromptService, SpeechReadyCuePlayer {
  _FakeVoicePromptService({this.onReadyCue});
  final void Function()? onReadyCue;
  final List<String> spokenTexts = <String>[];
  int readyCueCount = 0;

  @override
  Future<void> playSpeechReadyCue() async {
    onReadyCue?.call();
    readyCueCount += 1;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _ImmediateStreamingSpeechInput implements StreamingSpeechInput {
  const _ImmediateStreamingSpeechInput();

  @override
  String get label => 'ASR Android kiểm thử';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn đi công viên',
    duration: Duration(seconds: 1),
    inputLabel: 'ASR Android kiểm thử',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _PartialOnlyStreamingSpeechInput implements StreamingSpeechInput {
  final StreamController<String> _partials = StreamController<String>.broadcast(
    sync: true,
  );
  int stopCount = 0;

  void emitPartial(String text) => _partials.add(text);

  @override
  String get label => 'ASR Android partial-only';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => _partials.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async {
    stopCount += 1;
    return const StreamingSpeechCapture(
      sourceText: 'Con muốn đi công viên',
      duration: Duration(seconds: 1),
      inputLabel: 'ASR Android partial-only',
      confidence: 0.9,
      firstResultMs: 100,
      finalAfterStopMs: 20,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _partials.close();
}

class _EndpointStreamingSpeechInput
    implements StreamingSpeechInput, SpeechEndpointInput {
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast(sync: true);
  final StreamController<String> _partials = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<String> _speechEnded =
      StreamController<String>.broadcast(sync: true);
  int stopCount = 0;

  void emitAmplitude(double dbfs) => _amplitude.add(dbfs);

  void emitPartial(String text) => _partials.add(text);

  void emitSpeechEnded(String text) => _speechEnded.add(text);

  @override
  String get label => 'ASR Android endpoint';

  @override
  Stream<double> get amplitudeDbfs => _amplitude.stream;

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => _partials.stream;

  @override
  Stream<String> get speechEnded => _speechEnded.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async {
    stopCount += 1;
    return const StreamingSpeechCapture(
      sourceText: 'Con muốn đi công viên',
      duration: Duration(seconds: 1),
      inputLabel: 'ASR Android endpoint',
      confidence: 0.9,
      firstResultMs: 100,
      finalAfterStopMs: 20,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    if (_amplitude.isClosed) return;
    await _amplitude.close();
    await _partials.close();
    await _speechEnded.close();
  }
}

class _NoSpeechStreamingSpeechInput implements StreamingSpeechInput {
  const _NoSpeechStreamingSpeechInput();

  @override
  String get label => 'ASR Android im lặng';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async {
    throw const StreamingSpeechInputException(
      'Không nghe thấy giọng nói.',
      code: 'ANDROID_SPEECH_7',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _CorrectableStreamingSpeechInput implements StreamingSpeechInput {
  const _CorrectableStreamingSpeechInput();

  @override
  String get label => 'ASR cần sửa câu';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con ngửa tay xong rồi',
    duration: Duration(seconds: 1),
    inputLabel: 'ASR cần sửa câu',
    confidence: 0.7,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _CapturingStreamingRepository extends DemoConversationRepository {
  StreamingSpeechCapture? capture;

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async {
    this.capture = capture;
    return ConversationResult(
      conversationId: 'corrected-turn',
      sessionId: 'corrected-session',
      context: context,
      vietnameseText: capture.sourceText,
      englishText: 'I have washed my hands.',
      audioUri: null,
      processingMode: 'streaming',
      textSource: 'native_speech',
      audioSource: 'none',
      asrMode: capture.asrMode,
      latency: const ConversationLatency(
        asrMs: 1,
        llmMs: 1,
        ttsMs: 0,
        timeToFirstAudioMs: 0,
      ),
    );
  }
}
