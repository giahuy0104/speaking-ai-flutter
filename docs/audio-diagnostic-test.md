# Android audio/navigation diagnostic test

The initial capture instrumented existing behavior. The follow-up test build
also changes Android cue ownership, bounded source-level matching, offline
menu prompt loading and HFP handoff. Compare against the preserved initial
capture rather than treating the new build as instrumentation-only.

Build with the existing production configuration and add
`--dart-define=HOMI_AUDIO_DIAGNOSTICS=true`. Native events are enabled on the
test phone by `adb shell setprop log.tag.HomiDiag DEBUG`. Disable them after
testing with `adb shell setprop log.tag.HomiDiag INFO`.

Run `tool/start_audio_diagnostic_capture.ps1` to start a detached local
logcat capture. Keep USB connected. The script prints the process ID and
unique output directory. Stop only that capture process after the user
finishes; preserve `device.log` for analysis.

## Reading the timeline

- `speech.final`, `main.command.received/resolved`: recognition and command resolution.
- `main.prompt.prepare/budget_ready`: authored lookup and preparation.
- `prompt.lease.request/acquired`: shared audio ownership wait.
- `prompt.route.start.request/completed`: selected HFP activation.
- `prompt.native.started/audio_completed`: native player timeline; completion includes file silence.
- `prompt.delegate.completed`: platform playback future completed.
- `prompt.route.release.request/completed`, `hfp.stop.*`: cleanup latency.
- `main.handoff.*`, `main.native_end.*`: remaining controller barriers.
- `navigation.dispatch/handler.completed`: UI handler invocation and return.
- `screen.topics.first_frame`: first frame after topic state initialization; not data-ready.
- `screen.vocabulary.activation_frame`: frame following activation; not animation completion.
- `main.cue.request`: MAIN call site and generation.
- `cue.delegate`: coordinated owner.
- `cue.channel.request/completed`, `cue.native.start/complete`: bridge calls and native cue ID.
- `media.gain.request`, `media.play.*`: media owner, requested gain and start delay.
- `media.level.applied`, `prompt.level.applied`: effective source gain and whether
  a complete-file measurement was available.
- `hfp.handoff.retained/expired`: short idle HFP lease between adjacent owners.
- `prompt.audio.bundled/remote.wait`: offline source versus network fallback.
- `cue.native.routed`: actual MediaPlayer output device when Android reports it.

Compare `utcMs` across Dart and Kotlin. Their monotonic clocks have different
origins and must not be subtracted from each other. Use operation IDs, native
prompt/cue IDs and chronological order to correlate events. A controller
generation is a cancellation epoch, not a unique command ID.

Native output snapshots report communication device, mode, SCO state and
Media/Voice Call volume settings. They are not physical output measurements
or proof of acoustic volume. New events omit transcript text and audio
bytes; existing Flutter/system logs may contain their normal diagnostics.

## Manual scenarios

1. With H20 connected, navigate to Topics and Vocabulary using MAIN voice commands.
2. Repeat each transition at least three times, noting waits after spoken confirmation.
3. Trigger prompts, lesson audio, recording playback and ready cues; note volume changes.
4. Note the exact step and actual speaker whenever a duplicate or misplaced cue is heard.
5. Within Topics, say a topic number, including 1 and 10. Within Vocabulary,
   select Stars, Parent-added and Review; compare both UI response and the wait
   until the next spoken prompt/microphone is ready.
6. Repeat with H20 and phone output separately, including cancel/restart and
   a disconnected H20. Do not judge loudness across routes with different
   system volume settings.

The source-level target is gated RMS −21 dBFS with sample peaks no higher
than −1 dBFS after linear gain, not certified −21 LUFS/true-peak normalization.
Complete local clips up to 30 seconds use a bounded native meter; unsupported,
long or slow-to-decode clips use a common bounded fallback. Recordings used
for scoring are not modified. Real-device loudness and any recognizer/H20
system beep still require listening checks.

Follow-up automated validation: 187 focused Flutter speech/audio/navigation
tests and 24 Android native unit tests passed. Release APK built and installed;
`flutter analyze --no-pub lib` passed. Whole
repository analysis also finds unrelated pre-existing issues in `tool/` and
`output/apk/`.
