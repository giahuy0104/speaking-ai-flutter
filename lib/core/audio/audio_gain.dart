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
const double androidMaxPlaybackGainDb = 30.0;

/// An additional 80% linear amplitude (20 * log10(1.8), or 5.105 dB) above
/// the previous child-recording replay setting of 23.480625354554377 dB.
/// This is playback-only: saved originals and scoring audio are not rewritten.
/// Android's LoudnessEnhancer compresses peaks outside the sample range, so
/// this is a target gain, not a promise of 80% more loudness on every device.
/// Authored English/Vietnamese samples keep [androidSpeechBoostDb].
const double lessonRecordingPlaybackGainDb = 28.5860754566205;
