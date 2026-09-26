/// Stable keys for authored MAIN prompts.
abstract final class MainAssistantAudioKeys {
  static const openMenu = 'assistant.main.open_menu.vi';
  static const chooseTranslation = 'assistant.main.choose_translation.vi';
  static const chooseListening = 'assistant.main.choose_listening.vi';
  static const chooseVocabulary = 'assistant.main.choose_vocabulary.vi';
  static const invalidChoice = 'assistant.main.invalid_choice.vi';
  static const noSpeech = 'assistant.main.no_speech.vi';
  static const cancelled = 'assistant.main.cancelled.vi';
  static const switchedToListening = 'assistant.main.switched_to_listening.vi';
  static const switchedToVocabulary =
      'assistant.main.switched_to_vocabulary.vi';
  static const switchedToTranslation =
      'assistant.main.switched_to_translation.vi';
  static const translationAcknowledged =
      'assistant.main.translation_acknowledged.vi';
  static const translationStarted = 'assistant.main.translation_started.vi';
  static const translationContinue = 'assistant.main.translation_continue.vi';
  static const afterTranslationStop =
      'assistant.main.after_translation_stop.vi';
  static const translationStopped = 'assistant.main.translation_stopped.vi';
  static const activeLearningControls =
      'assistant.main.active_learning_controls.vi';
  static const challengeControls = 'assistant.learning.challenge_controls.vi';
  static const songControls = 'assistant.learning.song_controls.vi';
  static const resumeLearning = 'assistant.learning.resume.vi';
  static const continueSubject = 'assistant.learning.continue_subject.vi';
  static const nextItem = 'assistant.learning.next_item.vi';
  static const previousItem = 'assistant.learning.previous_item.vi';
  static const replayItem = 'assistant.learning.replay_item.vi';
  static const nextLesson = 'assistant.learning.next_lesson.vi';
  static const restartLesson = 'assistant.learning.restart_lesson.vi';
  static const firstItemReplay = 'assistant.learning.first_item_replay.vi';
  static const challengeSkipCorrect = 'listening.feedback.age.skip_correct.vi';
  static const keepCurrentContent = 'assistant.main.keep_current_content.vi';
  static const lessonNotFound = 'assistant.main.lesson_not_found.vi';
  static const topicNotFound = 'assistant.main.topic_not_found.vi';
  static const catalogLoadError = 'assistant.main.catalog_load_error.vi';
  static const courseRelearnLevel = 'assistant.level.choose_course_relearn.vi';
  static const chooseRelearnLevel = 'assistant.level.choose_relearn.vi';
  static const topicWithoutLessons =
      'assistant.topic.no_lessons_choose_other.vi';
  static const startNow = 'assistant.main.start_now.vi';
  static const songReplay = 'assistant.main.song_replay.vi';

  static String levelTopicSelection(int levelNumber) =>
      'assistant.topic.level_selection.$levelNumber.vi';

  static String chooseTopic(int topicCount) =>
      'assistant.topic.choose_$topicCount.vi';

  static String invalidTopic(int topicCount) =>
      'assistant.topic.invalid_$topicCount.vi';

  static String replayTopic(int topicNumber) =>
      'assistant.topic.replay.$topicNumber.vi';
}
