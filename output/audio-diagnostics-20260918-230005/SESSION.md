# Android audio fix v2 device test

- Device: Redmi 23054RA19C / ORH6S4ZT85BMWGSK.
- Package: com.innotrik.aispeaking, 1.0.8+10; updated in place (data preserved).
- Installation confirmed: 2026-09-18 22:59:51, local time.
- Native startup confirmed in device.log: build=audio-fix-v2.
- APK SHA-256: 0C64CA237FB15FB2CF8C3C1BA494D25380263F500393F42754F02979F1538743.
- Capture process 6692 was verified as this device's adb logcat and stopped
  after the user reported completion. Native log.tag.HomiDiag was reset to INFO.
- Frozen log: 182,485 bytes; SHA-256
  5E927C8C0AB963D480CC8C0CF57ABE5662EDB55AE3B3B94FAAE96857A1D44BC1.
- Results: see ANALYSIS.md in this directory. No further app-code edits or
  installation were performed during this analysis turn.
- Flutter regression: 187 passing tests; lib analysis clean; release APK build successful.
- Native unit results: 24 passed, zero failures/errors, including 12 loudness
  and 2 cue-waveform tests. See ../audio-fix-native-tests-final.log.

Changes under test: command endpoint finalization with final-result grace;
offline fixed-menu audio; 750 ms HFP handoff with immediate release for explicit
phone output; shared bounded per-file RMS matching; single Android cue call site
and one WAV MediaPlayer cue without ToneGenerator retry.

Test internal topic number selection (including 1 vs 10), Vocabulary Stars,
Parent-added and Review. Compare both screen response and next prompt/mic readiness.
Check prompt, lesson, own-recording and cue loudness on the same route/volume.
Note the exact step and audible device if two tings occur.

After the user reports finished: verify PID 6692 is still this capture, stop
only it, set log.tag.HomiDiag back to INFO, and analyze this directory's device.log.
Do not clear logcat or overwrite the original 20:12 baseline capture.

Limitations: this is gated RMS -21 dBFS, not LUFS/true-peak normalization.
Unmeasurable/long files and failed TTS-file synthesis can retain fallback levels.
No physical/acoustic loudness or elimination of Android/H20 system tones has yet
been verified; do not infer those outcomes from one app cue API call.
