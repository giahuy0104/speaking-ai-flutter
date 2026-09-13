import 'listening_content.dart';

/// Defines the stable Star slots that belong to one authored lesson.
///
/// The redesigned flow awards Stars only for Core sentences. Challenge and
/// Song completion never create Star slots.
abstract final class LessonStarFlow {
  static Set<String> expectedStarIds(ListeningLessonContent lesson) => {
    for (final sentence in lesson.sentences) 'core:${sentence.id}',
  };

  static int remainingStarCount(
    ListeningLessonContent lesson,
    Set<String> earnedStarIds,
  ) {
    final expected = expectedStarIds(lesson);
    return expected.difference(earnedStarIds).length;
  }
}
