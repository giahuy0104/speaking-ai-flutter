import '../../../features/listening/data/listening_progress_store.dart';
import '../../../features/listening/domain/listening_catalog.dart';
import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

/// Input data for LessonPracticeScreen; services and callbacks stay in presentation.
class LessonPracticeArguments {
  const LessonPracticeArguments({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    this.topicContent,
    this.contentGroup,
    this.levelContent,
    this.initialResumeStage = ListeningResumeStage.core,
    this.isRelearn = false,
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
  final ListeningResumeStage initialResumeStage;
  final bool isRelearn;
  final bool relearnTopicSequence;
}
