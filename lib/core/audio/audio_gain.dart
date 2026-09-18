/// Fallback only, used when Android cannot measure a source before playback.
/// Measurable local sources instead use AndroidPlaybackLoudness's gated PCM
/// level policy. A common fallback avoids a different fixed boost per player.
const double androidSpeechBoostDb = 8.0;

const double androidAssistantSpeechBoostDb = androidSpeechBoostDb;

/// Bound positive gain even for very quiet recordings. Digital attenuation for
/// loud sources is applied separately through the player's volume control.
const double androidMaxPlaybackGainDb = 12.0;

/// Recorded attempts use the same measured playback policy as authored speech.
/// Do not stack the old fixed +28.6 dB boost on top of source normalization.
/// Original recording/scoring bytes remain unchanged.
const double lessonRecordingPlaybackGainDb = androidSpeechBoostDb;
