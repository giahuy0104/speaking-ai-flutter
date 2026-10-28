import '../../../features/vocabulary/data/vocabulary_session_store.dart';
import '../../../l10n/display_language.dart';

/// Input data for VocabularyPracticeScreen; services and callbacks stay in presentation.
class VocabularyPracticeArguments {
  const VocabularyPracticeArguments({
    required this.language,
    required this.childAge,
    required this.session,
    this.announceIntro = true,
    this.announceResume = false,
  });

  final DisplayLanguage language;
  final int childAge;
  final VocabularyPracticeSession session;
  final bool announceIntro;
  final bool announceResume;
}
