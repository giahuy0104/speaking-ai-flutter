import 'package:flutter/foundation.dart';

enum ChallengeCompletionOutcome { correct, needsPractice }

@immutable
final class ChallengeCompletionResult {
  const ChallengeCompletionResult({
    required this.operationId,
    required this.challengeId,
    required this.challengeIndex,
    required this.targetId,
    required this.outcome,
  });

  final int operationId;
  final String challengeId;
  final int challengeIndex;
  final String targetId;
  final ChallengeCompletionOutcome outcome;

  bool matches({
    required int operationId,
    required String challengeId,
    required int challengeIndex,
    required String targetId,
  }) =>
      this.operationId == operationId &&
      this.challengeId == challengeId &&
      this.challengeIndex == challengeIndex &&
      this.targetId == targetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeCompletionResult &&
          operationId == other.operationId &&
          challengeId == other.challengeId &&
          challengeIndex == other.challengeIndex &&
          targetId == other.targetId &&
          outcome == other.outcome;

  @override
  int get hashCode =>
      Object.hash(operationId, challengeId, challengeIndex, targetId, outcome);
}
