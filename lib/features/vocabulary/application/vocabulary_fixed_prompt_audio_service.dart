import '../../listening/application/lesson_guide_audio_library.dart';
import '../../listening/application/lesson_media_service.dart';
import '../../../core/audio/voice_prompt_service_base.dart';
import '../domain/vocabulary_audio_keys.dart';
import '../domain/vocabulary_flow_v3.dart';

abstract interface class VocabularyFixedPromptAudioService {
  Future<bool> playPromptIfAvailable(String text);

  Future<bool> playAudioCodeIfAvailable(String audioCode);
}

abstract interface class CancellableVocabularyFixedPromptAudioService {
  void cancelPending();
}

class AssetFirstVocabularyFixedPromptAudioService
    implements
        VocabularyFixedPromptAudioService,
        CancellableVocabularyFixedPromptAudioService {
  AssetFirstVocabularyFixedPromptAudioService({
    required LessonMediaService mediaService,
    LessonGuideAudioLibrary? audioLibrary,
    VoicePromptService? registryService,
  }) : _mediaService = mediaService,
       _audioLibrary = audioLibrary ?? LessonGuideAudioLibrary(),
       _registryService = registryService;

  final LessonMediaService _mediaService;
  final LessonGuideAudioLibrary _audioLibrary;
  final VoicePromptService? _registryService;
  int _generation = 0;

  @override
  void cancelPending() => _generation++;

  @override
  Future<bool> playPromptIfAvailable(String text) async {
    final generation = _generation;
    final prompt = VocabularyFlowV3.fixedPromptForText(text);
    if (prompt == null) return false;
    final registry = _registryService;
    final audioKey = VocabularyAudioKeys.fixedPrompt(prompt);
    if (audioKey != null && registry is KeyedVoicePromptService) {
      await (registry as KeyedVoicePromptService).speakAndWaitWithAudioKey(
        audioKey,
        text,
      );
      return true;
    }
    for (final audioCode in prompt.lookupCodes) {
      if (await playAudioCodeIfAvailable(audioCode)) return true;
      if (generation != _generation) return true;
    }
    return false;
  }

  @override
  Future<bool> playAudioCodeIfAvailable(String audioCode) async {
    final generation = _generation;
    try {
      final uri = await _audioLibrary.uriForAudioCode(audioCode);
      if (generation != _generation) return true;
      if (uri == null) return false;
      await _mediaService.prepareSelectedLessonOutput();
      if (generation != _generation) return true;
      await _mediaService.playToCompletion(uri);
      return true;
    } catch (_) {
      if (generation != _generation) return true;
      return false;
    }
  }
}
