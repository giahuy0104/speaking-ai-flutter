import '../../listening/application/lesson_guide_audio_library.dart';
import '../../listening/application/lesson_media_service.dart';
import '../domain/vocabulary_flow_v3.dart';

abstract interface class VocabularyFixedPromptAudioService {
  Future<bool> playPromptIfAvailable(String text);

  Future<bool> playAudioCodeIfAvailable(String audioCode);
}

class AssetFirstVocabularyFixedPromptAudioService
    implements VocabularyFixedPromptAudioService {
  AssetFirstVocabularyFixedPromptAudioService({
    required LessonMediaService mediaService,
    LessonGuideAudioLibrary? audioLibrary,
  }) : _mediaService = mediaService,
       _audioLibrary = audioLibrary ?? LessonGuideAudioLibrary();

  final LessonMediaService _mediaService;
  final LessonGuideAudioLibrary _audioLibrary;

  @override
  Future<bool> playPromptIfAvailable(String text) async {
    final prompt = VocabularyFlowV3.fixedPromptForText(text);
    if (prompt == null) return false;
    for (final audioCode in prompt.lookupCodes) {
      if (await playAudioCodeIfAvailable(audioCode)) return true;
    }
    return false;
  }

  @override
  Future<bool> playAudioCodeIfAvailable(String audioCode) async {
    try {
      final uri = await _audioLibrary.uriForAudioCode(audioCode);
      if (uri == null) return false;
      await _mediaService.prepareSelectedLessonOutput();
      await _mediaService.playToCompletion(uri);
      return true;
    } catch (_) {
      return false;
    }
  }
}
