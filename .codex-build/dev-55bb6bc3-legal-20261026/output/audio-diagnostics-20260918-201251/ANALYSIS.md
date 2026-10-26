# Android/H20 diagnostic results — 2026-09-18

Capture: `device.log`, SHA256 `030C2D0A1C286E8D8C2BEACE96B9786C3A94FC5EA512C095003B51F6A8124019`.
Manual interaction events: approximately 21:28:04–21:30:25 Asia/Bangkok.
The earlier startup at 20:12 is also present. Capture process 1804 was verified
as this device's adb logcat and stopped after the user reported completion.
Native diagnostic logging was disabled with log.tag.HomiDiag=INFO.
No behavioral fix was made during this analysis.

## Navigation and audio readiness are separate

| Destination | Command received to dispatch | Dispatch to frame marker | Total |
| --- | ---: | ---: | ---: |
| Topics, first entry | 10 ms | 54 ms | 64 ms |
| Topics, next selection | 5 ms | 27 ms | 32 ms |
| Vocabulary | 33 ms | 30 ms | 63 ms |

Evidence: lines 53–68, 105–111, 279–302. Topic markers are the first
post-init frame; vocabulary marker is the frame after activation, not the end
of its PageView animation. These metrics start when the controller receives
the recognized command, not when the user physically stops speaking.

All three navigation dispatches occurred before the subsequent destination
prompt. This sample does not reproduce a seconds-long prompt-completion-to-UI
delay and does not validate the earlier assumption that release blocked navigation.

Across 20 coordinated prompt/cue operations, scoped release took 0–1 ms.
Some scopes had no selected route, or another scope still retained HFP;
scoped release is not equivalent to physically disconnecting Bluetooth.
Six native stops took 43, 49, 34, 57, 147 and 108 ms.
Fourteen native prompt completions reached the Dart delegate in 8–37 ms.
No `main.prompt.timeout` occurred. Three navigations are insufficient for P95 claims.

## Confirmed multi-second wait: reopening HFP

- Lines 71–74: start 21:28:19.169 -> route ready 21:28:23.044 = 3,875 ms.
  A delayed SCO disconnect causes a route re-assertion. Topic first frame had
  already occurred at 21:28:19.141. Prompt starts at 21:28:23.223.
- Lines 289–302: vocabulary dispatch at 21:29:59.170; stop completes .253;
  restart .262 -> ready 21:30:02.314 = 3,052 ms; prompt starts .925.
  Dispatch-to-prompt-start is 3,755 ms, while UI frame marker took 30 ms.
- Lines 332–343: next vocabulary turn stops HFP and reopens it in 2,667 ms.

These events support investigating ownership handoff and unnecessary
stop/restart at module transitions. Removing an awaited prompt cleanup is
not supported as the primary fix by this capture.

Two lesson prompts also wait 2,246 ms and 2,066 ms between delegate start
and native TTS synthesis request (lines 123–126 and 134–137). This is a
pre-synthesis delay, not TTS synthesis time. Synthesis plus player preparation
then takes 732 ms and 552 ms. Exact attribution requires source correlation
or additional remote-asset/cache events. Source correlation confirms Android
sets `remoteAudioLoadTimeout` to 2 seconds in `voice_prompt_service.dart:29`.
`main_assistant_audio_prompt_service.dart:265` waits for remote bytes before
falling back to TTS. These durations fit that policy, but no remote timeout
event was recorded, so this remains a supported hypothesis rather than proof.

## Cue accounting

Six delegate requests, six channel requests, six native starts and six native
completions. MAIN owns IDs 1, 2, 5, 6; listeningLesson owns IDs 3, 4.
There is no duplicate application request in this sample. Native retry of
ToneGenerator.startTone is not separately instrumented, and system/H20
generated sounds are outside these counters.

All starts report stream=0, sco=true, communicationDeviceType=7 and deviceId=8190.
MAIN starts report mode=0; lesson starts report mode=3. The different modes
warrant investigation but do not prove which physical speaker emitted the
tone. No acoustic recording or actual ToneGenerator output-device callback
was collected. A duplicate sound heard by the user cannot be ruled out.

## Volume

Prompt playback requests gainMb=1200 (+12 dB); lesson media requests +8 dB;
recording playback requests +28.5860754566205 dB (including vocabulary).
At the native prompt/cue snapshots, system Media=15/15 and Voice Call=11/11.
There is no sampled user-volume change explaining the inconsistency.
Different requested gains are confirmed; perceived loudness, source LUFS,
limiter behavior and physical speaker levels were not measured here.

## Additional events and limits

- SpeechRecognizer reports "not connected to the recognition service" during
  two cleanup transitions (lines 287, 330); both navigation/next prompt flows
  continue. This is not evidence of the main delay by itself.
- At 21:30:25, SCO disconnect, BLUETOOTH_DISABLED and profile disconnect follow
  recording playback. The log cannot distinguish user disabling Bluetooth
  from another cause without the user's account of that step.
- Earlier BLE GATT connection attempts time out before the active test.

Suggested priority: preserve HFP ownership across MAIN/module handoff;
investigate pre-TTS remote audio wait; unify gain policy after loudness
measurement; correlate the user's ting observation before changing cue logic.
