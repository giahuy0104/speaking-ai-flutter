# Registered navigation validation — 2026-10-21

Baseline commit: `26fadd0bd424143102806156ead5a4abc3dd2603`. Baseline source was extracted into a separate temporary folder; the working tree was never reverted. Runs used the same Flutter SDK, assets and privacy test defines.

## Final results

- Registered-route regression: **822 passed, 29 failed**.
- Original baseline suite: 811 passed / 28 failed; the two additionally included test files (`accessibility_resilience_test.dart` and `app/homi_connection_presentation_test.dart`) produce 4 passed / 1 failed on baseline. The union of all 29 failing test names is identical to the final registered-route run. No new failing test was observed.
- Focused core routing, active-learning navigation and guided lesson flow: **122 passed** after fixing initialRoute intermediate-path probing.
- Dart analyzer: no issues. `git diff --check`: clean.
- Actual AiSpeakingApp test asserts MaterialApp.onGenerateRoute is configured and Topics receives the expected route name and typed input.
- Core tests cover named dispatch, lazy dependency evaluation, synchronous route installation, typed pop and replacement results, Android/iOS paused initialization, bottom-sheet Back behavior, nearest nested Navigator, unnamed continuation and invalid requests.
- Existing Home/Settings tests cover live theme updates while the registered sheet is open. The broad suite also exercises learning navigation, vocabulary, automatic connection, startup, partial connection recovery and settings/device behavior.

## Preservation checks

All 17 typed page/sheet dispatch sites retain the same input, dependency and callback expressions as the preceding adapter implementation. The original migration also checked the 15 screen constructors against HEAD. The shared active-learning factory body and MAIN observer are unchanged; only the factory's name/visibility was opened for reuse. No service or BLE retry code was edited.

All 24 failed-golden rendered test images are byte-identical between baseline and the registered-route run. Existing golden reference images were not updated. Baseline failures remain visible; these results do not imply the complete suite is green.

These are local automated tests with simulated Android/iOS lifecycle states. No physical Bluetooth/device test, APK installation or deep-link/browser-history validation was performed in this turn.

## Failures also present on baseline

- `test/app/device_connection_action_app_test.dart: BLE alone does not let the Home speaking action through (variant: TargetPlatform.android)`
- `test/app/device_connection_action_app_test.dart: Cancel rejects a late scan candidate and a new action can retry immediately (variant: TargetPlatform.android)`
- `test/app/device_connection_action_app_test.dart: Home action observes native retry failure and Cancel reaches native (variant: TargetPlatform.android)`
- `test/app/device_connection_action_app_test.dart: Retry starts a fresh native scan and unsuccessful completion shows guidance (variant: TargetPlatform.android)`
- `test/app/device_connection_action_app_test.dart: a stuck native scan releases Retry after the requested-round deadline (variant: TargetPlatform.android)`
- `test/app/device_connection_action_app_test.dart: background HFP retry resumes after Cancel on the existing 15-second tick (variant: TargetPlatform.android)`
- `test/features/home/home_learning_shell_golden_test.dart: dark communication matches the approved rail treatment`
- `test/features/home/home_learning_shell_golden_test.dart: dark home keeps the approved option two composition`
- `test/features/home/home_learning_shell_golden_test.dart: disconnected home matches the approved navy tabs`
- `test/features/home/home_learning_shell_golden_test.dart: home communication matches image one`
- `test/features/home/home_learning_shell_golden_test.dart: small disconnected home keeps both tabs readable with large text`
- `test/features/listening/lesson_flow_golden_test.dart: English-only lesson review matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: V4 completion opens an authored voice challenge`
- `test/features/listening/lesson_flow_golden_test.dart: favorite food journey matches the selected HOMI direction`
- `test/features/listening/lesson_flow_golden_test.dart: friendly reminder popup matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: lesson intro matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: recording praise fireworks match the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: sentence practice matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: song journey uses English-first titles and music markers`
- `test/features/listening/lesson_flow_golden_test.dart: topic lesson journey matches the approved direction`
- `test/features/listening/lesson_guide_flow_v2_test.dart: uses the required pauses for the bilingual sentence guide`
- `test/features/listening/song_karaoke_screen_test.dart: karaoke screen matches the selected visual direction`
- `test/features/settings/history_sheet_test.dart: empty history keeps the shared HOMI visual system`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: parent suggestion selection stays visually quiet`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: parent-added journey uses the welcoming HOMI`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: review journey uses the navy anchor tile`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: review practice HOMI stage at 390x844`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: stars journey uses the singing HOMI`
- `test/accessibility_resilience_test.dart: main flow supports 200 percent text, small screens and reduced motion` — expects the removed Settings label “Dữ liệu và quyền riêng tư”; the same assertion fails on baseline.

## Build and evidence

Android debug APK built successfully (40.3 seconds). No installation performed. Build uses `--dart-define-from-file=dart_defines.production.json`; no configuration secrets are copied into documentation.

Evidence: `HOMI/docs/session-artifacts/2026-10-21-registered-routes/`.


## Follow-up: Settings as a full page

Settings now uses a registered regular MaterialPageRoute and full-screen Scaffold.
History remains a bottom sheet. Closing Settings does not emit the learning-exit
notification. The original Settings content/controller, parent gate, device
cancellation, voice pause/resume and MAIN visibility callback are retained.

97 focused tests pass across the core router, Home, Settings appearance/device
flows and actual AiSpeakingApp device integration. New coverage verifies the
full 390×844 page bounds, no outer BottomSheet, retained nested language picker,
Close/system Back returning to Home, balanced visibility callbacks, typed page
result without learning exit, and floating MAIN hidden in actual app Settings.
The existing live-theme and microphone deselection/retry tests also pass.
Analyzer and diff checks are clean. Physical-device validation is not included.
Evidence: `HOMI/docs/session-artifacts/2026-10-21-settings-page/`.

Android debug APK rebuilt successfully (53.1 seconds) using the existing production dart-defines file. No installation performed.


## Follow-up: horizontal navigation animations

Default page transition now slides from right to left in 300 ms, in both themes.
Home Vocabulary uses reversed PageView direction while retaining logical indices
and its mounted state. Topics uses a full-width slide with its existing 260 ms
route duration. Background routes remain zero duration; reduced motion skips
horizontal animation.

Final regression: **831 passed, 29 failed**. The failing test-name set is identical
to the previously verified baseline; no new failing test remains. Seven new
animation test variants measure horizontal positions during entrance/exit on
Android/iOS, both themes, reduced motion, and actual Home Vocabulary/Topics.
Four existing tests were adjusted to wait for pages to finish entering before
interacting or checking route removal. Assertions and business expectations were
preserved. Analyzer and diff checks pass. No golden reference was updated.
Evidence: `HOMI/docs/session-artifacts/2026-10-21-navigation-slide/`.

Android debug APK rebuilt successfully using the existing production dart-defines file; not installed on a device.
