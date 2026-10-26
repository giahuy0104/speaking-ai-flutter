import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_star_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds stable Star slots for Core sentences only', () {
    expect(LessonStarFlow.expectedStarIds(_lesson), <String>{
      'core:core-1',
      'core:core-2',
    });
  });

  test('counts only missing stable slots and ignores unrelated earned IDs', () {
    final remaining = LessonStarFlow.remainingStarCount(_lesson, <String>{
      'core:core-1',
      'legacy:unrelated',
    });

    expect(remaining, 1);
  });
}

const _lesson = ListeningLessonContent(
  id: 'lesson-1',
  number: 1,
  titleVi: 'Bài kiểm tra',
  titleEn: 'Test lesson',
  intro: '',
  outro: '',
  estimatedMinutes: 4,
  sentences: <ListeningSentenceContent>[
    ListeningSentenceContent(
      id: 'core-1',
      number: 1,
      english: 'One.',
      vietnamese: 'Một.',
    ),
    ListeningSentenceContent(
      id: 'core-2',
      number: 2,
      english: 'Two.',
      vietnamese: 'Hai.',
    ),
  ],
  rolePlay: ListeningRolePlayContent(
    scenarioVi: 'Kiểm tra',
    turns: <ListeningRolePlayTurn>[
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.homi,
        english: 'Hello.',
        vietnamese: 'Xin chào.',
      ),
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.child,
        english: 'Hi.',
        vietnamese: 'Chào bạn.',
      ),
      ListeningRolePlayTurn(
        speaker: ListeningRolePlaySpeaker.child,
        english: 'Bye.',
        vietnamese: 'Tạm biệt.',
      ),
    ],
  ),
);
