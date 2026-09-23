import 'vocabulary_entry.dart';

/// Precomputed vocabulary collections used by the vocabulary landing page.
///
/// Building these collections includes filtering, review de-duplication and
/// sorting. Keeping the result immutable lets UI rebuilds reuse the same lists
/// instead of repeating that work while a page transition is animating.
class VocabularyJourneyIndex {
  VocabularyJourneyIndex._({
    required this.family,
    required this.stars,
    required this.review,
  });

  factory VocabularyJourneyIndex.fromEntries(Iterable<VocabularyEntry> source) {
    final family = <VocabularyEntry>[];
    final stars = <VocabularyEntry>[];
    final reviewByTarget = <String, VocabularyEntry>{};

    for (final entry in source) {
      if (entry.isUnlockedParent) {
        family.add(entry);
      }
      if (entry.isStar &&
          entry.source == VocabularySource.topicCore &&
          (entry.correctAudioPath?.trim().isNotEmpty ?? false)) {
        stars.add(entry);
      }
      if (_isActiveReviewEntry(entry)) {
        final target = _normalize(entry.word);
        final previous = reviewByTarget[target];
        if (previous == null ||
            (entry.isParentAdded && !previous.isParentAdded)) {
          reviewByTarget[target] = entry;
        }
      }
    }

    family.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    stars.sort(
      (a, b) => (a.earnedAt ?? a.addedAt).compareTo(b.earnedAt ?? b.addedAt),
    );
    final review = reviewByTarget.values.toList(growable: false)
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));

    return VocabularyJourneyIndex._(
      family: List<VocabularyEntry>.unmodifiable(family),
      stars: List<VocabularyEntry>.unmodifiable(stars),
      review: List<VocabularyEntry>.unmodifiable(review),
    );
  }

  factory VocabularyJourneyIndex.empty() =>
      VocabularyJourneyIndex.fromEntries(const <VocabularyEntry>[]);

  final List<VocabularyEntry> family;
  final List<VocabularyEntry> stars;
  final List<VocabularyEntry> review;

  static bool _isActiveReviewEntry(VocabularyEntry entry) =>
      entry.needsPractice &&
      !entry.isParentAdded &&
      !(entry.sourceLessonCode?.startsWith('LEGACY-V41:') ?? false);

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[\s.,!?;:…_-]+"), ' ')
      .trim();
}
