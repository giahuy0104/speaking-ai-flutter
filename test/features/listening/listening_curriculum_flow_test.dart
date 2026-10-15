import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_curriculum_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final topics = List<ListeningTopicContent>.generate(
    10,
    (index) => _topic(index + 1),
  );
  final group = ListeningContentAgeGroup(
    startAge: 3,
    endAge: 5,
    topics: topics,
  );

  test('all ten topics are peers while lessons remain sequential', () {
    final progress = <String, int>{};
    const activities = <String>{};
    for (final topic in topics) {
      expect(
        ListeningCurriculumFlow.lessonUnlocked(topic, 0, progress, activities),
        isTrue,
      );
    }
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
      ListeningCurriculumFlow.topicState(topics[9], progress, activities),
      ListeningTopicLearningState.notStarted,
    );
  });

  test(
    'course completion requires every topic regardless of numeric order',
    () {
      final progress = <String, int>{
        for (final topic in topics.skip(1))
          for (final lesson in topic.lessons) lesson.id: 1,
      };
      expect(
        ListeningCurriculumFlow.allTopicsCompleted(group, progress, const {}),
        isFalse,
      );
      expect(
        ListeningCurriculumFlow.incompleteTopicNumbers(
          group,
          progress,
          const {},
        ),
        <int>[1],
      );

      for (final lesson in topics.first.lessons) {
        progress[lesson.id] = 1;
      }
      expect(
        ListeningCurriculumFlow.allTopicsCompleted(group, progress, const {}),
        isTrue,
      );
      expect(
        ListeningCurriculumFlow.incompleteTopicNumbers(
          group,
          progress,
          const {},
        ),
        isEmpty,
      );
    },
  );

  test(
    'legacy unlocked-level metadata does not gate topics or grant progress',
    () {
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
        ListeningCurriculumFlow.incompleteTopicNumbers(group, progress, {}),
        List<int>.generate(10, (index) => index + 1),
      );
    },
  );
}

ListeningTopicContent _topic(int number) => ListeningTopicContent(
  id: 'topic-$number',
  number: number,
  titleVi: 'Chủ đề $number',
  titleEn: 'Topic $number',
  lessons: <ListeningLessonContent>[
    _lesson('topic-$number-lesson-1', 1),
    _lesson('topic-$number-lesson-2', 2),
  ],
);

ListeningLessonContent _lesson(String id, int number) => ListeningLessonContent(
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
