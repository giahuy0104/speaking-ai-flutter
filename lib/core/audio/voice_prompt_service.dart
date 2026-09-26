import 'audio_turn_coordinator.dart';
import 'catalog/voice_prompt_audio_registry_adapter.dart';
import 'coordinated_voice_prompt_service.dart';
import 'homi_gap66_audio_config.dart';
import 'hfp_audio_control.dart';
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
  HfpAudioControl? selectedOutputRoute,
}) {
  final platformService = platform.createPlatformVoicePromptService();
  final usesPromptRegistry =
      owner == AudioTurnOwner.mainAssistant ||
      owner == AudioTurnOwner.continuousTranslation ||
      owner == AudioTurnOwner.listeningLesson ||
      owner == AudioTurnOwner.vocabulary;
  final VoicePromptService fixedPromptService = usesPromptRegistry
      ? MainAssistantAudioPromptService(
          delegate: platformService,
          httpClient: httpClient,
          enabled:
              homiGap66AudioEnabled &&
              const bool.fromEnvironment(
                'HOMI_ASSISTANT_AUTHORED_AUDIO',
                defaultValue: true,
              ) &&
              const bool.fromEnvironment(
                'HOMI_MAIN_AUTHORED_AUDIO',
                defaultValue: true,
              ),
          preferBundledAudio: true,
          additionalManifestAssets: const [homiGap66ManifestAsset],
          groupEnabled: homiGap66AudioGroups,
        )
      : platformService;
  final VoicePromptService service = usesPromptRegistry
      ? VoicePromptAudioRegistryAdapter(
          delegate: fixedPromptService,
          manifestAssets: [
            'assets/data/assistant_core_audio.json',
            if (owner == AudioTurnOwner.mainAssistant ||
                owner == AudioTurnOwner.listeningLesson)
              'assets/data/listening_common_audio.json',
            if (owner == AudioTurnOwner.listeningLesson) ...const [
              'assets/data/listening_3_5_audio.json',
              'assets/data/listening_6_7_audio.json',
              'assets/data/listening_8_10_audio.json',
              'assets/data/listening_11_12_audio.json',
              'assets/data/listening_13_15_audio.json',
              'assets/data/challenge_3_5_audio.json',
              'assets/data/challenge_6_7_audio.json',
              'assets/data/challenge_8_10_audio.json',
              'assets/data/challenge_11_12_audio.json',
              'assets/data/challenge_13_15_audio.json',
            ],
            if (owner == AudioTurnOwner.vocabulary) ...const [
              'assets/data/vocabulary_common_audio.json',
              'assets/data/vocabulary_built_in_audio.json',
            ],
          ],
          httpClient: httpClient,
        )
      : fixedPromptService;
  return coordinator == null
      ? service
      : CoordinatedVoicePromptService(
          delegate: service,
          coordinator: coordinator,
          owner: owner,
          selectedOutputRoute: selectedOutputRoute,
        );
}
