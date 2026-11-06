# Rejected device experiments and restoration

2026-11-05, vivo 1919, local UTC+07 timestamps.

Both candidate optimizations were rejected after physical testing:

- VOICE_RECOGNITION source: user reported faster foreground response but loss of recording/replay with the screen off; source6 log includes takes with no speech and no level samples. Removed source option and restored VOICE_COMMUNICATION.
- Bounded silent SCO output: user reported replay failure both with screen on/off. The helper did start, but did not prevent actual SCO loss. At17:00:13.409 helper starts; recorder stops13.706; replay prepares13.753; route loss14.477; generic playback-cancel error14.524; native route recovers15.476. Same pattern repeats. Recording file normalization and history had already completed.

Likely error path, independently reviewed by two agents: HFP loss increments the playback request generation during pending route preparation; current-playback check raises a generic cancellation exception before the HFP-specific retry can proceed. This explains the candidate regression; it does not establish the original SCO teardown's origin.

Audio mode stayed IN_COMMUNICATION during one failure; a mode reset is not supported as its immediate cause. Cached and compiled record_android2.1.2 stop code does not explicitly release Bluetooth for the configured recording mode. No evidence warrants removing route validation, changing shared lifecycle, or moving history persistence as the main fix.

Restoration: adb install -r output/diagnostics/topic-handoff-measured/baseline.apk succeeded. Package lastUpdateTime17:02:53. Data was not cleared. This is the diagnostic baseline that successfully recorded/replayed before experiments.

All functional experiment source changes and tests were removed from active source. Rejected patch and helper source copies are retained in this folder for investigation. Active diff is only17 lines of timing diagnostics in LessonMediaService. git diff --check passes. No latency fix is accepted or complete.

Next evidence needed: confirm restored screen-on/off recording/replay, then identify the exact route-loss status/generation and triggering Android route command before designing another functional change. Existing candidate automated tests passed but did not establish hardware behavior; device failures take precedence.
