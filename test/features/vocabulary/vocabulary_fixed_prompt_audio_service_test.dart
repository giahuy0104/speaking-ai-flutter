import 'dart:async';

import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_fixed_prompt_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancel during H20 route preparation prevents late fixed prompt playback',
    () async {
      final media = _RecordingMediaService()..preparation = Completer<void>();
      final service = AssetFirstVocabularyFixedPromptAudioService(
        mediaService: media,
        audioLibrary: LessonGuideAudioLibrary(
          assetPaths: const <String>[
            'assets/audio/VOCABULARY/STAR_BLOCK_END_01.mp3',
          ],
        ),
      );
      final pending = service.playPromptIfAvailable(
        VocabularyFlowV3.reviewGroupCompletion,
      );
      await Future<void>.delayed(Duration.zero);
      expect(media.prepared, 1);
      service.cancelPending();
      media.preparation!.complete();
      expect(
        await pending,
        isTrue,
      ); // Cancelled is handled, not a TTS fallback.
      expect(media.played, isEmpty);
    },
  );
  test('resolves a shared FINAL state ID alias before TTS fallback', () async {
    final media = _RecordingMediaService();
    final service = AssetFirstVocabularyFixedPromptAudioService(
      mediaService: media,
      audioLibrary: LessonGuideAudioLibrary(
        assetPaths: const <String>[
          'assets/audio/VOCABULARY/STAR_BLOCK_END_01.mp3',
        ],
      ),
    );

    final played = await service.playPromptIfAvailable(
      VocabularyFlowV3.reviewGroupCompletion,
    );

    expect(played, isTrue);
    expect(media.prepared, 1);
    expect(media.played, <Uri>[
      Uri(
        scheme: 'asset',
        path: '/assets/audio/VOCABULARY/STAR_BLOCK_END_01.mp3',
      ),
    ]);
  });

  test('reports missing authored audio so the caller can use TTS', () async {
    final media = _RecordingMediaService();
    final service = AssetFirstVocabularyFixedPromptAudioService(
      mediaService: media,
      audioLibrary: LessonGuideAudioLibrary(assetPaths: const <String>[]),
    );

    expect(
      await service.playPromptIfAvailable(VocabularyFlowV3.todayIntro),
      isFalse,
    );
    expect(media.played, isEmpty);
  });
}

class _RecordingMediaService extends LessonMediaService {
  int prepared = 0;
  Completer<void>? preparation;
  final List<Uri> played = <Uri>[];

  @override
  Future<void> prepareSelectedLessonOutput() async {
    prepared += 1;
    await preparation?.future;
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 30),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
    bool fixedPlaybackGain = false,
  }) async {
    played.add(uri);
  }
}
