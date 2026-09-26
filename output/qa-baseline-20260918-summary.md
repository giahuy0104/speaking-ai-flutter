# Baseline comparison for topic fixes

Source baseline: `239ba6fc3a342a00e5ec6e0f36946dd70fb12391` (HEAD).

The baseline used `git archive HEAD` for `lib`, `test`, `pubspec.yaml`, `pubspec.lock`, and `analysis_options.yaml`, with the existing unchanged assets linked by a directory junction. Offline dependency resolution succeeded. No working source or golden references were changed for this comparison. The snapshot was subsequently moved from `output/qa-baseline-20260918` to ignored `tmp/qa-baseline-20260918`; paths embedded in logs identify the original test location.

Six selected baseline test files finished with **39 passed, 13 failed**. All 13 failing test descriptions exactly match the failures in `qa-topic-fixes-20260918-tests.log`. The seven golden failures also have identical pixel difference counts and percentages. The remaining diagnostics match: three pending-timer failures in Home shell, two missing-widget failures in Vocabulary home, and the missing Chinese label in display language.

Logs:

- `qa-baseline-20260918-selected-tests.log`
- `qa-baseline-20260918-today-back-test.log`

Baseline command:

```text
flutter test --no-pub --reporter expanded --timeout 30s test/display_language_test.dart test/features/home/home_learning_shell_test.dart test/features/home/home_learning_shell_golden_test.dart test/features/vocabulary/vocabulary_home_screen_test.dart test/features/vocabulary/vocabulary_practice_golden_test.dart test/golden_conversation_screen_test.dart
```

The isolated HEAD test `system Back cannot leave an unfinished Today session` also stalled after starting, matching the working-tree full-suite observation. Its command used `--timeout 30s`, but this did not interrupt the widget test's blocked await; the runner was cancelled manually after approximately 30 seconds. A subsequent process inspection found no remaining matching Dart or Flutter test process. This is a reproduced baseline hang, not a passing test or a test-runner timeout result.

```text
flutter test --no-pub --reporter expanded --timeout 30s test/features/vocabulary/vocabulary_practice_screen_test.dart --plain-name "system Back cannot leave an unfinished Today session"
```

Failing descriptions shared by HEAD and working tree:

1. language setting changes display text only and hides backend URL
2. dark home keeps the approved option two composition
3. iOS keeps header, side navigation, and hardware MAIN flow
4. opens vocabulary, returns to communication, and opens topics
5. system Back closes vocabulary detail before leaving the tab
6. leaving the vocabulary tab stops active collection audio
7. MAIN vocabulary prompt failure is handled and can retry
8. parent-added journey uses the welcoming HOMI
9. stars journey uses the singing HOMI
10. idle screen keeps the compact hero above the fold
11. processing screen uses the waveform instead of a spinner
12. ready result screen keeps the scenic communication layout
13. topic listening screen matches the selected mobile direction
