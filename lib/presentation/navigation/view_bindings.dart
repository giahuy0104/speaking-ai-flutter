import 'dart:async';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/learning_audio_dependencies.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/device_connection_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_settings_port.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_completion_choice_recognizer.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_endpoint_detector.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/song_karaoke_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_fixed_prompt_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Existing live dependencies for TopicListeningScreen, supplied lazily by its owner.
class TopicListeningBindings {
  const TopicListeningBindings({
    this.controller,
    this.ensureDeviceConnected,
    this.onMainPressed,
    this.onVocabularyRequested,
    this.onVoiceNavigationPause,
    this.onVoiceNavigationResume,
    this.onTopicSelected,
    this.onLessonSelectionRequested,
    this.onTopicSelectionRequested,
    this.iosTopicRecognitionFailureRevision,
    this.onChildAgeChanged,
    this.onRequestParentAccess,
    this.onCommunicationRequested,
    this.contentFuture,
    this.progressStore = const ListeningProgressStore(),
    this.mediaService,
    this.voicePromptService,
    this.key,
  });

  final LearningAudioDependencies? controller;
  final Future<bool> Function()? ensureDeviceConnected;
  final Future<void> Function()? onMainPressed;
  final VoidCallback? onVocabularyRequested;
  final Future<void> Function()? onVoiceNavigationPause;
  final VoidCallback? onVoiceNavigationResume;
  final ValueChanged<int>? onTopicSelected;
  final TopicLessonSelectionPrompt? onLessonSelectionRequested;
  final TopicSelectionPrompt? onTopicSelectionRequested;
  final ValueListenable<int>? iosTopicRecognitionFailureRevision;
  final ValueChanged<int>? onChildAgeChanged;
  final Future<bool> Function()? onRequestParentAccess;
  final VoidCallback? onCommunicationRequested;
  final Future<ListeningContentCatalog>? contentFuture;
  final ListeningProgressStore progressStore;
  final LessonMediaService? mediaService;
  final VoicePromptService? voicePromptService;
  final Key? key;
}

/// Existing live dependencies for TopicLessonListScreen, supplied lazily by its owner.
class TopicLessonListBindings {
  const TopicLessonListBindings({
    this.controller,
    this.ensureDeviceConnected,
    this.onMainPressed,
    this.onVocabularyRequested,
    this.onVoiceNavigationPause,
    this.onVoiceNavigationResume,
    this.progressStore = const ListeningProgressStore(),
    this.mediaService,
    this.voicePromptService,
    this.initialLessonLeadPrompt,
    this.onTopicCompleted,
    this.onCommunicationRequested,
    this.key,
  });

  final LearningAudioDependencies? controller;
  final Future<bool> Function()? ensureDeviceConnected;
  final Future<void> Function()? onMainPressed;
  final VoidCallback? onVocabularyRequested;
  final Future<void> Function()? onVoiceNavigationPause;
  final VoidCallback? onVoiceNavigationResume;
  final ListeningProgressStore progressStore;
  final LessonMediaService? mediaService;
  final VoicePromptService? voicePromptService;
  final Future<void>? initialLessonLeadPrompt;
  final VoidCallback? onTopicCompleted;
  final VoidCallback? onCommunicationRequested;
  final Key? key;
}

/// Existing live dependencies for LessonIntroScreen, supplied lazily by its owner.
class LessonIntroBindings {
  const LessonIntroBindings({
    required this.progressStore,
    required this.mediaService,
    this.controller,
    this.guideAudioLibrary,
    this.voicePromptService,
    this.leadPrompt,
    this.onTopicCompleted,
    this.onCommunicationRequested,
    this.key,
  });

  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LearningAudioDependencies? controller;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final VoicePromptService? voicePromptService;
  final Future<void>? leadPrompt;
  final VoidCallback? onTopicCompleted;
  final VoidCallback? onCommunicationRequested;
  final Key? key;
}

/// Existing live dependencies for LessonPracticeScreen, supplied lazily by its owner.
class LessonPracticeBindings {
  const LessonPracticeBindings({
    required this.progressStore,
    required this.mediaService,
    this.vocabularyStore = const VocabularyStore(),
    this.controller,
    this.guideAudioLibrary,
    this.attemptEvaluator,
    this.completionChoiceRecognizer,
    this.voicePromptService,
    this.onTopicCompleted,
    this.onCommunicationRequested,
    this.key,
  });

  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final VocabularyStore vocabularyStore;
  final LearningAudioDependencies? controller;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final LessonAttemptEvaluator? attemptEvaluator;
  final LessonCompletionChoiceRecognizer? completionChoiceRecognizer;
  final VoicePromptService? voicePromptService;
  final VoidCallback? onTopicCompleted;
  final VoidCallback? onCommunicationRequested;
  final Key? key;
}

/// Existing live dependencies for LessonReviewScreen, supplied lazily by its owner.
class LessonReviewBindings {
  const LessonReviewBindings({
    required this.mediaService,
    this.learnNowBuilder,
    this.voicePromptService,
    this.key,
  });

  final LessonMediaService mediaService;
  final WidgetBuilder? learnNowBuilder;
  final VoicePromptService? voicePromptService;
  final Key? key;
}

/// Existing live dependencies for LessonChallengeScreen, supplied lazily by its owner.
class LessonChallengeBindings {
  const LessonChallengeBindings({
    required this.mediaService,
    this.startPaused = false,
    this.attemptEvaluator,
    this.voicePromptService,
    this.iosSpeechInput,
    this.onStarEarned,
    this.onStarEarnedWithResult,
    this.onStarEarnedWithAudioResult,
    this.onNeedsPractice,
    this.onChallengeResolved,
    this.key,
  });

  final LessonMediaService mediaService;
  final bool startPaused;
  final LessonAttemptEvaluator? attemptEvaluator;
  final VoicePromptService? voicePromptService;
  final LessonEnglishSpeechInput? iosSpeechInput;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onStarEarned;
  final Future<bool> Function(String starId, String english, String vietnamese)?
  onStarEarnedWithResult;
  final Future<bool> Function(
    String starId,
    String english,
    String vietnamese,
    String? correctAudioPath,
  )?
  onStarEarnedWithAudioResult;
  final Future<void> Function(
    String targetId,
    String english,
    String vietnamese,
  )?
  onNeedsPractice;
  final Future<void> Function(
    ListeningChallengeContent challenge,
    bool correct,
  )?
  onChallengeResolved;
  final Key? key;
}

/// Existing live dependencies for SongKaraokeScreen, supplied lazily by its owner.
class SongKaraokeBindings {
  const SongKaraokeBindings({
    required this.mediaService,
    required this.practiceBuilder,
    this.autoPlayDelay = const Duration(seconds: 3),
    this.backgroundAsset = songKaraokeBackgroundAsset,
    this.key,
  });

  final LessonMediaService mediaService;
  final WidgetBuilder practiceBuilder;
  final Duration autoPlayDelay;
  final String backgroundAsset;
  final Key? key;
}

/// Existing live dependencies for V4SongStageScreen, supplied lazily by its owner.
class V4SongStageBindings {
  const V4SongStageBindings({
    required this.mediaService,
    this.voicePromptService,
    this.key,
  });

  final LessonMediaService mediaService;
  final VoicePromptService? voicePromptService;
  final Key? key;
}

/// Existing live dependencies for VocabularyPracticeScreen, supplied lazily by its owner.
class VocabularyPracticeBindings {
  const VocabularyPracticeBindings({
    required this.store,
    required this.sessionStore,
    required this.mediaService,
    this.audioDependencies,
    this.attemptEvaluator,
    this.recordingEndpointDetector,
    this.voicePromptService,
    this.vocabularyAudioService,
    this.fixedPromptAudioService,
    this.samplePause = const Duration(seconds: 2),
    this.autoStart = true,
    this.onRequestVoiceChoice,
    this.key,
  });

  final VocabularyStore store;
  final VocabularySessionStore sessionStore;
  final LessonMediaService mediaService;
  final LearningAudioDependencies? audioDependencies;
  final LessonAttemptEvaluator? attemptEvaluator;
  final LessonRecordingEndpointDetector? recordingEndpointDetector;
  final VoicePromptService? voicePromptService;
  final VocabularyContentAudioService? vocabularyAudioService;
  final VocabularyFixedPromptAudioService? fixedPromptAudioService;
  final Duration samplePause;
  final bool autoStart;
  final Future<void> Function({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  })?
  onRequestVoiceChoice;
  final Key? key;
}

/// Existing live dependencies for SettingsSheet, supplied lazily by its owner.
class SettingsBindings {
  const SettingsBindings({
    required this.controller,
    this.themeMode = ThemeMode.system,
    this.connectionCoordinator,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onStartTutorial,
    this.config,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.stopMediaWhenBackgrounded,
    this.onStopMediaWhenBackgroundedChanged,
    this.key,
  });

  final ConversationSettingsPort controller;
  final ThemeMode themeMode;
  final DeviceConnectionCoordinator? connectionCoordinator;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onStartTutorial;
  final AppConfig? config;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final bool? stopMediaWhenBackgrounded;
  final ValueChanged<bool>? onStopMediaWhenBackgroundedChanged;
  final Key? key;
}

/// Existing live dependencies for HistorySheet, supplied lazily by its owner.
class HistoryBindings {
  const HistoryBindings({required this.controller, this.key});

  final ConversationHistoryPort controller;
  final Key? key;
}
