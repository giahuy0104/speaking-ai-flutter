import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

/// Input data for LessonChallengeScreen; services and callbacks stay in presentation.
class LessonChallengeArguments {
  const LessonChallengeArguments({
    required this.language,
    required this.startAge,
    required this.lesson,
    required this.challenges,
  });

  final DisplayLanguage language;
  final int startAge;
  final ListeningLessonContent lesson;
  final List<ListeningChallengeContent> challenges;
}
