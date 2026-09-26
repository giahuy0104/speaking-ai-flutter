import 'package:flutter/foundation.dart';

import 'audio_prompt_key.dart';

enum AudioOutputRoute { defaultOutput, selectedMediaOutput, phoneSpeaker }

enum AudioPlaybackStyle { standard, assistant, lesson, feedback }

@immutable
final class AudioPromptRequest {
  const AudioPromptRequest({
    required this.key,
    required this.fallbackText,
    required this.locale,
    this.outputRoute = AudioOutputRoute.defaultOutput,
    this.playbackStyle = AudioPlaybackStyle.standard,
    this.timeout = const Duration(seconds: 20),
    this.allowTtsFallback = true,
  }) : assert(timeout > Duration.zero);

  final AudioPromptKey key;
  final String fallbackText;
  final String locale;
  final AudioOutputRoute outputRoute;
  final AudioPlaybackStyle playbackStyle;
  final Duration timeout;
  final bool allowTtsFallback;
}
