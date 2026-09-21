import 'audio_turn_coordinator.dart';
import 'coordinated_voice_prompt_service.dart';
import 'homi_gap19_audio_config.dart';
import 'homi_gap66_audio_config.dart';
import 'hfp_audio_control.dart';
import 'main_assistant_audio_prompt_service.dart';
import 'voice_prompt_service_base.dart';
import 'voice_prompt_service_native.dart'
    if (dart.library.js_interop) 'voice_prompt_service_web.dart'
    as platform;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

export 'voice_prompt_service_base.dart';
export 'audio_turn_coordinator.dart' show AudioTurnCoordinator, AudioTurnOwner;

VoicePromptService createVoicePromptService({
  AudioTurnCoordinator? coordinator,
  AudioTurnOwner owner = AudioTurnOwner.legacy,
  http.Client? httpClient,
  HfpAudioControl? selectedOutputRoute,
}) {
  final platformService = platform.createPlatformVoicePromptService();
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final service = MainAssistantAudioPromptService(
    delegate: platformService,
    httpClient: httpClient,
    // Fixed Android menus are bundled so selection never waits on the CDN.
    // Unbundled curriculum gets a short first-use attempt, then native TTS;
    // verified late downloads warm subsequent turns without replaying them.
    preferBundledAudio: isAndroid,
    remoteAudioLoadTimeout: isAndroid
        ? const Duration(milliseconds: 350)
        : const Duration(seconds: 8),
    cacheLateRemoteAudio: isAndroid,
    groupEnabled: const <String, bool>{
      ...homiGap66AudioGroups,
      MainAssistantAudioPromptService.mainNavigationGroup: bool.fromEnvironment(
        'HOMI_ASSISTANT_AUDIO_MAIN_NAVIGATION',
        defaultValue: true,
      ),
      MainAssistantAudioPromptService.translationControlsGroup:
          bool.fromEnvironment(
            'HOMI_ASSISTANT_AUDIO_TRANSLATION_CONTROLS',
            defaultValue: true,
          ),
      MainAssistantAudioPromptService.challengeCueGroup: bool.fromEnvironment(
        'HOMI_ASSISTANT_AUDIO_CHALLENGE_CUES',
        defaultValue: true,
      ),
      MainAssistantAudioPromptService.conversationRecoveryGroup:
          bool.fromEnvironment(
            'HOMI_ASSISTANT_AUDIO_CONVERSATION_RECOVERY',
            defaultValue: true,
          ),
    },
    additionalManifestAssets: const [
      if (bool.fromEnvironment(
        'HOMI_CURRICULUM_AUTHORED_AUDIO',
        defaultValue: true,
      ))
        'assets/data/curriculum_audio.json',
      if (homiGap66AudioEnabled) homiGap66ManifestAsset,
      if (homiGap19AudioEnabled) homiGap19ManifestAsset,
    ],
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
          selectedOutputRoute: selectedOutputRoute,
        );
}
