import '../../listening/domain/listening_content.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';

/// Bridges authored learning content into the vocabulary feature without
/// coupling vocabulary presentation to listening implementation details.
class AuthoredVocabularySuggestionProvider {
  AuthoredVocabularySuggestionProvider({required this.loadCatalog});

  final Future<ListeningContentCatalog> Function() loadCatalog;
  Future<ListeningContentCatalog>? _catalogFuture;

  Future<ListeningContentCatalog> _catalog() =>
      _catalogFuture ??= loadCatalog();

  Future<bool> containsInCurriculum(VocabularyTranslation candidate) async {
    final target = _normalized(candidate.englishText);
    if (target.isEmpty) return false;
    final catalog = await _catalog();

    bool matches(String english) => _normalized(english) == target;

    for (final group in catalog.groups) {
      for (final topic in group.topics) {
        for (final lesson in <ListeningLessonContent>[
          ...topic.lessons,
          ...topic.songs,
        ]) {
          for (final sentence in <ListeningSentenceContent>[
            ...lesson.sentences,
            ...lesson.karaokeLines,
          ]) {
            if (matches(sentence.english)) return true;
          }
          for (final challenge in lesson.challengeBank) {
            if (matches(challenge.correctAnswer)) return true;
          }
        }
      }
      for (final level in group.levels) {
        for (final mission in level.missionBank) {
          if (matches(mission.correctAnswer)) return true;
        }
      }
    }
    return false;
  }

  Future<List<VocabularyTranslation>> call(String input, int childAge) async {
    final query = _normalized(input);
    if (query.length < 2) return const <VocabularyTranslation>[];

    final catalog = await _catalog();
    final group = _groupForAge(catalog.groups, childAge);
    if (group == null) return const <VocabularyTranslation>[];

    final ranked = <({VocabularyTranslation value, int score})>[];
    final seen = <String>{};

    void addCandidate(String english, String vietnamese) {
      final englishText = english.trim();
      final vietnameseText = vietnamese.trim();
      if (englishText.isEmpty || vietnameseText.isEmpty) return;

      final englishNormalized = _normalized(englishText);
      final vietnameseNormalized = _normalized(vietnameseText);
      final key = '$englishNormalized\u0000$vietnameseNormalized';
      if (!seen.add(key)) return;

      final score = _matchScore(
        query: query,
        english: englishNormalized,
        vietnamese: vietnameseNormalized,
      );
      if (score <= 0) return;
      ranked.add((
        value: VocabularyTranslation(
          englishText: englishText,
          vietnameseText: vietnameseText,
        ),
        score: score,
      ));
    }

    for (final topic in group.topics) {
      addCandidate(topic.titleEn, topic.titleVi);
      for (final lesson in <ListeningLessonContent>[
        ...topic.lessons,
        ...topic.songs,
      ]) {
        addCandidate(lesson.titleEn, lesson.titleVi);
        for (final sentence in <ListeningSentenceContent>[
          ...lesson.sentences,
          ...lesson.karaokeLines,
        ]) {
          addCandidate(sentence.english, sentence.vietnamese);
        }
      }
    }

    ranked.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      return left.value.englishText.length.compareTo(
        right.value.englishText.length,
      );
    });
    return ranked.take(8).map((candidate) => candidate.value).toList();
  }

  ListeningContentAgeGroup? _groupForAge(
    List<ListeningContentAgeGroup> groups,
    int childAge,
  ) {
    if (groups.isEmpty) return null;
    for (final group in groups) {
      if (childAge >= group.startAge && childAge <= group.endAge) return group;
    }
    return groups.reduce((current, candidate) {
      int distance(ListeningContentAgeGroup group) {
        if (childAge < group.startAge) return group.startAge - childAge;
        if (childAge > group.endAge) return childAge - group.endAge;
        return 0;
      }

      return distance(candidate) < distance(current) ? candidate : current;
    });
  }

  int _matchScore({
    required String query,
    required String english,
    required String vietnamese,
  }) {
    if (query == english || query == vietnamese) return 1000;
    if (english.startsWith(query) || vietnamese.startsWith(query)) return 800;
    if (english.contains(query) || vietnamese.contains(query)) return 650;

    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return 0;
    final candidateTokens = <String>{
      ..._tokens(english),
      ..._tokens(vietnamese),
    };
    final overlap = queryTokens.where(candidateTokens.contains).length;
    if (overlap == 0) return 0;
    if (queryTokens.length > 1 && overlap < queryTokens.length) return 0;
    return 300 + overlap * 30;
  }

  Set<String> _tokens(String value) =>
      value.split(' ').where((token) => token.length >= 2).toSet();

  String _normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('đ', 'd')
      .replaceAll(RegExp('[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
      .replaceAll(RegExp('[èéẹẻẽêềếệểễ]'), 'e')
      .replaceAll(RegExp('[ìíịỉĩ]'), 'i')
      .replaceAll(RegExp('[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
      .replaceAll(RegExp('[ùúụủũưừứựửữ]'), 'u')
      .replaceAll(RegExp('[ỳýỵỷỹ]'), 'y')
      .replaceAll(RegExp("[^a-z0-9']+"), ' ')
      .trim();
}
