/// Shared Android speech boost for lesson audio and synthesized assistant
/// prompts. Keep a single value so the two playback paths stay in sync.
const double androidSpeechBoostDb = 8.0;

/// Highest gain that Android's playback pipeline may request from its
/// LoudnessEnhancer. This leaves enough headroom for quiet child recordings
/// while keeping accidental values bounded.
const double androidMaxPlaybackGainDb = 18.0;

/// Child recordings were previously played at 12 dB. Adding
/// 20 * log10(1.5) dB raises their linear amplitude by exactly 50% relative to
/// that existing level.
const double lessonRecordingPlaybackGainDb = 15.521825181113627;
