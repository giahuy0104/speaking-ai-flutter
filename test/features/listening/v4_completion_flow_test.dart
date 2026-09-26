import 'package:ai_speaking_flutter_app/features/listening/domain/v4_completion_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'completion choices reject negation, embedded text and wrong spoken numbers',
    () {
      const resolver = V4CompletionChoiceResolver();
      for (final text in [
        'Không học bài tiếp theo',
        'Mình đang học Bài 2',
        'Học lại Bài năm',
        'Bài 3',
      ]) {
        expect(
          resolver.resolve(
            text,
            stage: V4CompletionStage.lessonEnd,
            currentLesson: 1,
            nextLesson: 2,
          ),
          isNull,
          reason: text,
        );
      }
      expect(
        resolver.resolve(
          'Bắt đầu Level ba',
          stage: V4CompletionStage.nextLevel,
          nextLevel: 2,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          'Bắt đầu Level hai',
          stage: V4CompletionStage.nextLevel,
          nextLevel: 2,
        ),
        V4CompletionAction.startNextLevel,
      );
      expect(
        resolver.resolve(
          'Mình không muốn học lại',
          stage: V4CompletionStage.topicEnd,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          'Học lại Bài 8',
          stage: V4CompletionStage.lessonEnd,
          currentLesson: 7,
        ),
        isNull,
      );
    },
  );
  test('uses the approved V4.1 completion prompts verbatim', () {
    expect(
      v4CompletionPrompt(V4CompletionStage.lessonEnd),
      'Bạn muốn học bài tiếp theo hay học lại bài này?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.topicEnd),
      'Bạn muốn học chủ đề khác hay học lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.topicEndOneRemaining),
      'Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.nextLevel, nextLevel: 2),
      'Bạn muốn bắt đầu Level 2 hay dừng lại?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.courseRelearnLevel),
      'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?',
    );
    expect(
      v4CompletionPrompt(
        V4CompletionStage.lessonEnd,
        currentLesson: 1,
        nextLesson: 2,
      ),
      'Bạn muốn học Bài 2 hay học lại Bài 1?',
    );
    expect(
      v4CompletionPrompt(V4CompletionStage.topicEnd, topicNumber: 3),
      'Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?',
    );
  });

  test('resolves spoken V4 choices within the active completion stage', () {
    const resolver = V4CompletionChoiceResolver();

    expect(
      resolver.resolve(
        'Con muốn học bài tiếp theo',
        stage: V4CompletionStage.lessonEnd,
      ),
      V4CompletionAction.nextLesson,
    );
    expect(
      resolver.resolve('Học lại bài này ạ', stage: V4CompletionStage.lessonEnd),
      V4CompletionAction.relearnCurrentLesson,
    );
    expect(
      resolver.resolve('Học lại chủ đề', stage: V4CompletionStage.topicEnd),
      V4CompletionAction.relearnTopic,
    );
    expect(
      resolver.resolve(
        'Cho con học lại level hai',
        stage: V4CompletionStage.courseRelearnLevel,
      ),
      V4CompletionAction.relearnLevel2,
    );
    expect(
      resolver.resolve('Dừng lại', stage: V4CompletionStage.nextLevel),
      V4CompletionAction.stop,
    );
  });

  test(
    'global STOP can pause even when only learning choices are displayed',
    () {
      expect(
        const V4CompletionChoiceResolver().resolve(
          'Dừng lại',
          stage: V4CompletionStage.lessonEnd,
          allowedActions: const <V4CompletionAction>[
            V4CompletionAction.nextLesson,
            V4CompletionAction.relearnCurrentLesson,
          ],
        ),
        V4CompletionAction.stop,
      );
    },
  );

  test('does not navigate on prompt echo or replay of a different lesson', () {
    for (final text in <String>[
      'Bạn muốn học Bài 2 hay học lại Bài 1?',
      'Học lại Bài 2',
      'Học tiếp hay học lại',
    ]) {
      expect(
        const V4CompletionChoiceResolver().resolve(
          text,
          stage: V4CompletionStage.lessonEnd,
          currentLesson: 1,
          nextLesson: 2,
        ),
        isNull,
      );
    }
  });

  test(
    'understands the actual numbered choices and short continue answers',
    () {
      const resolver = V4CompletionChoiceResolver();
      for (final text in <String>[
        'Bài 2',
        'Bài số hai',
        'Đi tiếp',
        'Tiếp tục',
      ]) {
        expect(
          resolver.resolve(
            text,
            stage: V4CompletionStage.lessonEnd,
            currentLesson: 1,
            nextLesson: 2,
          ),
          V4CompletionAction.nextLesson,
        );
      }
      expect(
        resolver.resolve(
          'Bài một',
          stage: V4CompletionStage.lessonEnd,
          currentLesson: 1,
          nextLesson: 2,
        ),
        V4CompletionAction.relearnCurrentLesson,
      );
      for (final text in <String>['Chủ đề khác', 'Học tiếp', 'Đi tiếp']) {
        expect(
          resolver.resolve(text, stage: V4CompletionStage.topicEnd),
          V4CompletionAction.nextTopic,
        );
      }
      expect(
        resolver.resolve(
          'I want to practice again',
          stage: V4CompletionStage.lessonEnd,
        ),
        V4CompletionAction.relearnCurrentLesson,
      );
      expect(
        resolver.resolve('The next lesson', stage: V4CompletionStage.lessonEnd),
        V4CompletionAction.nextLesson,
      );
    },
  );
}
