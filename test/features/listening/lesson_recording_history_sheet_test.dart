import 'package:ai_speaking_flutter_app/core/audio/audio_gain.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/lesson_recording_history_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_recording_history_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('history child replay uses the same gain as the lesson', (
    tester,
  ) async {
    final media = _RecordingMediaService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LessonRecordingHistorySheet(mediaService: media)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nghe bản ghi'));
    await tester.pumpAndSettle();

    expect(media.lastUri, Uri.file('/recordings/child.wav'));
    expect(media.lastGainDb, lessonRecordingPlaybackGainDb);
    await tester.pumpWidget(const SizedBox());
  });
}

class _RecordingMediaService extends LessonMediaService {
  _RecordingMediaService() : super(historyStore: _MemoryHistoryStore());

  Uri? lastUri;
  double? lastGainDb;

  @override
  Future<void> play(
    Uri uri, {
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = androidSpeechBoostDb,
    bool fixedPlaybackGain = false,
  }) async {
    lastUri = uri;
    lastGainDb = playbackGainDb;
  }

  @override
  Future<void> stopPlayback() async {}
}

class _MemoryHistoryStore extends LessonRecordingHistoryStore {
  @override
  Future<List<LessonRecordingHistoryEntry>> readAll() async => [
    LessonRecordingHistoryEntry(
      id: 'child-recording',
      lessonId: 'numbers',
      lessonTitle: 'Numbers',
      sentenceId: 'one',
      sentenceNumber: 1,
      english: 'One.',
      vietnamese: 'Một.',
      filePath: '/recordings/child.wav',
      duration: const Duration(seconds: 2),
      createdAt: DateTime(2026, 9, 18),
    ),
  ];
}
