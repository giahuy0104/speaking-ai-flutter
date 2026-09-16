/// Shared Android speech boost for lesson audio and assistant prompts,
/// including both device TTS and bundled authored audio. Keep a single value
/// so every speech playback path stays in sync.
const double androidSpeechBoostDb = 8.0;

/// Child recordings are naturally quieter than mastered lesson clips. Four
/// extra decibels is roughly a 58% amplitude lift over regular speech playback.
const double lessonRecordingPlaybackGainDb = 12.0;
