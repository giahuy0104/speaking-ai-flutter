import '../../../features/listening/domain/listening_content.dart';
import '../../../l10n/display_language.dart';

/// Input data for SongKaraokeScreen; services and callbacks stay in presentation.
class SongKaraokeArguments {
  const SongKaraokeArguments({
    required this.language,
    required this.lesson,
    required this.topicTitle,
  });

  final DisplayLanguage language;
  final ListeningLessonContent lesson;
  final String topicTitle;
}
