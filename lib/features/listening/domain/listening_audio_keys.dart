abstract final class ListeningAudioKeys {
  static const chooseTopic = 'listening.navigation.choose_topic.vi';
  static const chooseLevel = 'listening.navigation.choose_level.vi';
  static const chooseLesson = 'listening.navigation.choose_lesson.vi';
  static const replayTopic = 'listening.navigation.replay_topic.vi';
  static const replayLesson = 'listening.navigation.replay_lesson.vi';
  static const noTopic = 'listening.navigation.no_topic.vi';
  static const noLesson = 'listening.navigation.no_lesson.vi';

  static const guideStart = 'listening.guide.start.vi';
  static const guideContinue = 'listening.guide.continue.vi';
  static const guideRepeat = 'listening.guide.repeat.vi';
  static const guideYourTurn = 'listening.guide.your_turn.vi';
  static const guideTryAgain = 'listening.guide.try_again.vi';
  static const guideCompleted = 'listening.guide.completed.vi';

  static String lessonIntro(String lessonId) =>
      'listening.lesson.${lessonId.trim()}.intro.vi';

  static String sentenceEnglish(String sentenceId) =>
      'listening.sentence.${sentenceId.trim()}.en';

  static String sentenceVietnamese(String sentenceId) =>
      'listening.sentence.${sentenceId.trim()}.vi';

  static String challengePrompt(String challengeId) =>
      'listening.challenge.${challengeId.trim()}.prompt.vi';

  static String challengeAnswer(String challengeId) =>
      'listening.challenge.${challengeId.trim()}.answer.en';

  static const feedbackCorrect = 'listening.feedback.correct.vi';
  static const feedbackIncorrect = 'listening.feedback.incorrect.vi';
  static const feedbackTryAgain = 'listening.feedback.try_again.vi';
  static const feedbackCompleted = 'listening.feedback.completed.vi';
}
