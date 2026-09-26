# H20 audio routing verification — 2026-09-18

Scope: Android audio output ownership, playback cancellation, and Bluetooth route-loss handling only. No lesson content, scoring rules, navigation rules, permissions/consent UI, backend configuration, or history schema changes.

## Observed on connected phone

- Xiaomi 23054RA19C, Android 13; application `com.innotrik.aispeaking`.
- H20 is exposed as an HFP/SCO headset, device port 4035. The captured device inventory did not contain an A2DP output.
- Before the fix, app PID 17664 stopped HFP at 01:37:10.693 and created a MEDIA audio track at 01:37:11.256. Similar sequences occurred at 01:37:19–20 and 01:37:31. This explains connected Bluetooth with phone playback: connected profile did not imply an active SCO output.
- Initial patched APK installed at 02:00:13 with `adb install -r`. Application `ceDataInode=1244129` was unchanged, confirming replacement without clearing the data directory.
- Post-install PID 21705: native MediaPlayer and ExoPlayer AudioTrack outputs both used `USAGE_VOICE_COMMUNICATION` and routed to device 4035. The 02:01:36–43 recording completed and produced the expected normalized mono WAV.
- Extended QA found an additional OEM edge case: at 02:02:11.727 Xiaomi's system AudioDeviceBroker initiated SCO closure. The app's communication-device callback arrived only at 02:02:13.987; an active track briefly reported phone device 2 before pausing at 02:02:14.047. This was not counted as a successful final verification.

## Corrections

- Dedicated HFP output scopes for Android MAIN and translation prompts, held until awaited playback completes.
- Selected-output failure or loss cancels the pending prompt, including an authored clip still loading; HFP errors are not converted into phone TTS fallback.
- Each Android player owns its audio attributes rather than inheriting another feature's global session configuration.
- Stop/dispose invalidates queued playback, delayed cache/source loads, and stale preparation work.
- Recorder no longer restores an old AudioManager mode over the HFP bridge; native route reuse verifies communication mode.
- Follow-up native fix addresses missing/late Bluetooth audio-disconnect events. Android documents that Bluetooth privileged-process broadcasts need an exported receiver: [Android broadcast guidance](https://developer.android.com/develop/background-work/background-tasks/broadcasts). The receiver remains restricted to the existing protected headset actions and selected-device checks.

## Automated checks

- Focused suite: 134 passing tests (`h20-routing-focused-tests.log`).
- Extended regression suite: 226 passing tests (`h20-routing-regression-tests.log`), including 8 routing tests also covered in the focused run. Total: 360 passing test executions, 352 distinct tests.
- Static analysis of 10 changed Dart files: no issues (`h20-routing-analysis.log`).
- Initial release build and APK signature verification passed. Production defines and existing legal URLs were preserved; the local release uses the existing Android Debug certificate, not a store production-signing certificate.

Final native follow-up build and device verification are recorded below when completed. Physical listening quality cannot be established from routing logs alone.
