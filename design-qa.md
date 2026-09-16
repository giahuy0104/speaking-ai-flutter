# HOMI Option 2 — Design QA

## Result

Pass for the requested visual redesign. Final open findings: P0 0, P1 0, P2 0, P3 1.

The implementation applies the selected option-2 visual grammar across the current native Flutter surfaces: navy for primary actions and navigation, hot pink for selection/progress/recording, and mint-white for backgrounds and supporting surfaces. Existing product flows and content remain intact.

## Visual truth and captures

- Visual source of truth: `C:\Users\Windows\.codex\generated_images\019fac05-f74f-7952-9259-e708249b6185\exec-525673cd-cb5a-458c-9069-a82108d61810.png`
- Source board: 1490 × 1056 px, light theme.
- Native implementation captures: 390 × 844 logical px, light theme, idle communication, selected age 6–7, and vocabulary landing states.
- Final side-by-side comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\design-qa-option2-overview.png`
- The implementation captures were normalized to 1056 px height only for the combined comparison; no screenshot was stretched inside the app.

## Full-view comparison

Reviewed source and implementation in the same 1490 × 2112 comparison image. The final pass confirms:

- navy hierarchy is consistent across CTAs, arrows, MAIN and selected navigation;
- pink is restricted to stateful emphasis instead of becoming the page background;
- mint-white scenery keeps all three screens bright and gender-neutral;
- vocabulary uses open rows and separators instead of repeated framed cards;
- setup uses the same two-column radio form and visual hierarchy as the selected concept;
- mascot, supporting copy and CTA do not overlap at the 390 × 844 native viewport;
- conversation waveform is long, visible and integrated with the selected palette.

## Focused-region evidence

The full comparison is large enough to inspect the three critical regions without separate crops:

1. Conversation waveform and primary microphone CTA.
2. Setup progress, two-column age selector, information notice, mascot and CTA.
3. Vocabulary illustration rows, separators, counters, arrow buttons and bottom navigation.

## Iteration log

| Severity | Finding | Resolution | Status |
| --- | --- | --- | --- |
| P1 | A whole-screen color filter made the conversation screen appear magenta. | Removed the filter and implemented a responsive mint/pink waveform directly in the shared voice component. | Fixed |
| P2 | The conversation hero asset carried an opaque white rectangle. | Replaced it with a true-alpha version of the approved hero artwork. | Fixed |
| P2 | Vocabulary retained too many rounded cards. | Rebuilt the landing content as open full-width rows with subtle mint separators. | Fixed |
| P2 | Setup initially used a single-column selector and the mascot overlapped the information panel. | Moved to the two-column radio layout and reserved explicit mascot space above the CTA. | Fixed |
| P1 | Narrow waveform instances overflowed in H20 and lesson states. | Made every waveform bar flex to available width. | Fixed |
| P1 | Settings overflowed at 320 px width with 200% text. | Stacked section trailing status when needed, allowed status labels to wrap, and changed the language control to a wrapping choice layout at large text sizes. | Fixed |
| P3 | Some line wraps and illustration sizes differ from the concept board because the implementation preserves real copy and a 390 × 844 native viewport. | Accepted as responsive adaptation; hierarchy, palette and interaction targets remain aligned. | Accepted |

## Verification

- `flutter analyze`: passed with no issues.
- Golden suites for conversation, home, all three setup steps, settings/history, lesson flow and karaoke: passed.
- Home, onboarding, settings, vocabulary, display-language and 200%-text accessibility tests: passed.
- Android debug package: built successfully at `build\app\outputs\flutter-apk\app-debug.apk`.
- iOS shares the same Flutter presentation layer; an IPA/TestFlight archive still requires Xcode on macOS.

## Waveform motion QA — continuous translation and listening lessons

- Source visual truth path: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-6caf2c55-c8a4-4ed1-ba28-e46e3d325eb1.png`.
- Rendered implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\listening\goldens\lesson-practice-390x844.png`.
- Combined focused comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\waveform-motion-reference-vs-implementation.png`.
- Viewport and density: implementation 390 × 844 logical px at 1×; source 112 × 79 px; combined comparison 1120 × 540 px. The implementation crop is 350 × 300 px and both sides were resized proportionally without stretching.
- State: light-theme sentence-practice card. The static capture shows the shared mint/pink waveform styling; runtime motion uses a continuously repeating 2.2-second phase.
- Full-view evidence: the native 390 × 844 screenshot keeps the original lesson hierarchy, primary recording action, bottom navigation and readable spacing without new containers or overflow.
- Focused-region evidence: the combined comparison puts the supplied card and the rendered Flutter card in one image. Copy, mint/pink waveform, playback actions, rounded treatment and visual emphasis align; the implementation remains sharper at native density.
- Motion evidence: `processing_status_test.dart` samples three independently phased bars for 24 consecutive 16 ms frames, confirms visible travel, and caps the largest one-frame height change below 3.5 logical px. `lesson_flow_golden_test.dart` confirms the lesson sample waveform is always active. `accessibility_resilience_test.dart` confirms reduced-motion users retain a stable static waveform.
- Findings: P0 0, P1 0, P2 0. The only intentional difference is higher native rendering clarity than the compressed source thumbnail.
- Comparison history: the earlier implementation advanced the wave in 420 ms steps, leaving a visible pause between interpolations (P2 motion polish). It was replaced with Flutter's frame-synchronized animation controller, continuous sine phase, and a light secondary ripple. The post-fix 16 ms cadence test, navigation suite, accessibility test and full lesson golden suite pass.

## Non-design test note

The isolated test `virtual lesson buttons interrupt the current recording and change sentence` currently expects recording to have started immediately but observes `false`. The visual changes in `lesson_practice_screen.dart` only alter colors, not recording startup logic, so this behavior was not changed as part of the redesign.

## Dark mode adaptation QA

### Visual truth and captures

- Source visual truth: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\home\goldens\home-communication-390x844.png`, the approved option-2 light composition.
- Rendered implementation: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\home\goldens\dark-home-communication-390x844.png`.
- Same-screen comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\dark-home-reference-vs-implementation.png`.
- Full dark UI review board: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design-qa\homi-dark-mode-overview.png`.
- Viewport and density: both source and dark implementation are 390 × 844 logical/pixel px at 1×. The side-by-side canvas is 800 × 884 px and neither screen was rescaled.
- State: idle communication screen. The theme intentionally differs; geometry, content, hierarchy and interaction state are the direct comparison surfaces while color is evaluated as an option-2 dark adaptation.

### Full-view comparison evidence

- The approved header, mascot hero, waveform, translation area, CTA and five-item bottom navigation retain their original proportions and reading order.
- The dark version uses a deep navy scenic canvas rather than pure black, with two surface elevations and preserved illustration color.
- Blue, pink and mint keep the same semantic jobs as light mode: primary actions/navigation, voice/selection emphasis and positive/audio states.
- The seven-screen overview confirms the same rules on Home, Vocabulary, Topics, Settings and all three Setup steps. No persistent control is clipped or pushed below the 390 × 844 viewport.

### Focused-region evidence

The 1× side-by-side file is sufficient to inspect the critical text, waveform, translation surface, CTA and bottom navigation. The full overview additionally exposes the setup controls, vocabulary rows, topic journey and settings controls at one consistent scale, so no separate crop was required.

### Required fidelity surfaces

- Fonts and typography: Roboto family, hierarchy, weights, wrapping and line height remain unchanged; light-on-dark text uses the semantic `onSurface` roles.
- Spacing and layout rhythm: no frame, padding, radius or vertical-position changes were introduced for dark mode.
- Colors and visual tokens: canvas `#07172F`, surfaces `#0B2146`/`#123055`, primary `#A9C7F5`, pink `#FF79AA`, mint `#71D8BE`, primary text `#F7FBFF`, secondary text `#C2CEE0`.
- Image quality and asset fidelity: the approved HOMI mascot, topic and vocabulary assets are unchanged; only the scenery receives a navy readability overlay.
- Copy and content: unchanged across themes.
- Accessibility: tested text combinations meet at least 4.5:1; primary body text exceeds 7:1. Reduced-motion behavior remains supported by the shared waveform.

### Dark iteration history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P1 | Vocabulary titles, setup CTA text and some dialog copy inherited light-only navy and became difficult to read. | Replaced fixed foregrounds with semantic dark roles and added explicit dark CTA foregrounds. | Dark Vocabulary and all three Setup screens on the overview board. |
| P2 | The first dark scenery pass remained too bright and grey, weakening the dark-mode distinction. | Increased the navy overlay while preserving the cloud, hill and flower silhouettes. | Home, Vocabulary and Topics captures now share a calm deep-navy lower field. |
| P2 | Success/status accents and metadata chips used light-theme fills or low-contrast green. | Remapped shared status pills, badges, history chips and settings controls to dark mint/raised surfaces. | Settings capture and shared token contrast test. |
| P2 | The MAIN button and vocabulary arrows used a dark light-theme fill against the dark navigation/screen. | Switched interactive dark controls to the light-blue primary with navy foreground. | Home, Vocabulary and Topics captures. |

### Verification

- Primary interactions exercised: switch theme immediately, navigate Home → Vocabulary → Topics, and advance through all three Setup steps.
- Dark golden captures: Home, Vocabulary, Topics, Settings, Setup Privacy, Setup Profile and Setup Permissions.
- `flutter analyze`: passed with no issues.
- Dark semantic contrast test: passed.
- Dark home/setup/settings golden tests: passed.

No actionable P0, P1 or P2 findings remain. Minor platform-specific text rasterization differences between Android and iOS are acceptable and do not change layout or contrast.

final result: passed

## Home communication — compact side tabs and waveform

### Visual truth and captures

- Source visual truth paths: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-3e0e34a9-aad5-4891-9801-16545d869f3a.png` for the retained Home composition, `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-f35cc085-cfcd-49b8-9da7-1847af4b4090.png` for the side-tab treatment only, and `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-ea6a1e97-77b9-4332-afac-20d5ba735877.png` for the mint/pink waveform palette.
- Source pixels: 859 × 1908 px, 300 × 650 px, and 1171 × 365 px respectively.
- Rendered implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\home\goldens\home-communication-390x844.png`.
- Same-input comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\home-side-tabs-wave-20260916\reference-vs-implementation.png`.
- Viewport and density: Flutter 390 × 844 logical/pixel px at device-pixel ratio 1, Vietnamese, light theme, idle state. The comparison preserves each source's aspect ratio inside equal padded cells.

### Full-view comparison evidence

- The implementation keeps the current HOMI header, scenic background, mascot, title, supporting copy, translation sections and primary speaking action; it does not copy the alternate center-card or floating Main treatment from reference 3.
- The compact navy Vocabulary rail and purple Topic rail reuse only reference 3's two-edge navigation treatment. Their 44 × 142 px visual bounds remain outside the center copy and result area.
- The five-item bottom navigation is absent. Its recovered height keeps the Vietnamese and English result sections plus the speaking action visible together at 390 × 844.
- The waveform is reduced to 238 × 46 px on compact screens while retaining the approved mint and hot-pink bar pattern.

### Focused-region evidence

The four-cell comparison keeps the two edge rails, waveform, result copy and removed bottom-navigation region readable in one input. A separate crop was unnecessary.

### Required fidelity surfaces

- Fonts and typography: the existing Roboto hierarchy, weights, wrapping and Vietnamese copy are unchanged; both translation labels and placeholders are fully visible.
- Spacing and layout rhythm: the left rail begins 32 px above the right rail, matching the staggered reference treatment; the smaller waveform and removed navigation restore clear vertical breathing room without shrinking the result copy.
- Colors and visual tokens: Vocabulary uses existing HOMI navy, Topic uses the approved purple, and the waveform uses `AppColors.mint` plus `AppColors.accentPink`.
- Image quality and asset fidelity: the approved transparent HOMI mascot, cloud blob and scenic background assets are reused at native quality. No screenshot crop, placeholder, or code-drawn replacement was introduced.
- Copy and content: “Từ vựng”, “Chủ đề”, “Câu tiếng Việt”, “Câu tiếng Anh” and the existing Home instructions remain intact.

### Comparison history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P1 | The five-destination bottom navigation consumed the lower viewport and could leave the English sentence below the fold on the target device. | Removed the Home shell bottom navigation and retained History/Settings in the header plus Vocabulary/Topic on the edge rails. | Final 390 × 844 Home golden. |
| P2 | Vocabulary and Topic were available only in the bottom navigation, contrary to the selected side-tab treatment. | Restored the two edge rails and reduced them from 47 × 224 px to 44 × 142 px. | Final four-cell comparison, bottom-right panel. |
| P2 | The 330 × 68 px compact waveform remained too dominant. | Reduced it to 238 × 46 px and locked the mint/pink bars with widget assertions. | Final Home golden and waveform component tests. |
| P1 | Showing the rails over the Vocabulary landing obscured its first card. | Scoped the edge rails to the Home communication page; tapping the HOMI identity returns from Vocabulary as before. | Updated Vocabulary golden with unobstructed cards. |

### Verification

- Primary interactions tested: Home → Vocabulary → Home, Home → Topic, header History/Settings, and the hardware MAIN path after removal of the on-screen bottom action.
- Responsive and accessibility coverage: 390 × 844 goldens plus the existing 200% text, narrow-screen and reduced-motion resilience test.
- Scoped `flutter analyze`: passed with no issues across all changed source and test files.
- Widget, navigation, golden and accessibility suites: 33 tests passed.
- Full-repository analysis remains affected only by two pre-existing diagnostics in `output\apk\recheck-vocabulary-choice_test.dart`; the changed files are clean.
- Browser console checks are not applicable to these native Flutter widget captures.

No actionable P0, P1 or P2 findings remain. The 44 px edge rails intentionally follow the compact visual reference while retaining working semantic button labels.

final result: passed

## Vocabulary HOMI learning stage — selected premium mock-up

### Visual truth and captures

- Source visual truth path: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-e47d5dee-d9c1-468e-b87f-de7b65e4acfa.png`.
- Source pixels: 853 × 1844 px, normalized proportionally to 390 × 844 px for comparison.
- Rendered implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\vocabulary\goldens\vocabulary-practice-homi-390x844.png`.
- Same-state comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-selected-homi\comparison-reference-vs-implementation.png`.
- Additional journey captures: `vocabulary-family-homi-390x844.png` and `vocabulary-stars-homi-390x844.png` in the same golden directory.
- Viewport and density: Flutter 390 × 844 logical/pixel px at device-pixel ratio 1, Vietnamese, light theme, initial idle state.

### Full-view comparison evidence

- The selected hierarchy is preserved: compact back/title row, count pill, slim pink progress, elevated white word card, helper copy, one combined “Nghe và nói lại” action, and a dedicated HOMI stage in the lower landscape.
- The implementation uses the user-approved smaller “Luyện lại” title rather than copying the oversized generated type.
- The new vocabulary-only scenic asset raises the layered hills and flowers so the lower half is intentional rather than empty.
- Review uses the listening HOMI, Parent Added uses the welcoming/waving HOMI, and Stars uses the singing HOMI. During active recording, Review switches to the speaking HOMI without changing the one-button interaction.
- Parent Added and Stars keep their existing listen-only behavior. No microphone practice was invented for those journeys.

### Focused-region evidence

The 800 × 890 side-by-side comparison keeps the header, card, CTA, mascot stage and lower landscape readable at the same normalized density. Separate focused crops were unnecessary. The two journey goldens confirm the distinct HOMI assets beside their existing actions.

### Required fidelity surfaces

- Fonts and typography: Roboto regular/bold are loaded in the captures; title, vocabulary, helper and CTA hierarchy match the selected direction without truncation.
- Spacing and layout rhythm: 18px screen gutters, 30px card radius, 58px primary action, responsive 132/180/232px mascot slots, and safe scrolling on short displays.
- Colors and tokens: navy, pink, mint and warm white remain mapped to the existing HOMI theme tokens; the selected visual introduces no competing palette.
- Image quality and assets: the new high-resolution landscape is used as a real raster asset, while transparent production HOMI assets remain sharp and state-aware.
- Copy and content: “Luyện lại”, “1/1”, “At noon.”, “Buổi trưa.”, “Con nghe kỹ rồi nói lại nhé.” and “Nghe và nói lại” match the selected state.

### Comparison history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P2 | The shared scenery left most of the lower screen empty and placed the hills below the mascot stage. | Added a vocabulary-specific premium landscape with raised layered hills and flowers. | Final side-by-side comparison. |
| P2 | The first HOMI render was too small relative to the selected mock-up. | Increased the responsive mascot slot while retaining short-screen breakpoints. | Final 390 × 844 golden and 360 × 720 widget coverage. |
| P2 | The initial idle helper displayed the longer review introduction instead of the selected instructional sentence. | Kept the spoken intro behavior but changed the idle on-screen copy to “Con nghe kỹ rồi nói lại nhé.” | Final golden capture. |

### Verification

- `flutter analyze` on both vocabulary screens and all related tests: passed with no issues.
- Vocabulary widget and golden suite: 21 tests passed.
- Primary interactions tested: combined listen-then-record, HOMI listening-to-speaking state change, retry flow, completion routing, three journey entrances, and collection-specific HOMI identity.
- Golden captures pass at 390 × 844; the existing narrow-screen suite passes at 360 × 720 without RenderFlex overflow.
- Browser console checks are not applicable to these native Flutter widget captures.

Remaining P3 difference: the generated mock-up depicts a seated listening pose with a decorative audio ribbon; the implementation intentionally reuses the approved transparent HOMI listening asset and omits the ribbon to keep animation/runtime assets light and consistent across Android and iOS.

final result: passed

## Vocabulary option 1 — Journey landing and Review practice

### Visual truth and captures

- Selected source visual: `D:\CodexData\.codex\generated_images\01a0a829-468e-7111-811c-c286440a7aca\exec-006b3c6b-f3cb-4a6d-a5a0-098cc0b06b5a.png`.
- Final user override: remove the speaker control from inside the vocabulary card and use one combined “Nghe và nói lại” action below it. The earlier two-action interpretation is superseded.
- Rendered implementation screenshots: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-option1-applied\landing-390x844.png` and `practice-single-action-390x844.png`.
- Focused same-state comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-option1-applied\comparison-single-action-source-vs-implementation.png`.
- Capture density: 1× at 390 × 844. The narrower 360 × 720 Android target remains covered by the responsive widget suite.

### Full-view comparison evidence

- The landing screen follows the selected option-1 hierarchy: compact HOMI identity row, restrained 27–29sp title, subtitle, and three independent white journey cards with illustration, live count, and navy arrow.
- The practice screen keeps the selected compact header, count pill, slim pink progress and elevated word card, followed by one 286 × 58 combined action.
- The card contains only the English word and Vietnamese meaning. No speaker icon, secondary audio action or “Về Main” action remains below it.
- “Luyện lại” is 25–28sp and protected by a single-line responsive header rather than the earlier oversized treatment.
- The 360 × 720 render keeps every action visible without clipping, overlap, or a forced scroll at initial state.

### Focused-region evidence

The focused comparison places the exact user-provided button crop beside the rendered disabled/busy state. Both use the same blue-grey fill, white microphone icon, bold white label, rounded geometry and pale mint background. The full-screen capture verifies its position below the word card.

### Required fidelity surfaces

- Typography: Roboto, navy hierarchy, 27–29sp landing title, 22sp journey labels, and 25–28sp practice title.
- Spacing and geometry: 16–20px narrow-screen gutters, 110–116px journey cards, 26–30px card radii, and one 286 × 58 action with a 22px radius.
- Color: existing HOMI navy, pink, mint and scenic background tokens are reused; the change introduces no parallel palette.
- Image quality: the existing family, golden-star, review-book, HOMI avatar, and scenery assets are reused at high filter quality.
- Interaction: tapping “Nghe và nói lại” plays the English sample and Vietnamese meaning, then automatically opens the microphone. During playback the action uses the blue-grey disabled state shown in the reference.
- Accessibility: the combined learning action remains a native button with a 58px target; the widget test confirms that no separate listen/speak/Main buttons or nested card speaker remain.

### Comparison history

| Severity | Finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P2 | The first rendered landing inherited vertical centering and left excessive space between HOMI and the page title. | Top-aligned the landing content and applied responsive 36/56px top spacing. | Final landing 390 × 844 capture. |
| P2 | The first interpretation split the requested flow into “Nghe mẫu” and “Giữ để nói” and added “Về Main”. | Replaced all three with the single native “Nghe và nói lại” CTA shown in the user’s clarification. | Focused source-versus-implementation comparison. |
| P2 | The generated option still showed a speaker button inside the card after the user removed it from scope. | Treated the user instruction as the authoritative override and omitted the card control. | Final full-screen practice capture. |

### Verification

- Primary interactions tested: combined listen-then-record flow, retry-after-no-response, completion routing, and all three journey entrances.
- `flutter analyze` on the two vocabulary screens and their tests: passed with no issues.
- `flutter test test/features/vocabulary/vocabulary_home_screen_test.dart test/features/vocabulary/vocabulary_practice_screen_test.dart`: 18 tests passed.
- Visual capture check: the 390 × 844 busy/disabled state generated with no Flutter exceptions or RenderFlex overflow.
- Browser console checks are not applicable to this native Flutter implementation.

No actionable P0, P1 or P2 findings remain. The single combined CTA and absent in-card speaker are intentional user-approved deviations from the generated mock-up.

final result: passed

## Vocabulary detail option 2 — Stars and Review

### Visual truth and captures

- Source visual truth path: `D:\CodexData\.codex\generated_images\01a0a829-468e-7111-811c-c286440a7aca\exec-44df4373-6dad-4782-8ee2-2aea80cf7fd2.png`.
- Source pixels: 1296 × 1222 px; the board contains the selected 390 × 844 mobile direction for both Review and Stars.
- Rendered implementation screenshots: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-option2\review-390x844.png` and `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-option2\stars-390x844.png`.
- Implementation viewport: 390 × 844 logical/pixel px at device-pixel ratio 1.
- Combined same-view evidence: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-vocabulary-option2\comparison-source-vs-implementation.png`.
- State: Vietnamese, light theme, three realistic items in each collection, idle playback.

### Full-view comparison evidence

- Both implemented detail screens preserve the selected option-2 hierarchy: compact identity area, rounded detail header, navy primary CTA and three separate warm-white word cards.
- The Review and Stars screens use the same header, CTA width, card geometry, icon treatment and status-chip placement.
- Search, add and delete controls are absent from both detail screens. They remain available on the vocabulary landing and Parent Added flow.
- The title treatment intentionally differs from the generated reference: the approved follow-up requested smaller text. The implementation uses 24sp and drops to 22sp at narrow widths, with scale-down protection and no ellipsis. “Ngôi sao của con” remains fully visible.
- The isolated detail captures omit the shell-owned bottom navigation. Existing navigation remains owned and rendered by `HomeLearningShell`; the implementation keeps 110px bottom scroll padding so list content is not obscured when composed in the full app.

### Focused-region evidence

The combined board is large enough to inspect the title row, count chip, CTA and all six word-card examples at readable scale, so a separate crop was not required. Focused review confirms full title rendering, 44–48px controls, distinct word cards, mint status chips and aligned speaker actions.

### Required fidelity surfaces

- Fonts and typography: Roboto is loaded in the capture; English rows use bold navy hierarchy, Vietnamese translations use muted text, and responsive titles use 22–24sp as explicitly requested.
- Spacing and layout rhythm: 16px narrow-screen gutters, 10px card gaps, 20–22px radii, 52px CTA height and 110px bottom content padding are consistent across both collections.
- Colors and visual tokens: existing HOMI navy, mint, off-white and scenery tokens are retained; no new palette was introduced.
- Image quality and asset fidelity: the existing HOMI penguin and option-2 scenery assets are reused without approximation or replacement.
- Copy and content: “Luyện lại”, “Ngôi sao của con”, “Bắt đầu luyện”, “Bắt đầu nghe”, “Cần luyện” and “Yêu thích” match the approved direction.
- Responsiveness and accessibility: automated widget coverage passes at 360 × 720 and 390 × 844; titles do not truncate, no RenderFlex overflow occurs, and interactive targets remain at least 44px.

### Comparison history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P2 | The first implementation reused the shared scenic panel shadow, making the lower card edge heavier than the selected mock-up. | Replaced it with a lighter navy-tinted shadow and a thin translucent border for detail headers and individual cards. | Final combined comparison board. |
| P2 | The original detail layout exposed search/add controls, a disabled trash action and a 27sp ellipsized title on Stars and Review. | Scoped those actions to landing/Parent Added, removed the destructive affordance from Stars/Review, and introduced the responsive 22–24sp header. | Final Review and Stars captures plus the 360 × 720 widget test. |

### Verification

- Primary interactions tested: enter Stars, return, enter Review, return, enter Parent Added, and verify control visibility per collection.
- `flutter analyze lib/features/vocabulary/presentation/vocabulary_home_screen.dart test/features/vocabulary/vocabulary_home_screen_test.dart`: passed with no issues.
- `flutter test test/features/vocabulary/vocabulary_home_screen_test.dart`: 13 tests passed.
- Native visual capture test: both 390 × 844 screenshots generated successfully with no Flutter exceptions or layout overflows.
- Browser console checks are not applicable to this native Flutter widget capture.

No actionable P0, P1 or P2 findings remain. The smaller title and stacked count chip are intentional responsive adaptations approved by the user.

final result: passed

## Parent Added — saved content before waiting queue

### Visual truth and captures

- Source visual truth paths: `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-161a4d54-648f-4893-9356-27dc9db3aae6.png` and `C:\Users\Windows\AppData\Local\Temp\codex-clipboard-b20ff57b-73bf-463d-b726-9a9cf2d3da07.png`.
- Source pixels: both references are 859 × 1908 px and include Android system chrome. They were proportionally contained in 390 × 844 panels for the structural comparison; no app-owned element was stretched.
- Rendered implementation screenshot: `C:\Users\Windows\Documents\ai-speaking-flutter-app\test\features\vocabulary\goldens\vocabulary-family-homi-390x844.png`.
- Combined comparison: `C:\Users\Windows\Documents\ai-speaking-flutter-app\output\design\homi-parent-added-reordered\comparison-request-vs-implementation.png` (1190 × 900 px).
- Implementation viewport: 390 × 844 logical/pixel px at device-pixel ratio 1, Vietnamese, light theme, one saved item and one waiting item.

### Full-view comparison evidence

- The redundant “Hôm nay” section is absent.
- Parent search and add controls remain available only in the Parent Added journey.
- Saved-content count, listening action and saved vocabulary panel now appear before the waiting queue.
- The waiting queue remains editable and deletable, but is visually subordinate to learned/saved content.
- The saved-content panel keeps its large empty-state presentation when no saved content exists and collapses to its natural height when entries are present, so the queue is not pushed below an unnecessary blank area.

### Focused-region evidence

The three-column comparison shows the crossed-out original Today section, the requested saved-content block, and the final reordered Flutter screen together. Text, controls and queue actions remain readable at the normalized size, so a separate crop was not required.

### Required fidelity surfaces

- Fonts and typography: Roboto regular, medium and bold are loaded; Vietnamese diacritics render correctly in saved and waiting content.
- Spacing and layout rhythm: search/add, saved count, HOMI action, saved content and queue use consistent 12–18px vertical rhythm; populated content no longer inherits the 330px empty-state minimum height.
- Colors and visual tokens: existing navy, mint and off-white tokens are unchanged.
- Image quality and assets: the approved HOMI waving asset and scenery remain unchanged and sharp.
- Copy and content: “Hôm nay” is removed; “nội dung đã lưu” and “Hàng chờ” remain explicit and correctly ordered.

### Comparison history

| Severity | Earlier finding | Fix | Post-fix evidence |
| --- | --- | --- | --- |
| P2 | “Hôm nay” duplicated the parent-content experience and appeared before the saved library. | Removed the Today presentation block while preserving the underlying daily-learning data flow. | Final family golden and three-column comparison. |
| P2 | The first reorder kept a 330px minimum height for populated saved content, pushing the queue almost entirely below the viewport. | Applied the large minimum height only to the true empty state; populated lists now size to content. | Final 390 × 844 implementation capture. |

### Verification

- Primary flow tested: open Parent Added, confirm Today is absent, confirm saved content precedes the waiting queue, and retain queue edit/delete actions.
- `flutter analyze` on the changed screen and tests: passed with no issues.
- Related vocabulary suite: 21 tests passed.
- Native golden capture: passed at 390 × 844 with no RenderFlex overflow.
- Browser console checks are not applicable to this native Flutter widget capture.

No actionable P0, P1 or P2 findings remain.

final result: passed
