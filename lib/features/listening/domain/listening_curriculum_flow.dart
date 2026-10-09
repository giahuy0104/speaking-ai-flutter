import 'listening_content.dart';

enum ListeningTopicLearningState { notStarted, inProgress, completed }

/// Pure curriculum rules shared by the catalog, lesson path, and completion
/// flow. Levels are sequential; topics inside an unlocked level are peers;
/// lessons inside a topic are sequential.
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

  static bool allTopicsInLevelCompleted(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) => level.topicNumbers.every((number) {
    final topic = group.topics.where((candidate) => candidate.number == number);
    return topic.isNotEmpty &&
        topicState(topic.first, progress, completedV4Activities) ==
            ListeningTopicLearningState.completed;
  });

  static List<int> incompleteTopicNumbers(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Map<String, int> progress,
    Set<String> completedV4Activities,
  ) => level.topicNumbers
      .where((number) {
        final matches = group.topics.where(
          (candidate) => candidate.number == number,
        );
        return matches.isEmpty ||
            topicState(matches.first, progress, completedV4Activities) !=
                ListeningTopicLearningState.completed;
      })
      .toList(growable: false);

  static int currentUnlockedLevelNumber(
    ListeningContentAgeGroup group,
    Map<String, int> progress,
    Set<String> completedActivities,
  ) {
    final retainedLevel = _retainedUnlockedLevel(group, progress);
    for (final level in group.levels) {
      if (level.number < retainedLevel) continue;
      if (!allTopicsInLevelCompleted(
        group,
        level,
        progress,
        completedActivities,
      )) {
        return level.number;
      }
    }
    return group.levels.isEmpty ? 1 : group.levels.last.number;
  }

  static bool levelUnlocked(
    ListeningContentAgeGroup group,
    ListeningLevelContent level,
    Map<String, int> progress,
    Set<String> completedActivities,
  ) {
    final retainedLevel = _retainedUnlockedLevel(group, progress);
    for (final previous in group.levels) {
      if (previous.number >= level.number) break;
      if (previous.number < retainedLevel) continue;
      if (!allTopicsInLevelCompleted(
        group,
        previous,
        progress,
        completedActivities,
      )) {
        return false;
      }
    }
    return true;
  }

  // Access already earned before the four-topic content migration is retained;
  // this is deliberately NOT treated as completion of the replacement Cores.
  static int _retainedUnlockedLevel(
    ListeningContentAgeGroup group,
    Map<String, int> progress,
  ) {
    if (!((group.startAge == 3 && group.endAge == 5) ||
        (group.startAge == 6 && group.endAge == 7))) {
      return 1;
    }
    return (progress['__topic-patch-v42-unlocked-level:${group.startAge}-${group.endAge}'] ??
            1)
        .clamp(1, group.levels.isEmpty ? 1 : group.levels.last.number);
  }
}
