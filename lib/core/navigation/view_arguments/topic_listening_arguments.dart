import '../../../features/listening/application/listening_voice_navigation_target.dart';
import '../../../l10n/display_language.dart';

/// Input data for TopicListeningScreen; services and callbacks stay in presentation.
class TopicListeningArguments {
  const TopicListeningArguments({
    required this.language,
    required this.childAge,
    this.initialVoiceTarget,
  });

  final DisplayLanguage language;
  final int childAge;
  final ListeningVoiceNavigationTarget? initialVoiceTarget;
}
