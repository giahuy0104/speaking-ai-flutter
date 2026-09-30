/// Fallback only, used when Android cannot measure a source before playback.
/// Measurable local sources instead use AndroidPlaybackLoudness's gated PCM
/// level policy. A common fallback avoids a different fixed boost per player.
const double androidSpeechBoostDb = 8.0;

const double androidAssistantSpeechBoostDb = androidSpeechBoostDb;

/// What iOS has to take off synthesised speech to reach the shared target.
///
/// Android measures every synthesised utterance before playing it and only
/// falls back to [androidSpeechBoostDb] when that measurement fails. iOS has no
/// equivalent, so its prompts played at whatever the synthesiser produced. That
/// went unnoticed while the authored catalogue was uneven too — but now that
/// every bundled clip is pulled to the manifest's target, uncorrected speech
/// sits noticeably above them.
///
/// Measured with `AVSpeechSynthesizer.write` and the same gated-RMS policy as
/// `tool/measure_audio_loudness.py`: the compact vi-VN and en-US voices need
/// between -3.7 and -6.5 dB to reach the target, median -5.1. Attenuation is
/// all that is needed, which is the one thing `AVSpeechUtterance.volume` can
/// do.
const double iosAssistantSpeechGainDb = -5.0;

/// H20 microphone captures can sit more than 20 dB below authored speech.
/// Source metering still chooses the actual gain and attenuates loud clips, but
/// it needs the full LoudnessEnhancer range to bring quiet captures to target.
const double androidMaxPlaybackGainDb = 28.0;

/// Fallback for a child recording when Android cannot finish source metering.
/// Android lesson WAVs are already raised to the speech target when saved
/// (`normalizeLessonWavLoudness`), so an unmeasured replay plays them as saved.
/// Measurable recordings still use the common gated level target.
const double lessonRecordingPlaybackGainDb = 0.0;
