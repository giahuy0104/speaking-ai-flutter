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
  static const challengeIntro = 'listening.challenge.intro.vi';
  static const challengeResume = 'listening.challenge.resume.vi';
  static const challengeAnswerHandoff = 'listening.challenge.answer_handoff.vi';
  static const rewardFirstStar = 'listening.reward.first_star.vi';
  static const completionTopicOneRemaining =
      'listening.completion.topic.one_remaining.vi';
  static const milestoneCourse = 'listening.milestone.course.vi';
  static const challengeInvalidContent =
      'listening.challenge.invalid_content.vi';
  static const reviewCompletedNextLesson =
      'listening.review.completed.next_lesson.vi';
  static const reviewCompletedChooseLesson =
      'listening.review.completed.choose_lesson.vi';

  static String lockedLevel(int levelNumber) =>
      'listening.navigation.locked_level.$levelNumber.vi';

  static String lockedLesson(int lessonNumber) =>
      'listening.navigation.locked_lesson.$lessonNumber.vi';

  static String startLessonChoice(int lessonNumber) =>
      'listening.navigation.start_lesson.$lessonNumber.vi';

  static String invalidLessonCount(int lessonCount) =>
      'listening.navigation.invalid_lesson_count.$lessonCount.vi';

  static String completionLesson(int currentLesson, int nextLesson) =>
      'listening.completion.lesson.${currentLesson}_to_$nextLesson.vi';

  static String completionTopicReplay(int topicNumber) =>
      'listening.completion.topic.replay.$topicNumber.vi';

  static String completionLevelStart(int levelNumber) =>
      'listening.completion.level.start.$levelNumber.vi';

  static String milestoneLesson(int lessonNumber) =>
      'listening.milestone.lesson.$lessonNumber.vi';

  static String milestoneTopic(int topicNumber) =>
      'listening.milestone.topic.$topicNumber.vi';

  static String milestoneLevel(int levelNumber) =>
      'listening.milestone.level.$levelNumber.vi';

  /// Resolves the finite, context-dependent prompts used by the Topic module.
  /// Unknown lesson content is intentionally left to its sentence-specific key.
  static String? topicContextPrompt(String text) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value ==
        'Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?') {
      return completionTopicOneRemaining;
    }
    if (value == 'Tiếp theo là một câu thử thách nhé.') {
      return challengeIntro;
    }
    if (value == 'Bạn đã hoàn thành khóa học rồi!') return milestoneCourse;
    if (value == 'Bài học chưa có Challenge hợp lệ cho từng Core.') {
      return challengeInvalidContent;
    }

    final lockedLevelMatch = RegExp(
      r'^Bạn cần hoàn thành Level (\d+) trước nhé\.$',
    ).firstMatch(value);
    if (lockedLevelMatch != null) {
      return lockedLevel(int.parse(lockedLevelMatch.group(1)!));
    }
    final lockedLessonMatch = RegExp(
      r'^Bạn cần học xong Bài (\d+) trước nhé\.$',
    ).firstMatch(value);
    if (lockedLessonMatch != null) {
      return lockedLesson(int.parse(lockedLessonMatch.group(1)!));
    }
    final lessonChoiceMatch = RegExp(
      r'^Bạn muốn học Bài (\d+) hay học lại Bài (\d+)\?$',
    ).firstMatch(value);
    if (lessonChoiceMatch != null) {
      return completionLesson(
        int.parse(lessonChoiceMatch.group(2)!),
        int.parse(lessonChoiceMatch.group(1)!),
      );
    }
    final startLessonMatch = RegExp(
      r'^Bạn muốn bắt đầu Bài (\d+) hay dừng lại\?$',
    ).firstMatch(value);
    if (startLessonMatch != null) {
      return startLessonChoice(int.parse(startLessonMatch.group(1)!));
    }
    final invalidLessonMatch = RegExp(
      r'^Có (\d+) Bài học\. Bạn chọn từ số 1 đến số \1\.$',
    ).firstMatch(value);
    if (invalidLessonMatch != null) {
      return invalidLessonCount(int.parse(invalidLessonMatch.group(1)!));
    }
    final topicChoiceMatch = RegExp(
      r'^Bạn muốn chọn Chủ đề khác hay học lại Chủ đề (\d+)\?$',
    ).firstMatch(value);
    if (topicChoiceMatch != null) {
      return completionTopicReplay(int.parse(topicChoiceMatch.group(1)!));
    }
    final nextLevelMatch = RegExp(
      r'^Bạn muốn bắt đầu Level (\d+) hay dừng lại\?$',
    ).firstMatch(value);
    if (nextLevelMatch != null) {
      return completionLevelStart(int.parse(nextLevelMatch.group(1)!));
    }
    final lessonMilestoneMatch = RegExp(
      r'^Bạn đã hoàn thành Bài (\d+) rồi!$',
    ).firstMatch(value);
    if (lessonMilestoneMatch != null) {
      return milestoneLesson(int.parse(lessonMilestoneMatch.group(1)!));
    }
    final topicMilestoneMatch = RegExp(
      r'^Bạn đã hoàn thành Chủ đề (\d+) rồi!$',
    ).firstMatch(value);
    if (topicMilestoneMatch != null) {
      return milestoneTopic(int.parse(topicMilestoneMatch.group(1)!));
    }
    final levelMilestoneMatch = RegExp(
      r'^Bạn đã hoàn thành Level (\d+) rồi!$',
    ).firstMatch(value);
    if (levelMilestoneMatch != null) {
      return milestoneLevel(int.parse(levelMilestoneMatch.group(1)!));
    }
    return null;
  }

  static String topicResume(int topicNumber) =>
      'listening.topic.$topicNumber.resume.vi';

  static String lessonIntro(String lessonId) =>
      'listening.lesson.${lessonId.trim()}.intro.vi';

  static String lessonResume(String lessonId) =>
      'listening.lesson.${lessonId.trim()}.resume.vi';

  static String lessonRelearn(String lessonId) =>
      'listening.lesson.${lessonId.trim()}.relearn.vi';

  static String lessonSongResume(String lessonId) =>
      'listening.lesson.${lessonId.trim()}.song_resume.vi';

  static String lessonRemainingStars(
    int remainingStars, {
    required bool childFriendly,
  }) =>
      'listening.lesson.remaining_stars.$remainingStars.'
      '${childFriendly ? 'young' : 'older'}.vi';

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

  static String songStart(String songAudioId) {
    var value = songAudioId.trim().toLowerCase();
    if (value.endsWith('_song')) {
      value = value.substring(0, value.length - '_song'.length);
    }
    return 'listening.song.${value.replaceAll('_', '-')}.start.vi';
  }
}
