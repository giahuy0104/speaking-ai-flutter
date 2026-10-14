// Audit only. Native playback is observed through a mock channel; no real progress is written.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = ListeningContentCatalog.fromJson(jsonDecode(File('assets/data/listening_lessons.json').readAsStringSync()) as Map<String, dynamic>);
  final assetByHash = <String, List<String>>{};
  for (final file in Directory('assets/data').listSync().whereType<File>().where((f) => f.path.endsWith('_audio.json'))) {
    final manifest = jsonDecode(file.readAsStringSync()) as Map;
    for (final p in (manifest['prompts'] as List? ?? [])) {
      if (p['sha256'] != null && p['asset'] != null) {
        assetByHash.putIfAbsent(p['sha256'] as String, () => []).add(p['asset'] as String);
      }
    }
  }
  List<Map<String, Object?>> events = [];
  void installMock() {
    const channel = MethodChannel('ailingo_voice_prompt');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments;
      if (call.method == 'playAuthoredAudioAndWait') {
        final hash = sha256.convert((args as Map)['bytes'] as Uint8List).toString();
        events.add({'kind': 'mp3', 'assets': assetByHash[hash], 'sha256': hash});
      } else if (call.method == 'speakAndWait' || call.method == 'speak') {
        events.add({'kind': 'tts', 'text': (args as Map)['text'], 'locale': args['locale']});
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  testWidgets('observe actual fresh intro widget and factory for every lesson', (tester) async {
    installMock();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rows = <Map<String, Object?>>[];
    final platform = defaultTargetPlatform.name;
    for (final group in catalog.groups) {
      final cards = listeningCatalogs.singleWhere((g) => g.startAge == group.startAge);
      for (final topic in group.topics) {
        for (final lesson in topic.lessons) {
          events = [];
          final store = _ProbeStore();
          final service = createVoicePromptService(owner: AudioTurnOwner.listeningLesson);
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(),
            home: LessonIntroScreen(
              language: DisplayLanguage.vietnamese,
              startAge: group.startAge, endAge: group.endAge,
              topic: cards.topics[topic.number - 1],
              topicContent: topic, contentGroup: group, lesson: lesson,
              progressStore: store, mediaService: _ProbeMedia(() => events),
              voicePromptService: service, autoAdvance: false,
            ),
          ));
          for (var step = 0; step < 150 && !store.finished; step++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
            await tester.pump(const Duration(milliseconds: 16));
          }
          rows.add({
            'platform': platform, 'ageGroup': '${group.startAge}-${group.endAge}',
            'topicNumber': topic.number, 'topicTitle': topic.titleVi,
            'lessonId': lesson.id, 'lessonNumber': lesson.number, 'lessonTitle': lesson.titleEn,
            'hookUri': lesson.combinedHookAudioUri?.toString(),
            'finished': store.finished, 'events': List.of(events),
          });
          File('output/intro-deep-audit/fresh-$platform.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
          expect(store.finished, isTrue, reason: '$platform ${lesson.id}: intro did not finish');
          expect(events, isNotEmpty, reason: '$platform ${lesson.id}');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await service.dispose();
        }
      }
    }
    expect(rows, hasLength(109));
  }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}), timeout: const Timeout(Duration(minutes: 10)));

  test('observe all resume/relearn and remaining-star prompt paths through real factory', () async {
    installMock();
    final service = createVoicePromptService(owner: AudioTurnOwner.listeningLesson);
    addTearDown(service.dispose);
    final rows = <Map<String, Object?>>[];
    Future<void> probe(String kind, String key, String text, {String? lessonId}) async {
      events = [];
      await (service as KeyedSelectedMediaOutputVoicePromptService).speakAndWaitOnSelectedMediaOutputWithAudioKey(key, text);
      rows.add({'kind': kind, 'lessonId': lessonId, 'key': key, 'text': text, 'events': List.of(events)});
    }
    for (final group in catalog.groups) {
      for (final topic in group.topics) {
        for (final lesson in topic.lessons) {
          await probe('resume', ListeningAudioKeys.lessonResume(lesson.id), 'Mình học tiếp bài ${lesson.titleEn.trim()} nhé.', lessonId: lesson.id);
          await probe('relearn', ListeningAudioKeys.lessonRelearn(lesson.id), 'Mình học lại bài ${lesson.titleEn.trim()} nhé.', lessonId: lesson.id);
          if (lesson.songTitle != null) {
            await probe('song_resume', ListeningAudioKeys.lessonSongResume(lesson.id), 'Mình nghe lại bài hát ${lesson.songTitle} nhé.', lessonId: lesson.id);
          }
        }
      }
    }
    final maxCore = catalog.groups.expand((g) => g.topics).expand((t) => t.lessons).map((l) => l.sentences.length).reduce((a, b) => a > b ? a : b);
    for (var count = 1; count <= maxCore; count++) {
      for (final young in [true, false]) {
        await probe('remaining_stars', ListeningAudioKeys.lessonRemainingStars(count, childFriendly: young), 'Bài này bạn còn $count Ngôi sao chưa chinh phục.${young ? ' Mình cùng thử nhé!' : ''}');
      }
    }
    await probe('challenge_resume', ListeningAudioKeys.challengeResume, 'Mình tiếp tục câu thử thách nhé.');
    for (var n = 1; n <= 10; n++) {
      await probe('topic_resume', ListeningAudioKeys.topicResume(n), 'Mình học tiếp Chủ đề $n nhé.');
    }
    File('output/intro-deep-audit/resume-relearn-runtime.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    expect(rows, isNotEmpty);
  });
}

class _ProbeStore extends ListeningProgressStore {
  bool finished = false;
  @override
  Future<int> readLesson(String id) async => 0;
  @override
  Future<int> readCurrentSentence(String id) async => 0;
  @override
  Future<bool> hasOpenedLearningGuide() async => false;
  @override
  Future<bool> hasStartedLessonCore(String id) async => false;
  @override
  Future<ListeningResumeStage> readResumeStage(String id) async => ListeningResumeStage.core;
  @override
  Future<void> markLearningGuideOpened() async { finished = true; }
}

class _ProbeMedia extends LessonMediaService {
  _ProbeMedia(this.events);
  final List<Map<String, Object?>> Function() events;
  @override
  Future<void> prepareSelectedLessonOutput() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<void> playToCompletion(Uri uri, {Duration timeout = const Duration(seconds: 45), LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice, double playbackGainDb = 8, bool fixedPlaybackGain = false}) async {
    events().add({'kind': 'media', 'uri': uri.toString()});
  }
}
