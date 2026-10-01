import 'package:ai_speaking_flutter_app/core/audio/audio_turn_coordinator.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/voice_prompt_audio_registry_adapter.dart';
import 'package:ai_speaking_flutter_app/core/audio/coordinated_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_base.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final source in NativeSpeechAudioSource.values) {
    test(
      'iOS ${source.name} reaches beginMainTurn before prompt and capture',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final channel = MethodChannel('test_main_route_${source.name}');
        final calls = <MethodCall>[];
        final timeline = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          timeline.add(call.method);
          return call.method == 'beginMainTurn' ? 'ios-${source.name}' : null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final coordinator = AudioTurnCoordinator();
        final prompt = _wrap(
          MethodChannelVoicePromptService(channel: channel),
          coordinator,
        );
        final input = _SpeechInput(timeline);
        final controller = VoiceNavigationController(
          speechInput: input,
          voicePromptService: prompt,
          mainSpeechAudioSource: () => source,
          wakeWordEnabled: false,
        );
        addTearDown(() async {
          controller.dispose();
          await prompt.dispose();
          await coordinator.dispose();
        });

        expect(await controller.activateFromMainButton(), isTrue);
        expect(calls.first.method, 'beginMainTurn');
        expect(calls.first.arguments, {'audioSource': source.channelValue});
        expect(
          timeline.indexOf('beginMainTurn'),
          lessThan(timeline.indexOf('speakAndWait')),
        );
        expect(
          timeline.indexOf('beginMainTurn'),
          lessThan(timeline.indexOf('speech.start')),
        );
        expect(input.selectedSources, [source]);
        expect(controller.isListening, isTrue);
        await controller.pause();
        final end = calls.firstWhere((call) => call.method == 'endMainTurn');
        expect((end.arguments as Map)['turnId'], 'ios-${source.name}');
      },
    );
  }

  test('routed wrapper stack retains a legacy MAIN delegate', () async {
    final legacy = _LegacyMainService();
    final coordinator = AudioTurnCoordinator();
    final prompt = _wrap(legacy, coordinator);
    addTearDown(() async {
      await prompt.dispose();
      await coordinator.dispose();
    });
    expect(
      await prompt.beginMainTurnWithAudioSource('builtInMic'),
      'legacy-turn',
    );
    expect(legacy.beginCalls, 1);
    await prompt.endMainTurn('done', turnId: 'legacy-turn');
    expect(legacy.endedIds, ['legacy-turn']);
  });

  test(
    'legacy method-channel beginMainTurn retains its original payload',
    () async {
      const channel = MethodChannel('test_legacy_main_route');
      MethodCall? received;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return 'legacy-native';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const service = MethodChannelVoicePromptService(channel: channel);
      expect(await service.beginMainTurn(), 'legacy-native');
      expect(received?.method, 'beginMainTurn');
      expect(received?.arguments, isNull);
    },
  );
}

CoordinatedVoicePromptService _wrap(
  VoicePromptService delegate,
  AudioTurnCoordinator coordinator,
) => CoordinatedVoicePromptService(
  delegate: VoicePromptAudioRegistryAdapter(
    delegate: MainAssistantAudioPromptService(
      delegate: delegate,
      enabled: false,
    ),
    manifestAssets: const [],
  ),
  coordinator: coordinator,
  owner: AudioTurnOwner.mainAssistant,
);

class _SpeechInput
    implements StreamingSpeechInput, NativeSpeechAudioSourceControl {
  _SpeechInput(this.timeline);
  final List<String> timeline;
  final selectedSources = <NativeSpeechAudioSource>[];
  @override
  String get label => 'native test mic';
  @override
  Stream<double> get amplitudeDbfs => const Stream.empty();
  @override
  Stream<void> get completed => const Stream.empty();
  @override
  Stream<String> get partialText => const Stream.empty();
  @override
  Future<bool> checkAvailability() async => true;
  @override
  void useNativeSpeechAudioSourceOnce(NativeSpeechAudioSource source) {
    selectedSources.add(source);
  }

  @override
  Future<void> start() async => timeline.add('speech.start');
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: '',
    duration: Duration.zero,
    inputLabel: 'native test mic',
    confidence: null,
    firstResultMs: null,
    finalAfterStopMs: 0,
  );
}

class _LegacyMainService
    implements VoicePromptService, MainTurnVoicePromptService {
  int beginCalls = 0;
  final endedIds = <String?>[];
  @override
  Future<String?> beginMainTurn() async {
    beginCalls++;
    return 'legacy-turn';
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    endedIds.add(turnId);
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
