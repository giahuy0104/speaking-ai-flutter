import '../../../features/listening/domain/listening_catalog.dart';
import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

/// Input data for TopicLessonListScreen; services and callbacks stay in presentation.
class TopicLessonsArguments {
  const TopicLessonsArguments({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.content,
    this.contentGroup,
    this.levelContent,
    this.initialLessonNumber,
    this.relearnInitialLesson = false,
    this.relearnTopicSequence = false,
    this.songsOnly = false,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningTopicContent content;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final int? initialLessonNumber;
  final bool relearnInitialLesson;
  final bool relearnTopicSequence;
  final bool songsOnly;
}
