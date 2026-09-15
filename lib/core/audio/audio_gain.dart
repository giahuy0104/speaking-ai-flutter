/// Shared Android speech boost for lesson audio and synthesized assistant
/// prompts. Keep a single value so the two playback paths stay in sync.
const double androidSpeechBoostDb = 8.0;

/// Child recordings are naturally quieter than mastered lesson clips. Four
/// extra decibels is roughly a 58% amplitude lift over regular speech playback.
const double lessonRecordingPlaybackGainDb = 12.0;
