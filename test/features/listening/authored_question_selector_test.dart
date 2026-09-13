import 'package:ai_speaking_flutter_app/features/listening/domain/authored_question_selector.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const selector = AuthoredQuestionSelector();
  final bank = <ListeningChallengeContent>[
    _challenge('Q01', targetId: 'T01'),
    _challenge('Q02', targetId: 'T02'),
    _challenge('Q03', targetId: 'T03'),
  ];

  test('selects the first weak Core target', () {
    final selected = selector.selectSingleChallenge(
      bank,
      weakTargetIds: const <String>['T03', 'T01'],
      usedChallengeIds: const <String>['Q03'],
      seed: 1,
    );

    expect(selected?.id, 'Q03');
  });

  test('rotates only through unused Challenges', () {
    final selected = selector.selectSingleChallenge(
      bank,
      usedChallengeIds: const <String>['Q01', 'Q02'],
      seed: 7,
    );

    expect(selected?.id, 'Q03');
  });

  test('starts a deterministic new round after all Challenges are used', () {
    final first = selector.selectSingleChallenge(
      bank,
      usedChallengeIds: const <String>['Q01', 'Q02', 'Q03'],
      seed: 4,
    );
    final repeated = selector.selectSingleChallenge(
      bank,
      usedChallengeIds: const <String>['Q01', 'Q02', 'Q03'],
      seed: 4,
    );

    expect(first?.id, 'Q02');
    expect(repeated?.id, first?.id);
  });

  test('returns null for an invalid authored bank', () {
    expect(
      selector.selectSingleChallenge(const <ListeningChallengeContent>[]),
      isNull,
    );
  });
}

ListeningChallengeContent _challenge(String id, {required String targetId}) =>
    ListeningChallengeContent(
      id: id,
      format: 'VI_TO_EN',
      prompt: 'Prompt $id',
      choices: <String>['Answer $id', 'Distractor $id'],
      correctAnswer: 'Answer $id',
      correctVietnamese: 'Đáp án $id',
      targetId: targetId,
    );
