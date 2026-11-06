# Topic lesson screen-lock capture, 2026-11-05

Device: vivo 1919, application PID 12104, package com.innotrik.aispeaking.
Local phone timestamps, UTC+07. Source: device.log and audio-during.txt.

## Measured events

- 15:35:54.616 activity paused; 15:35:54.908 SCREEN_OFF broadcast.
- Recognition sessions continued at 15:36:01 and 15:36:12 with the application attributed as their caller.
- 15:36:38.788 SCREEN_ON broadcast; activity resumed at 15:36:42.131.
- App recorder stopped at 15:36:38.883. Preferred communication route became null at 15:36:39.693, with setCommunicationDevice attributed to application PID 12104. Bluetooth SCO was selected again at 15:36:39.796 and confirmed by a Bluetooth event at 15:36:40.128.
- App AudioTrack player 95223 started at 15:36:40.377: 1.494 seconds after the recorder stopped. This is before the activity resumed, so this interval cannot be attributed solely to the Flutter resumed callback. The system log does not identify the recording filename or lesson phase.
- 15:36:44.661 activity paused; 15:36:45.089 SCREEN_OFF broadcast. App MediaPlayer 95239 started at 15:36:45.014, and MediaPlayer 95247 started at 15:36:47.216: playback continued across screen-off.
- Recorder stopped again at 15:36:54.285. stopBluetoothSco was attributed to application PID at 15:36:54.265; SCO became unselected at 15:36:54.746 and was reselected at 15:36:55.133. App AudioTrack 95263 started at 15:36:55.696: 1.411 seconds after capture stopped, while the screen remained off.
- Earlier commentary estimated the second interval as 1.71 seconds from a voice-activity event. The player-start measurement is 1.411 seconds and is the appropriate value for this report.

## Assessment and limits

Confirmed: recording-to-playback handoffs include SCO route changes and approximately 1.4–1.5 seconds before the app player starts. The current logs do not separate recorder finalization, normalization, history persistence, route confirmation, and playback preparation within that interval. They do not prove that a screen transition caused capture to stop or that the clip restarted from its beginning.

Foreground service remained running; final power dump shows the app ActiveLesson partial wake lock held while the screen is asleep. No app crash/ANR was found in this capture.

Code review: HomeLearningShell._handleAppLifecycleState intends to keep learning alive when Android reports the screen is not interactive. LessonMediaService.stopRecording awaits recorder.stop, recording normalization and optional history persistence. Playback then awaits output preparation and selected HFP route activation. Its recorder config already disables record-plugin Bluetooth management. Do not assume that plugin configuration is the cause without a call-level trace.

No HOMI_DIAG Dart or HomiDiag native events were emitted in this capture despite enabling log tags. A diagnostic build with timing around lifecycle decisions, recorder stop, normalization, history persistence, route start/stop callers, and player start is needed to assign the exact cause and safely choose a code fix.

Capture stopped and temporary log properties restored. No application source changes were made.
