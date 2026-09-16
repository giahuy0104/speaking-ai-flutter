/// Shared Android speech boost for lesson audio and synthesized assistant
/// prompts. Keep a single value so the two playback paths stay in sync.
const double androidSpeechBoostDb = 8.0;

/// Highest gain that Android's playback pipeline may request from its
/// LoudnessEnhancer. Child recordings intentionally need more gain than the
/// authored samples, while this ceiling still bounds accidental values.
const double androidMaxPlaybackGainDb = 24.0;

/// Raises child-attempt replay by 2.5x in linear amplitude compared with the
/// previous 15.52 dB setting. This only affects the child's recording replay;
/// authored English/Vietnamese samples keep [androidSpeechBoostDb].
const double lessonRecordingPlaybackGainDb = 23.480625354554377;
