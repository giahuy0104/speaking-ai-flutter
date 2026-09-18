// Retain this tracked diagnostic artifact's established path.
// ignore_for_file: file_names

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Diagnostic only: no application code or existing test expectations changed.
void main() {
  // This is a Flutter test invoked explicitly outside the conventional test/ folder.
  // ignore: invalid_use_of_visible_for_testing_member
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  for (final stars in [false, true]) {
    testWidgets(
      '${stars ? 'Stars' : 'Parent'} waits after silent MAIN at block end',
      (tester) async {
        final registry = ActiveLearningModuleRegistry();
        addTearDown(registry.dispose);
        final voice = _Voice();
        final store = _Store([
          for (var index = 0; index < 6; index++)
            VocabularyEntry(
              id: 'entry-$index',
              word: 'Sentence ${index + 1}',
              meaning: 'Câu ${index + 1}',
              addedAt: DateTime(2026, 9, 15).add(Duration(minutes: index)),
              earnedAt: stars
                  ? DateTime(2026, 9, 15).add(Duration(minutes: index))
                  : null,
              collection: stars
                  ? VocabularyCollection.star
                  : VocabularyCollection.saved,
              source: stars
                  ? VocabularySource.topicCore
                  : VocabularySource.parent,
              status: VocabularyLearningStatus.learnedWell,
              parentState: stars ? null : ParentVocabularyState.unlocked,
              correctAudioPath: stars ? 'C:\\audio\\entry-$index.wav' : null,
            ),
        ]);
        var choiceRequests = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: ActiveLearningModuleScope(
              registry: registry,
              child: DisplayLanguageScope(
                language: DisplayLanguage.vietnamese,
                child: VocabularyHomeScreen(
                  isReady: true,
                  isActive: true,
                  store: store,
                  voicePromptService: voice,
                  mediaService: _Media(),
                  onRequestVoiceChoice:
                      ({noSpeechRetryPrompt, noSpeechExitPrompt}) async {
                        choiceRequests++;
                        await registry.pauseForMainAssistant();
                      },
                  onReturnToConversation: () {},
                  onHistory: () {},
                  onSettings: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final branch = stars ? 'stars' : 'family';
        await tester.tap(find.byKey(Key('vocabulary-$branch-card')));
        await tester.pumpAndSettle();
        final play = find.byKey(ValueKey<String>('vocabulary-$branch-action'));
        await tester.ensureVisible(play);
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(choiceRequests, 1);
        expect(voice.spoken, isNot(contains('Sentence 6')));
        // Same command emitted by AppFlowCoordinator.resumeAfterMainAssistant.
        // No explicit "học tiếp" or another child choice has been provided.
        await registry.execute(ActiveLearningCommand.resume);
        await tester.pumpAndSettle();
        expect(
          voice.spoken,
          isNot(contains('Sentence 6')),
          reason: 'Silent MAIN completion must preserve waiting-for-choice.',
        );
      },
    );
  }
}

class _Store extends VocabularyStore {
  _Store(this.entries);
  List<VocabularyEntry> entries;
  @override
  Future<List<VocabularyEntry>> read() async => entries;
  @override
  Future<void> write(List<VocabularyEntry> value) async =>
      entries = List.of(value);
}

class _Voice implements VoicePromptService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async =>
      spoken.add(text);
  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Media extends LessonMediaService {
  @override
  Future<void> prepareSelectedLessonOutput() async {}
  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
    double playbackGainDb = 8.0,
  }) async {}
  @override
  Future<void> stopPlayback() async {}
}
