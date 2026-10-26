import '../../../features/listening/domain/listening_catalog.dart';
import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

/// Input data for LessonIntroScreen; services and callbacks stay in presentation.
class LessonIntroArguments {
  const LessonIntroArguments({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    this.topicContent,
    this.contentGroup,
    this.levelContent,
    this.autoAdvance = true,
    this.relearnFromBeginning = false,
    this.relearnTopicSequence = false,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ListeningTopicContent? topicContent;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final bool autoAdvance;
  final bool relearnFromBeginning;
  final bool relearnTopicSequence;
}
