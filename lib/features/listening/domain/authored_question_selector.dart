import 'listening_content.dart';

/// Selects one fixed authored Challenge without synthesising content.
class AuthoredQuestionSelector {
  const AuthoredQuestionSelector();

  /// A weak Core has priority. Otherwise Challenges rotate in a deterministic
  /// order and a new round starts only after all of them have been processed.
  ListeningChallengeContent? selectSingleChallenge(
    Iterable<ListeningChallengeContent> challengeBank, {
    Iterable<String> weakTargetIds = const <String>[],
    Iterable<String> usedChallengeIds = const <String>[],
    int seed = 0,
  }) {
    final candidates = challengeBank
        .where(
          (challenge) =>
              challenge.id.trim().isNotEmpty &&
              challenge.targetId.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    for (final weakTarget in _normalizedIds(weakTargetIds)) {
      for (final challenge in candidates) {
        if (challenge.targetId.trim() == weakTarget) return challenge;
      }
    }

    final used = _normalizedIds(usedChallengeIds);
    final remaining = candidates
        .where((challenge) => !used.contains(challenge.id.trim()))
        .toList(growable: false);
    final round = remaining.isEmpty ? candidates : remaining;
    return round[seed.abs() % round.length];
  }

  static Set<String> _normalizedIds(Iterable<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}
