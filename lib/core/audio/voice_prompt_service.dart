import 'audio_turn_coordinator.dart';
import 'coordinated_voice_prompt_service.dart';
import 'main_assistant_audio_prompt_service.dart';
import 'voice_prompt_service_base.dart';
import 'voice_prompt_service_native.dart'
    if (dart.library.js_interop) 'voice_prompt_service_web.dart'
    as platform;
import 'package:http/http.dart' as http;

export 'voice_prompt_service_base.dart';
export 'audio_turn_coordinator.dart' show AudioTurnCoordinator, AudioTurnOwner;

VoicePromptService createVoicePromptService({
  AudioTurnCoordinator? coordinator,
  AudioTurnOwner owner = AudioTurnOwner.legacy,
  http.Client? httpClient,
}) {
  final platformService = platform.createPlatformVoicePromptService();
  final service = MainAssistantAudioPromptService(
    delegate: platformService,
    httpClient: httpClient,
    additionalManifestAssets:
        const bool.fromEnvironment(
          'HOMI_CURRICULUM_AUTHORED_AUDIO',
          defaultValue: true,
        )
        ? const ['assets/data/curriculum_audio.json']
        : const [],
    enabled:
        const bool.fromEnvironment(
          'HOMI_ASSISTANT_AUTHORED_AUDIO',
          defaultValue: true,
        ) &&
        const bool.fromEnvironment(
          'HOMI_MAIN_AUTHORED_AUDIO',
          defaultValue: true,
        ),
  );
  return coordinator == null
      ? service
      : CoordinatedVoicePromptService(
          delegate: service,
          coordinator: coordinator,
          owner: owner,
        );
}
