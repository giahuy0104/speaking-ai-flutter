import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_curriculum_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final topics = <ListeningTopicContent>[
    _topic(1),
    _topic(2),
    _topic(3),
    _topic(4, levelNumber: 2),
  ];
  final levels = <ListeningLevelContent>[
    const ListeningLevelContent(
      id: 'level-1',
      number: 1,
      titleVi: 'Level 1',
      topicNumbers: <int>[1, 2, 3],
    ),
    const ListeningLevelContent(
      id: 'level-2',
      number: 2,
      titleVi: 'Level 2',
      topicNumbers: <int>[4],
    ),
  ];
  final group = ListeningContentAgeGroup(
    startAge: 3,
    endAge: 5,
    topics: topics,
    levels: levels,
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

  test('level completion depends on every topic, not numeric order', () {
    final progress = <String, int>{
      for (final number in <int>[1, 2])
        for (final lesson in topics[number - 1].lessons) lesson.id: 1,
    };

    expect(
      ListeningCurriculumFlow.allTopicsInLevelCompleted(
        group,
        levels.first,
        progress,
        const <String>{},
      ),
      isFalse,
    );

    for (final lesson in topics[2].lessons) {
      progress[lesson.id] = 1;
    }
    expect(
      ListeningCurriculumFlow.allTopicsInLevelCompleted(
        group,
        levels.first,
        progress,
        const <String>{},
      ),
      isTrue,
    );
  });

  test('the next Level unlocks only after all previous topics complete', () {
    expect(
      ListeningCurriculumFlow.levelUnlocked(
        group,
        levels[1],
        const <String, int>{},
        const <String>{},
      ),
      isFalse,
    );
    final progress = <String, int>{
      for (final topic in topics.take(3))
        for (final lesson in topic.lessons) lesson.id: 1,
    };
    expect(
      ListeningCurriculumFlow.levelUnlocked(
        group,
        levels[1],
        progress,
        const <String>{},
      ),
      isTrue,
    );
  });

  test('patch retains earned access without crediting replacement Cores', () {
    final progress = <String, int>{
      '__topic-patch-v42-unlocked-level:3-5': 2,
      '__topic-patch-v42-unlocked-lesson:${topics.first.lessons[1].id}': 1,
    };
    expect(
      ListeningCurriculumFlow.currentUnlockedLevelNumber(group, progress, {}),
      2,
    );
    expect(
      ListeningCurriculumFlow.levelUnlocked(group, levels[1], progress, {}),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.lessonUnlocked(topics.first, 1, progress, {}),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.topicState(topics.first, progress, {}),
      ListeningTopicLearningState.notStarted,
    );
    expect(
      ListeningCurriculumFlow.allTopicsInLevelCompleted(
        group,
        levels.first,
        progress,
        {},
      ),
      isFalse,
    );
  });

  test('young-course access never becomes a prerequisite for six-seven', () {
    final older = ListeningContentAgeGroup(
      startAge: 6,
      endAge: 7,
      topics: topics,
      levels: levels,
    );
    final youngOnly = {'__topic-patch-v42-unlocked-level:3-5': 2};
    expect(
      ListeningCurriculumFlow.levelUnlocked(older, levels.first, {}, {}),
      isTrue,
    );
    expect(
      ListeningCurriculumFlow.levelUnlocked(older, levels[1], youngOnly, {}),
      isFalse,
    );
    expect(
      ListeningCurriculumFlow.currentUnlockedLevelNumber(older, youngOnly, {}),
      1,
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
