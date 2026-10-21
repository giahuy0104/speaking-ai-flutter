# HOMI onboarding implementation QA — 2026-10-21

final result: passed

## Scope and evidence
Native Flutter production implementation; this is not a browser prototype. User approved implementation of the three-step design, with fixed bottom actions and the supplied MAIN Bluetooth icon. No physical-device verification was performed in this turn.

Source visual truth directory: `/Users/quangonfire/.codex/generated_images/01a15239-933b-76e1-aa96-453a34861e43/`:
- Setup: `exec-940e5fca-2a41-4a81-b66d-0667316deb11.png` (1497×1051).
- Connection: `exec-07b71f35-3afa-4700-bacf-47adaefb46d0.png` (1496×1051).
- Results: `exec-19d2c0f6-5c33-487a-8d26-161332c44bb6.png` (1497×1051).
- Icon: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-onboarding-design/main-bluetooth-icon-reference.png`.

Implementation captures: `test/features/onboarding/goldens/startup-{first-privacy,profile,permissions,bluetooth-off,device-powered,searching,failed,partial,ready,partial-permission,limited}-390x844.png`. Also four corresponding dark-theme captures. Each actual Flutter capture is 390×844 pixels, 390×844 logical pixels at DPR 1. No CSS viewport applies.

Full-view comparison evidence: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-onboarding-implementation/{setup,connect,result}-comparison.png`. Source board above, three native captures below. Source board normalized proportionally to approximately 1202×844; native captures retain original 390×844 dimensions. Board gutters and source illustration proportions prevent a pixel-diff fidelity claim. Final comparison sheets are passive compositions of the original images, not regenerated UI.

Inspected combined sheets and individual actual captures for readability of terms, permission status, footer and MAIN icon. Text and controls are readable at original resolution; separate cropped-region evidence was not needed. States include first entry, age selection, no permissions, one permission, Bluetooth off/on, pending connection, failure, partial connection, ready and limited mode.

## Findings and iteration history
- [Resolved P2] Small-screen header/large text consumed the available vertical space and overflowed at 320×568 and 200% text. Added a compact step header for that combination; the content scrolls independently of the safe-area footer. Layout tests verify fixed footer geometry across steps and scrolling.
- [Resolved P2] Early captures made the hero too small and did not preserve the intended two-line consent heading. Increased the hero slot, used the actual physical viewport for golden capture, and explicitly wrapped the consent title. Current setup comparison records the revised result.
- [Resolved P2, test evidence] Initial searching/partial-permission/limited screenshots used incorrect fixtures. Fixed pending connection completion and state flags; searching explicitly asserts the visible progress widget before capture. Current captures show each distinct state.
- No remaining actionable P0/P1/P2 findings for the approved interaction/layout requirements.

## Five fidelity surfaces
- Typography: existing Roboto, navy hierarchy and bold display headings; readable Vietnamese diacritics. Font weights follow the production theme rather than the generated mock's approximate typeface. Independent terms link is underlined and wraps. Header compacts at large text; button labels wrap without clipping.
- Layout: 24dp horizontal/footer padding, minimum 52dp actions, 12dp action gap; single actions occupy the lowest slot. Body scroll never moves footer. Existing age grid retained. MAIN/mic status is stacked under each label in two rows/cards to accommodate larger fonts, an intentional responsive adaptation of the mock's side-by-side labels.
- Tokens: existing navy/mint/pink theme; navy primary and outlined secondary controls, semantic green connected indicators. Disabled consent actions retain disabled styling until required confirmation/review. Dark mode uses the app's dark tokens.
- Assets: reused real bundled HOMI penguin and scenery, with clean transparency; no hand-drawn substitute mascot or device illustration. MAIN uses the standard Bluetooth glyph in a pale mint rounded tile as requested. Generated alternative mascot poses, ornamental rings and floating decoration are not reproduced: existing brand assets are retained consistently across states.
- Copy: three steps, concise Bluetooth-off instructions, explicit missing permissions and separate MAIN/mic status. Inline search offers cancellation; failure offers retry. Only live MAIN+mic state enables voice-ready completion. The required existing legal review remains enforced even where the mock suggests an enabled skip action.

## Interaction and regression checks
110 tests passed across onboarding, adapter power, app connection actions, settings device connection and coordinator coverage. These include fixed footer at 390×844/320×568 and 100%/200% text with bottom safe-area inset, legal read vs consent, cancellation/retry/stale completion, partial permissions, both device channels and loss of readiness. The corrected golden suite separately passed all 11 tests; light and dark images were reviewed.

Full Flutter analyzer: no issues. Android debug APK built successfully with the existing production define file. Hardware/native permission prompts are mocked by these tests; real Android/iOS Bluetooth behavior and visual appearance on a physical device remain unverified in this turn. No change to retry cadence or automatic phone-microphone fallback.

## Implementation checklist
- [x] Bottom actions outside the scrollable content, inside safe area.
- [x] Separate parental and legal consent; underlined details link.
- [x] Existing age grid and MAIN Bluetooth icon.
- [x] Permission, power, search/cancel, retry, partial and ready states.
- [x] Automated layout/behavior checks, updated golden evidence, analyzer and debug build.
- [x] Session and design review updated.

Follow-up polish (P3): bespoke mascot poses and additional illustration details can be produced as a separate asset pass; current implementation consistently uses the existing HOMI asset.

## Follow-up: consent alignment correction
User screenshot exposed a P2 alignment mismatch missed in the prior review: CheckboxListTile and the custom legal row had different checkbox offsets and vertical alignment. Replaced both with _ConsentRow (48dp checkbox column, 8dp gap, shared TextButton label styling). Helper copy sits below the label at a 56dp inset. Both checkbox centers and label starts now align. Inspected the revised native first-privacy capture and updated setup comparison. 33 onboarding/layout/golden tests passed, analyzer and diff checks clean. The previously built APK predates this alignment-only correction; it was not rebuilt this turn.

final result: passed

## Follow-up: explicit consent defaults
Resolved opt-in behavior reported by the user: both checkboxes now initialize unchecked even when persisted consent exists. Widget updates cannot tick them. Returning-user Next also requires the user's explicit checkbox selections. Previous legal review may remain recorded; it does not tick agreement. Regression coverage verifies initial persisted consent, asynchronous consent update and Next gating after individual taps/unchecking. Updated native light/dark privacy goldens show unchecked controls. 47 onboarding and app Bluetooth tests passed; analyzer clean. APK not rebuilt this turn.

final result: passed

## Follow-up: step 3 permission refresh
Resolved stale permission state: step 3 performs a read-only native permission check on entry and resume before presenting permission actions. A checking state hides both Grant and Connect while the query is pending. Existing grants route directly to the connection/power UI. Partial or revoked grants show only the missing-permission action. Request actions also recheck authorization and avoid requesting an already-granted permission. Automated app/native-channel tests verify no automatic request/scan, existing grants with Bluetooth on/off, resume grant/revoke, and a pending check. 77 relevant tests passed, existing golden images unchanged; analyzer clean. Android/iOS bridges include read-only queries; Swift syntax parsed successfully, iOS runtime not tested.

final result: passed

Android debug APK rebuilt successfully, including the previous alignment/unchecked-default fixes and the native permission query. Not installed or exercised on physical hardware this turn.

## Follow-up: microphone picker overflow and MAIN prerequisite
Resolved reported P2 layout defect: the picker previously combined a 92px header with a 360px list inside a 354px constraint. It now uses a safe-area, screen-bounded sheet with an Expanded scrollable header/list and a separate dismissal action. Tests verify 15 devices, reaching the last device, 360×640 at text100%/200%, no layout exceptions.

Resolved flow defect: parent setup must establish MAIN before a microphone picker or automatic HFP selection (including iOS). Failed/pending MAIN connections cannot open the picker. The picker binds to the connected MAIN identity and disables selection if it disconnects or changes. 124 related regression tests passed; analyzer clean. Native hardware behavior, particularly iOS GATT interruption during HFP route changes, remains unverified.

final result: passed

## Follow-up: acknowledge terms through either tap target
Latest user instruction supersedes direct checkbox toggling: checkbox and label both open the legal sheet; only its Đã hiểu confirmation checks agreement after dismissal. Closing without acknowledgement leaves an unchecked box unchecked; reopening previously acknowledged terms preserves that choice. Adult confirmation remains independent and initial defaults stay unchecked. Added a duplicate-sheet guard and clarified confirmation copy.

The new large-text path exposed a P2 overflow in the legal sheet footer. Moved its long reading hint into the scrolling content and kept a short, fixed Đã hiểu action, disabled until the content end is reached. 59 onboarding/app tests pass including 200% text and both entry targets; analyzer and diff checks clean.

final result: passed

## Follow-up: connection/retry transition stability
Earlier static screens and bottom-inset checks missed dynamic reflow. A new failing-before test measured footer shrinkage of64px at100% text and124px at200% text on320×568, changing the scroll viewport. Adapter refresh also removed the primary action while busy, and resume checks replaced the settled UI.

Resolved P2: stable footer slots measured from labels and text scale; stable heading/status extents; IndexedStack reserves status-panel geometry; waiting primary is disabled, Cancel remains in the lower slot. Ready uses the lowest slot. Refresh disables rather than removes Connect. Only the first permission check replaces the screen; later checks retain the settled UI while actions are disabled.

Evidence: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-onboarding-implementation/connection-retry-stability.png` combines390×844 native captures for idle/search/failure without scaling. Source is the approved connection/result mockup set recorded above plus the latest user requirement for stable transition geometry. New tests compare footer/viewport/hero/panel rectangles through retry, cancel, partial and ready, including existing scroll position,100%/200% text and pending adapter/permission refresh. All62 relevant tests pass; analyzer clean. Existing goldens refreshed. Hardware playback/navigation was not exercised in this turn.

final result: passed


## Home navy side buttons — 2026-10-21

Scope: approved final revision of option3, limited to the two side controls and the disconnected helper. Existing Home composition, mascot, typography outside those controls and native OS chrome are not a full-screen redesign target.

- Source visual truth: ../docs/session-artifacts/2026-10-21-home-navy-tabs/approved-reference.png (870×1810 raster, normalized to458×954 for comparison).
- Implementation: ../docs/session-artifacts/2026-10-21-home-navy-tabs/home-disconnected-actual.png (Flutter widget renderer458×954, DPR1, light, device gate false). Native OS status bar is absent from widget capture; source includes it. This chrome difference is excluded from fidelity judgement.
- Full comparison: ../docs/session-artifacts/2026-10-21-home-navy-tabs/home-full-comparison.png.
- Focused comparison: ../docs/session-artifacts/2026-10-21-home-navy-tabs/buttons-focused-comparison.png. Native100px controls and reference approx100px controls compared at equal logical scale, local origins aligned; sourceOS and pre-existing adaptive content positioning excluded.
- Responsive evidence: home-small-large-text.png,320×568 at200% text; plus light/dark390×844 goldens.

Findings and comparison history:
- Initial capture used test surface constraints without matching MediaQuery view dimensions, incorrectly positioning the tabs high above mascot. Corrected the golden fixture to set both physicalSize and DPR1; recaptured before comparison. This was a capture configuration defect rather than production layout behavior.
- Final focused comparison: matching navy tile silhouette, white circular icon surface, restrained mint rim, horizontal white labels and gold rays. Equal control dimensions, no overlap with mascot at reviewed viewports. Native Material icons and box decoration retained as real interactive UI. Gold rays use a generated transparent image asset based on user's supplied reference; no custom-painted imitation.
- Fonts/typography: existing Roboto and Material icons;16px bold white labels, one horizontal line. Labels use scaleDown within edge width at large accessibility text sizes; semantics retain full name and one button action. Existing unrelated header truncation at320px/200% remains outside this change.
- Spacing/layout: width22% of viewport clamped78–100px; matching112% height; medallion66% width, rounded inward corner28px. Stable geometry between device states; footer unchanged. Existing compact/large-screen Home positioning retained with short-tab offset adjustment.
- Colors/tokens: primaryNavy faces, darker navy shallow underside, white label/medallion,1.3px muted mint border, yellow decorative rays. No added cyan/green patches.
- Image quality: existing mascot/scenery assets retained; generated245KB transparent ray asset decoded at144px for small UI placement. P3: generated ray texture and subtle tile shading differ slightly from the mock; legibility/shape/hue retained.
- Copy/content: exact Vietnamese disconnected helper “Kết nối với HOMI để bắt đầu sử dụng”; Chinese localization provided. Readiness shared with primary CTA. Connected/processing/recording instructions retain phase-specific behavior.
- Primary interactions verified by widget tests: both tabs open existing features; disconnected gate deduplicates taps and supports cancel; connected→disconnected label/helper updates; recording stop and processing status preserved.
-81 tests passed; flutter analyze and git diff --check clean. No physical-device visual or BLE verification in this turn.

Implementation checklist complete for scoped controls and helper. No actionable P0/P1/P2 mismatch within scope. Remaining P3: optional closer raster shading match; unrelated narrow/large-text header truncation noted above.

final result: passed


## Grouped parent Settings, selected option1 — 2026-10-21

Scope: production Flutter Settings redesign from the first displayed Settings concept, preserving existing device and legal actions.

Source visual truth: ../docs/session-artifacts/2026-10-21-settings-grouped/approved-reference.png (853×1844). Implementation: ../docs/session-artifacts/2026-10-21-settings-grouped/settings-grouped-light.png (390×844, DPR1, disconnected coordinator, age3–5, Vietnamese, System appearance). Source normalized to390×844 for density comparison. Both are app-content screens without native OS chrome; exact fonts use the app's Roboto files.

Full comparison: settings-comparison.png in the same evidence directory. Focused row comparison: settings-preferences-comparison.png. Additional captures: settings-grouped-dark.png, settings-grouped-small-large-text.png (320×568, text200%), settings-language-picker-light.png and settings-language-picker-small-large-text.png.

Findings and comparison history:
- P2 initial comparison: old decorative close background, heavier compact-row labels and nested legal panel treatment diluted the selected simple-list style. Removed close background, flattened legal group, changed row labels to medium weight, and increased header/device gap. Regenerated final light/dark/large-text goldens and compared the final full and focused captures shown above.
- Final: no actionable P0/P1/P2 findings. All3legal/support rows visible at390×844; smaller/large-text layouts scroll naturally. Preference values move under titles at narrow widths/large text, avoiding horizontal overflow.
- Fonts/typography: Roboto regular/bold loaded for capture; title24px, section19px, readable medium-weight row labels, subdued current values. Exact rasterized AI-font contours differ slightly (P3), app fonts retained.
- Spacing/layout:16px page horizontal inset, grouped white18px-radius surfaces, consistent dividers and rows. Device summary/connect first,3preference rows next,3legal/support rows last. Native detail row expands inline to preserve existing connection-work ownership and cancellation rather than opening a new screen; downward chevron intentionally communicates this. This is the sole interaction-layout adaptation to the concept.
- Colors/tokens: existing navy/mint/white and existing dark theme tokens; shadows removed from summary groups. Material icons replace equivalent standard mock icons; no generated illustration is needed for this screen.
- Image quality/asset fidelity: no raster assets in the selected Settings target beyond standard iconography; existing Material icons used, no custom-painted substitute art. Source reference saved in workspace.
- Copy/content: complete privacy policy/terms/support names; descriptions kept in implementation for exceptional permission/consent rows while ordinary legal rows are concise. Actual readiness, searching, partial mic, failed, powered-off and permission states continue to use existing coordinators; never hardcoded green readiness. Legal URLs and parental gate unchanged.
- Functionality: selectors close before invoking callbacks; cancel keeps prior selection; language changes update the page, age selection updates summary, theme applies immediately. Top connection CTA/cancel remain guarded by the existing coordinator. Device details retain microphone/battery/history actions.
- Validation:55targeted tests passed (Settings UI, device flow, persisted age/theme/media, app Bluetooth/onboarding regressions with required test privacy defines), analyzer and diff check clean. Light/dark/320px200% rendering checked. No physical-device BLE run in this turn. Chinese selection logic tested; test renderer lacks OS CJK fallback glyphs, so Chinese text raster fidelity is not claimed from these images.

Implementation checklist: grouped layout, selectors, connection state handling, legal routes, responsive rendering and regressions complete. Residual P3: small native-icon/font differences from AI mock.

final result: passed


### Age popup follow-up — 2026-10-21

Restored the previous wrapped ChoiceChip layout inside the age picker only. Main Settings remains compact. Inspected rendered goldens at390×844 and320×568/text200%: chips wrap3+2 at normal size and one per row at large text; no overflow. Selected mint/check treatment follows the existing theme.14 Settings flow tests pass; analyzer clean. No device installation or APK rebuild in this follow-up.
