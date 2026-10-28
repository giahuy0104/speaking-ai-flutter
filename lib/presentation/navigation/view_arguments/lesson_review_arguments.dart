import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

enum LessonReviewMode { overview, learned }

/// Input data for LessonReviewScreen; services and callbacks stay in presentation.
class LessonReviewArguments {
  const LessonReviewArguments({
    required this.language,
    required this.lesson,
    this.unrecordedSentenceIndexes = const <int>{},
    this.mode = LessonReviewMode.learned,
    this.hasNextLesson = false,
  });

  final DisplayLanguage language;
  final ListeningLessonContent lesson;
  final Set<int> unrecordedSentenceIndexes;
  final LessonReviewMode mode;
  final bool hasNextLesson;
}
