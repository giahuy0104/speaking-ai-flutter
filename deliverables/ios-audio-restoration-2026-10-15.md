# Audio restoration on the iOS performance branch

- Target branch: `perf/ios-audio-off-main-2026-10-12`, based on `1ee8e745`.
- Requested source: work performed in this chat on 14 October, 17:27–22:15 (UTC+7), saved in the `c9dd8eb4..f94c70e3` change set.
- Implementation workspace: `C:/Users/DELL/.codex/worktrees/ios-audio-restore/speaking-ai-flutter`.
- Original workspace and its two uncommitted files were not modified.

## Conflict decisions

- Retained the target branch's existing no-Level curriculum, ten-topic selection, progress persistence and course-relearn flow. Its API differs from the source implementation but already implements the requested navigation model.
- Preserved native iOS off-main-thread audio/device bridges, prompt-player preparation, MAIN-to-lesson activation gates, and review-to-translation handoff. No changes to `ios/`, `lib/core/`, home-shell or voice-navigation implementation.
- Imported the source recordings and metadata, including the three updated hooks and thirteen intro-lead recordings. Verified all 814 source-change MP3 files byte-for-byte against `f94c70e3`.
- Intro sequence is keyed lead audio, existing hook audio, then the recorded start cue. TTS remains an error fallback.
- Matched the topic-picker prompt text to the supplied recording so text-hash validation can select the MP3.
- Removed duplicate topic prompt keys introduced by the three-way merge; retained target manifest versions and target-only prompts.
- Rebuilt the audio-pack index and audit reports. Kept the target's existing gain/playback architecture; did not reintroduce the absent `audio_loudness.json` subsystem. The optional lead-composition tool supports branches without that subsystem.
- Excluded Gradle lock files and Python bytecode from the source change set.
- Updated the audio-identity test's approved recording hashes. Curriculum, topic patch, lexicon and songs retain their original hashes.

## Verification

- `flutter analyze --no-pub lib test tool`: no issues.
- Focused intro, hook, topic-picker, content-identity and audio-index suites: 155 passed.
- Initial broader run: 907 passed, five failed. One failure was the intentionally outdated audio-identity snapshot, updated and then verified by the focused suite.
- The remaining four failures were reproduced on the unmodified `1ee8e745` baseline: three `lesson_flow_golden_test.dart` screenshot cases and `silent topic selection resumes the same Level when MAIN is pressed again` in `voice_navigation_controller_test.dart`. They are not regressions introduced by this restoration. No golden images or unrelated voice behavior were changed to hide them.
- Reran the broader suite excluding exactly those four baseline failures: 908 passed.
- No iOS build or physical-device playback verification was performed on Windows.
- Implementation was handed off uncommitted; the user subsequently requested commit and push to the target branch.

The temporary baseline-check worktree remains available because the app refused archival as a protected/pinned workspace.
