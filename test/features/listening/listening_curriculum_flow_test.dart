import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_curriculum_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final topics = List.generate(10, (index) => _topic(index + 1));
  final group = ListeningContentAgeGroup(
    startAge: 3,
    endAge: 5,
    topics: topics,
  );

  test('topics are peers while lessons remain sequential', () {
    final progress = <String, int>{};
    const activities = <String>{};

    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        0,
        progress,
        activities,
      ),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        1,
        progress,
        activities,
      ),
      isFalse,
    );

    progress['topic-1-lesson-1'] = 1;
    expect(
      ListeningCurriculumFlow.lessonUnlocked(
        topics.first,
        1,
        progress,
        activities,
      ),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.topicState(topics[1], progress, activities),
      ListeningTopicLearningState.notStarted,
    );
  });

  test('course completion requires all ten topics, independent of order', () {
    final progress = <String, int>{
      for (final number in <int>[10, 1, 5])
        for (final lesson in topics[number - 1].lessons) lesson.id: 1,
    };

    expect(
      ListeningCurriculumFlow.allTopicsCompleted(
        group,
        progress,
        const <String>{},
      ),
      isFalse,
    );

    for (final topic in topics) {
      for (final lesson in topic.lessons) {
        progress[lesson.id] = 1;
      }
    }
    expect(
      ListeningCurriculumFlow.allTopicsCompleted(
        group,
        progress,
        const <String>{},
      ),
      isTrue,
    );
  });

  test('remaining topics span the entire age group', () {
    final progress = <String, int>{
      for (final topic in topics.take(3))
        for (final lesson in topic.lessons) lesson.id: 1,
    };
    expect(
      ListeningCurriculumFlow.incompleteTopicNumbers(group, progress, {}),
      [4, 5, 6, 7, 8, 9, 10],
    );
    expect(
      ListeningCurriculumFlow.allTopicsCompleted(group, progress, {}),
      isFalse,
    );
  });

  test('patch retains earned access without crediting replacement Cores', () {
    final progress = <String, int>{
      '__topic-patch-v42-unlocked-level:3-5': 2,
      '__topic-patch-v42-unlocked-lesson:${topics.first.lessons[1].id}': 1,
    };
    expect(
      ListeningCurriculumFlow.lessonUnlocked(topics.first, 1, progress, {}),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.topicState(topics.first, progress, {}),
      ListeningTopicLearningState.notStarted,
    );
    expect(
      ListeningCurriculumFlow.allTopicsCompleted(group, progress, {}),
      isFalse,
    );
  });
}

ListeningTopicContent _topic(int number, {int levelNumber = 1}) {
  return ListeningTopicContent(
    id: 'topic-$number',
    number: number,
    titleVi: 'Chủ đề $number',
    titleEn: 'Topic $number',
    levelNumber: levelNumber,
    lessons: <ListeningLessonContent>[
      _lesson('topic-$number-lesson-1', 1),
      _lesson('topic-$number-lesson-2', 2),
    ],
  );
}

ListeningLessonContent _lesson(String id, int number) {
  return ListeningLessonContent(
    id: id,
    number: number,
    titleVi: 'Bài $number',
    titleEn: 'Lesson $number',
    intro: '',
    outro: '',
    estimatedMinutes: 1,
    sentences: const <ListeningSentenceContent>[
      ListeningSentenceContent(
        number: 1,
        english: 'Hello.',
        vietnamese: 'Xin chào.',
      ),
    ],
  );
}
