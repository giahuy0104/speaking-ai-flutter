/// Fallback only, used when Android cannot measure a source before playback.
/// Measurable local sources instead use AndroidPlaybackLoudness's gated PCM
/// level policy. A common fallback avoids a different fixed boost per player.
const double androidSpeechBoostDb = 8.0;

const double androidAssistantSpeechBoostDb = androidSpeechBoostDb;

/// H20 microphone captures can sit more than 20 dB below authored speech.
/// Source metering still chooses the actual gain and attenuates loud clips, but
/// it needs the full LoudnessEnhancer range to bring quiet captures to target.
const double androidMaxPlaybackGainDb = 28.0;

/// Fixed gain for replaying a child recording. Lesson recordings are brought
/// to `lessonRecordingTargetDbfs` when saved (`normalizeLessonWavLoudness`,
/// the iOS native normalizer), so replays play them as saved: source metering
/// would pull them back down to the authored-prompt target.
const double lessonRecordingPlaybackGainDb = 0.0;
