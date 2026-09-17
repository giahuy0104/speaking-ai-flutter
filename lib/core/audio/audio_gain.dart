/// Android boost for authored lesson audio such as the English/Vietnamese
/// sentence and lesson-opening clips.
const double androidSpeechBoostDb = 8.0;

/// Android boost for assistant speech played by the native voice-prompt
/// bridge. That pipeline is quieter than lesson media at the same requested
/// gain, so use the bridge's supported 12 dB ceiling to match their perceived
/// volume without raising the already-loud lesson clips.
const double androidAssistantSpeechBoostDb = 12.0;

/// Highest gain that Android's playback pipeline may request from its
/// LoudnessEnhancer. Child recordings intentionally need more gain than the
/// authored samples, while this ceiling still bounds accidental values.
const double androidMaxPlaybackGainDb = 24.0;

/// Raises child-attempt replay by 2.5x in linear amplitude compared with the
/// previous 15.52 dB setting. This only affects the child's recording replay;
/// authored English/Vietnamese samples keep [androidSpeechBoostDb].
const double lessonRecordingPlaybackGainDb = 23.480625354554377;
