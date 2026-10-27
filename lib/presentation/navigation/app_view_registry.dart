import 'package:flutter/material.dart';

import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/lesson_challenge_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/lesson_intro_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/lesson_practice_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/lesson_review_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/song_karaoke_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/song_stage_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/topic_lessons_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/topic_listening_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/vocabulary_practice_arguments.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/song_karaoke_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/v4_song_stage_screen.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/history_sheet.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_practice_screen.dart';

import '../../core/navigation/app_router.dart';
import '../../core/navigation/app_route_names.dart';
import 'view_bindings.dart';

/// Central route -> screen registration. No service is created or disposed here.
AppRouter createAppRouter() => AppRouter({
  AppRouteNames.topicCatalog:
      AppRouteEntry<TopicListeningArguments, TopicListeningBindings>(
        builder: (context, arguments, bindings) => TopicListeningScreen(
          language: arguments.language,
          childAge: arguments.childAge,
          controller: bindings.controller,
          ensureDeviceConnected: bindings.ensureDeviceConnected,
          onVoiceNavigationPause: bindings.onVoiceNavigationPause,
          onVoiceNavigationResume: bindings.onVoiceNavigationResume,
          initialVoiceTarget: arguments.initialVoiceTarget,
          initialVoiceActivationGate: bindings.initialVoiceActivationGate,
          onTopicSelected: bindings.onTopicSelected,
          onLessonSelectionRequested: bindings.onLessonSelectionRequested,
          onTopicSelectionRequested: bindings.onTopicSelectionRequested,
          iosTopicRecognitionFailureRevision:
              bindings.iosTopicRecognitionFailureRevision,
          onChildAgeChanged: bindings.onChildAgeChanged,
          onRequestParentAccess: bindings.onRequestParentAccess,
          onCommunicationRequested: bindings.onCommunicationRequested,
          contentFuture: bindings.contentFuture,
          progressStore: bindings.progressStore,
          mediaService: bindings.mediaService,
          voicePromptService: bindings.voicePromptService,
          key: bindings.key,
        ),
      ),
  AppRouteNames.topicLessons:
      AppRouteEntry<TopicLessonsArguments, TopicLessonListBindings>(
        builder: (context, arguments, bindings) => TopicLessonListScreen(
          language: arguments.language,
          startAge: arguments.startAge,
          endAge: arguments.endAge,
          topic: arguments.topic,
          content: arguments.content,
          contentGroup: arguments.contentGroup,
          levelContent: arguments.levelContent,
          controller: bindings.controller,
          ensureDeviceConnected: bindings.ensureDeviceConnected,
          onVoiceNavigationPause: bindings.onVoiceNavigationPause,
          onVoiceNavigationResume: bindings.onVoiceNavigationResume,
          progressStore: bindings.progressStore,
          mediaService: bindings.mediaService,
          voicePromptService: bindings.voicePromptService,
          initialLessonNumber: arguments.initialLessonNumber,
          initialLessonLeadPrompt: bindings.initialLessonLeadPrompt,
          initialLessonMainReply: bindings.initialLessonMainReply,
          coverUntilInitialLessonReturns:
              arguments.coverUntilInitialLessonReturns,
          relearnInitialLesson: arguments.relearnInitialLesson,
          relearnTopicSequence: arguments.relearnTopicSequence,
          songsOnly: arguments.songsOnly,
          onTopicCompleted: bindings.onTopicCompleted,
          onCommunicationRequested: bindings.onCommunicationRequested,
          key: bindings.key,
        ),
      ),
  AppRouteNames.lessonIntro:
      AppRouteEntry<LessonIntroArguments, LessonIntroBindings>(
        builder: (context, arguments, bindings) => LessonIntroScreen(
          language: arguments.language,
          startAge: arguments.startAge,
          endAge: arguments.endAge,
          topic: arguments.topic,
          lesson: arguments.lesson,
          progressStore: bindings.progressStore,
          mediaService: bindings.mediaService,
          controller: bindings.controller,
          topicContent: arguments.topicContent,
          contentGroup: arguments.contentGroup,
          levelContent: arguments.levelContent,
          guideAudioLibrary: bindings.guideAudioLibrary,
          voicePromptService: bindings.voicePromptService,
          leadPrompt: bindings.leadPrompt,
          autoAdvance: arguments.autoAdvance,
          relearnFromBeginning: arguments.relearnFromBeginning,
          relearnTopicSequence: arguments.relearnTopicSequence,
          onTopicCompleted: bindings.onTopicCompleted,
          onCommunicationRequested: bindings.onCommunicationRequested,
          key: bindings.key,
        ),
      ),
  AppRouteNames.lessonPractice:
      AppRouteEntry<LessonPracticeArguments, LessonPracticeBindings>(
        builder: (context, arguments, bindings) => LessonPracticeScreen(
          language: arguments.language,
          startAge: arguments.startAge,
          endAge: arguments.endAge,
          topic: arguments.topic,
          lesson: arguments.lesson,
          progressStore: bindings.progressStore,
          mediaService: bindings.mediaService,
          vocabularyStore: bindings.vocabularyStore,
          controller: bindings.controller,
          guideAudioLibrary: bindings.guideAudioLibrary,
          attemptEvaluator: bindings.attemptEvaluator,
          completionChoiceRecognizer: bindings.completionChoiceRecognizer,
          voicePromptService: bindings.voicePromptService,
          topicContent: arguments.topicContent,
          contentGroup: arguments.contentGroup,
          levelContent: arguments.levelContent,
          initialResumeStage: arguments.initialResumeStage,
          isRelearn: arguments.isRelearn,
          relearnTopicSequence: arguments.relearnTopicSequence,
          onTopicCompleted: bindings.onTopicCompleted,
          onCommunicationRequested: bindings.onCommunicationRequested,
          key: bindings.key,
        ),
      ),
  AppRouteNames.lessonReview:
      AppRouteEntry<LessonReviewArguments, LessonReviewBindings>(
        builder: (context, arguments, bindings) => LessonReviewScreen(
          language: arguments.language,
          lesson: arguments.lesson,
          mediaService: bindings.mediaService,
          unrecordedSentenceIndexes: arguments.unrecordedSentenceIndexes,
          learnNowBuilder: bindings.learnNowBuilder,
          mode: arguments.mode,
          hasNextLesson: arguments.hasNextLesson,
          voicePromptService: bindings.voicePromptService,
          key: bindings.key,
        ),
      ),
  AppRouteNames.lessonChallenge:
      AppRouteEntry<LessonChallengeArguments, LessonChallengeBindings>(
        builder: (context, arguments, bindings) => LessonChallengeScreen(
          language: arguments.language,
          startAge: arguments.startAge,
          lesson: arguments.lesson,
          challenges: arguments.challenges,
          mediaService: bindings.mediaService,
          startPaused: bindings.startPaused,
          attemptEvaluator: bindings.attemptEvaluator,
          voicePromptService: bindings.voicePromptService,
          iosSpeechInput: bindings.iosSpeechInput,
          onStarEarned: bindings.onStarEarned,
          onStarEarnedWithResult: bindings.onStarEarnedWithResult,
          onStarEarnedWithAudioResult: bindings.onStarEarnedWithAudioResult,
          onNeedsPractice: bindings.onNeedsPractice,
          onChallengeResolved: bindings.onChallengeResolved,
          key: bindings.key,
        ),
      ),
  AppRouteNames.songKaraoke:
      AppRouteEntry<SongKaraokeArguments, SongKaraokeBindings>(
        navigatorName: AppRouteNames.lessonPractice,
        builder: (context, arguments, bindings) => SongKaraokeScreen(
          language: arguments.language,
          lesson: arguments.lesson,
          mediaService: bindings.mediaService,
          practiceBuilder: bindings.practiceBuilder,
          topicTitle: arguments.topicTitle,
          autoPlayDelay: bindings.autoPlayDelay,
          backgroundAsset: bindings.backgroundAsset,
          key: bindings.key,
        ),
      ),
  AppRouteNames.songStage:
      AppRouteEntry<SongStageArguments, V4SongStageBindings>(
        builder: (context, arguments, bindings) => V4SongStageScreen(
          language: arguments.language,
          songTitle: arguments.songTitle,
          mediaService: bindings.mediaService,
          songAudioId: arguments.songAudioId,
          songAudioUri: arguments.songAudioUri,
          voicePromptService: bindings.voicePromptService,
          key: bindings.key,
        ),
      ),
  AppRouteNames.vocabularyPractice:
      AppRouteEntry<VocabularyPracticeArguments, VocabularyPracticeBindings>(
        builder: (context, arguments, bindings) => VocabularyPracticeScreen(
          language: arguments.language,
          childAge: arguments.childAge,
          session: arguments.session,
          store: bindings.store,
          sessionStore: bindings.sessionStore,
          mediaService: bindings.mediaService,
          audioDependencies: bindings.audioDependencies,
          attemptEvaluator: bindings.attemptEvaluator,
          recordingEndpointDetector: bindings.recordingEndpointDetector,
          voicePromptService: bindings.voicePromptService,
          vocabularyAudioService: bindings.vocabularyAudioService,
          fixedPromptAudioService: bindings.fixedPromptAudioService,
          samplePause: bindings.samplePause,
          autoStart: bindings.autoStart,
          announceIntro: arguments.announceIntro,
          announceResume: arguments.announceResume,
          onRequestVoiceChoice: bindings.onRequestVoiceChoice,
          onPrepareContinue: bindings.onPrepareContinue,
          key: bindings.key,
        ),
      ),
  AppRouteNames.settings: AppRouteEntry<Null, SettingsBindings>(
    presentation: AppRoutePresentation.page,
    builder: (context, arguments, bindings) => Scaffold(
      key: const Key('settings-page'),
      body: SizedBox.expand(
        child: SettingsSheet(
          controller: bindings.controller,
          themeMode: bindings.themeMode,
          connectionCoordinator: bindings.connectionCoordinator,
          onThemeModeChanged: bindings.onThemeModeChanged,
          onChildAgeChanged: bindings.onChildAgeChanged,
          onStartTutorial: bindings.onStartTutorial,
          config: bindings.config,
          privacyConsentGranted: bindings.privacyConsentGranted,
          voiceAccessEnabled: bindings.voiceAccessEnabled,
          onRequestVoiceAccess: bindings.onRequestVoiceAccess,
          onManagePrivacyConsent: bindings.onManagePrivacyConsent,
          onRevokePrivacyConsent: bindings.onRevokePrivacyConsent,
          stopMediaWhenBackgrounded: bindings.stopMediaWhenBackgrounded,
          onStopMediaWhenBackgroundedChanged:
              bindings.onStopMediaWhenBackgroundedChanged,
          key: bindings.key,
        ),
      ),
    ),
  ),
  AppRouteNames.history: AppRouteEntry<Null, HistoryBindings>(
    presentation: AppRoutePresentation.bottomSheet,
    builder: (context, arguments, bindings) =>
        HistorySheet(controller: bindings.controller, key: bindings.key),
  ),
  AppRouteNames.learningContinuation:
      AppRouteEntry<Null, LearningContinuationBindings>(
        unnamed: true,
        builder: (context, _, bindings) => bindings.builder(context),
      ),
});
