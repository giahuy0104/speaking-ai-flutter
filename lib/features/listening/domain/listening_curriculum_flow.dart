import 'listening_content.dart';

enum ListeningTopicLearningState { notStarted, inProgress, completed }

/// Pure curriculum rules shared by the catalog, lesson path, and completion
/// flow. All topics in the age group are peers; lessons inside a topic
/// keep their existing sequential unlock rules.
abstract final class ListeningCurriculumFlow {
  static bool lessonCompleted(
    ListeningLessonContent lesson,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    final coreCompleted = (progress[lesson.id] ?? 0) >= lesson.sentences.length;
    return coreCompleted &&
        (!lesson.usesV4Flow || completedV4Activities.contains(lesson.id));
  }

  static ListeningTopicLearningState topicState(
    ListeningTopicContent topic,
    Map<String, int> progress,
    Set<String> completedV4Activities, {
    Set<String> startedLessonIds = const <String>{},
  }) {
    final completed = topic.lessons.every(
      (lesson) => lessonCompleted(lesson, progress, completedV4Activities),
    );
    if (completed) return ListeningTopicLearningState.completed;
    final started = topic.lessons.any(
      (lesson) =>
          (progress[lesson.id] ?? 0) > 0 ||
          startedLessonIds.contains(lesson.id) ||
          completedV4Activities.contains(lesson.id),
    );
    return started
        ? ListeningTopicLearningState.inProgress
        : ListeningTopicLearningState.notStarted;
  }

  static ListeningLessonContent? firstIncompleteLesson(
    ListeningTopicContent topic,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    for (final lesson in topic.lessons) {
      if (!lessonCompleted(lesson, progress, completedV4Activities)) {
        return lesson;
      }
    }
    return null;
  }

  static bool lessonUnlocked(
    ListeningTopicContent topic,
    int lessonIndex,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) {
    if (lessonIndex <= 0) return true;
    if (lessonIndex < topic.lessons.length &&
        progress['__topic-patch-v42-unlocked-lesson:${topic.lessons[lessonIndex].id}'] ==
            1) {
      return true;
    }
    return lessonCompleted(
      topic.lessons[lessonIndex - 1],
      progress,
      completedV4Activities,
    );
  }

  static bool courseCompleted(
    ListeningContentAgeGroup group,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) =>
      group.topics.length == 10 &&
      group.topics.every(
        (topic) =>
            topicState(topic, progress, completedV4Activities) ==
            ListeningTopicLearningState.completed,
      );

  static List<int> incompleteTopicNumbers(
    ListeningContentAgeGroup group,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) => group.topics
      .where(
        (topic) =>
            topicState(topic, progress, completedV4Activities) !=
            ListeningTopicLearningState.completed,
      )
      .map((topic) => topic.number)
      .toList(growable: false);
}
