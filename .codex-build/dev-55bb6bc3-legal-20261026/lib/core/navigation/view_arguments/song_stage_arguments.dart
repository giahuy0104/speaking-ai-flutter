import '../../../l10n/display_language.dart';

/// Input data for V4SongStageScreen; services and callbacks stay in presentation.
class SongStageArguments {
  const SongStageArguments({
    required this.language,
    required this.songTitle,
    this.songAudioId,
    this.songAudioUri,
  });

  final DisplayLanguage language;
  final String songTitle;
  final String? songAudioId;
  final Uri? songAudioUri;
}
