import '../../listening/application/lesson_guide_audio_library.dart';
import '../../listening/application/lesson_media_service.dart';
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
  }) : _mediaService = mediaService,
       _audioLibrary = audioLibrary ?? LessonGuideAudioLibrary();

  final LessonMediaService _mediaService;
  final LessonGuideAudioLibrary _audioLibrary;
  int _generation = 0;

  @override
  void cancelPending() => _generation++;

  @override
  Future<bool> playPromptIfAvailable(String text) async {
    final generation = _generation;
    final prompt = VocabularyFlowV3.fixedPromptForText(text);
    if (prompt == null) return false;
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
