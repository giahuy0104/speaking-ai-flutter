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

---

# Home cloud tabs and conversation bubbles - 2026-10-21

final result: passed

## Scope and visual truth

Native Flutter production UI, implemented in the existing project rather than a separate web prototype. This section is the latest Home review; earlier onboarding and Settings reports above are preserved. No device installation or physical HOMI verification is claimed.

Source visual truth: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-home-speaking-focus/08-cloud-edge-tabs-sky-blue-highlight.png` (870 x 1808 px). The user's sketch establishes narrow edge tabs with whole-word labels rotated 90 degrees; the latest approved image establishes white faces and slightly stronger sky-blue highlights, plus separate white Vietnamese and mint English conversation bubbles.

Implementation capture: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-home-cloud-implementation/implementation-final-458x954.png` (458 x 954 px, 458 x 954 Flutter logical pixels, DPR 1). State: light theme, Vietnamese, disconnected, empty transcript, idle. There is no CSS viewport because these are native Flutter captures.

Density normalization: source scaled proportionally and padded to 458 x 954, without changing the app capture. Full comparison sheet: `/Users/quangonfire/Desktop/Projects/main/HOMI/docs/session-artifacts/2026-10-21-home-cloud-implementation/comparison-final.png` (936 x 984 px including gutters/captions). Both original design and actual Flutter capture were opened together in this image. Focused comparisons were also opened: `comparison-tabs.png` (936 x 190 px) and `comparison-bubbles.png` (936 x 300 px), in the same evidence folder.

Additional actual captures in that folder: `implementation-320x568-large-text.png`, `implementation-dark-390x844.png`, `implementation-recording-390x844.png`, `implementation-processing-390x844.png`, and `implementation-ready-450x1025.png`. Dark/ready controller fixtures are presentation fixtures, not proof of real hardware readiness. Original app scenery and mascot assets are intentionally retained instead of replacing them with the regenerated character in the mock.

## Findings and comparison history

- [Resolved P2] First pass over-indented transcript placeholders under the icon/label row. Evidence: `comparison-first-pass.png`. Reduced body indentation to match the approved reading treatment; retained common bubble padding for both languages. Post-fix evidence: `comparison-bubbles.png` and `comparison-final.png`.
- [Resolved P2] The main content was too high on the tall target viewport. Increased only the scroll-content top padding, leaving header, fixed primary action and controller flow intact. The final comparison shows the reading area at the intended vertical region.
- [Resolved P2] Generated tab undersides were more saturated than the approved restrained highlights. Added a light white blend to the raster artwork. The final focused tab comparison retains the white face, blue accent and narrow geometry.
- [Resolved P2] White tabs attracted too much attention in dark mode. Adapted the cloud surface tint and label/icon foreground to the existing dark palette. The final dark capture was opened and reviewed: the mascot and primary action remain dominant.
- [Resolved behavior] New press feedback requires a short visual completion before navigation, so old transition tests assumed the wrong starting frame. Tests now wait for actual entry before checking direction. Existing destination callbacks, microphone ownership and background-learning logic are unchanged.
- No remaining actionable P0/P1/P2 finding in the changed Home components.

## Five fidelity surfaces

- Fonts/typography: existing Roboto and app type scale retained. Labels are a single unbroken string rotated counterclockwise on the left and clockwise on the right; semantic labels remain normally ordered. Vietnamese diacritics are readable. Large text is constrained by the narrow tab's available space instead of wrapping characters vertically. Test-font/native font contours can differ from the generated mock; no pixel-identical typeface claim.
- Spacing/layout: each stable tab target is 48 x 168 logical pixels, anchored to its screen edge. Only the visual grows inward by up to 4.5 percent. Icons stay upright above the whole-word rotated label. The result bubbles grow with content and text scale; the fixed speaking/connection action remains outside the scroll region. Body padding was checked against the source.
- Colors/tokens: original navy/mint theme and original sky/hills retained; navigation accents are sky-blue, not the rejected mint glow. Vietnamese surface is white, English surface is mint. Dark mode uses subdued blue cloud faces and light labels, plus dark white/mint-equivalent reading surfaces.
- Image quality/asset fidelity: supplied mascot and scenery remain real app assets. Two distinct transparent raster cloud tabs were generated from the approved target and inspected; both PNGs are RGBA 724 x 2172 with genuine alpha. Their transparent padding is handled in the image slot, and decoding is capped with cacheWidth 216. No substitute painted cloud geometry or baked UI text/icons is used. Speech-bubble tails are standard UI ShapeBorder geometry, not replacement illustration assets. Standard Material icons retain the app's icon system.
- Copy/content: Vietnamese/English labels, result text and replay behavior are preserved. Empty English copy now reads the approved "Bản dịch sẽ hiện ở đây" in Vietnamese and has a Chinese translation. Connection/start/recording/processing/stop labels and error handling remain under existing controllers. Offline translation attribution remains visible when required.

## Interaction and regression evidence

- Single tap: subtle press growth, then the existing callback. No extra tap to reveal a name.
- Feedback: 110 ms forward and 170 ms return; anchor on the outer edge, unchanged hit target. Cancelled presses do not navigate. Rapid taps coalesce while feedback is active; disposal cancels stale activation. Reduced motion skips growth and activates immediately.
- Native navigation directions, parental settings flow, MAIN ownership, automatic connection, device-action gate, processing states, long results, replay and offline attribution are covered by the selected tests.
- 126 selected widget/unit regressions passed. Eight changed visual golden checks passed again without --update-goldens after inspecting their captures. Unrelated known baseline failures from the earlier test audit were not regenerated or represented as fixed.
- Full Flutter analyzer: no issues. Final Android debug APK build passed in 36.0 seconds with the existing production define file; see the build log in the evidence folder. These tests mock hardware and do not verify radio/firmware behavior.

## Follow-up polish / limits

- P3: generated mock fonts, avatar pose, exact cloud billow contours and landscape saturation differ slightly because the existing app mascot/scenery and native theme were deliberately preserved.
- P3, existing: at 320 x 568 and 200 percent text, the compact header still ellipsizes the brand/status. Both edge controls and the primary action remain accessible, and the reading region scrolls. Full Home accessibility compliance is not claimed by this scoped change.
- Chinese semantics and layout were tested; golden tests do not claim OS CJK fallback font fidelity.
- No physical Android/iOS/HOMI test or installation was performed for this UI-only change.

## Implementation checklist

- [x] Approved narrow white/blue cloud tabs with rotated complete labels.
- [x] Gentle inward press feedback; stable targets and cancellation/reduced-motion handling.
- [x] White/mint reading bubbles; result, replay and attribution logic retained.
- [x] Existing navigation, retry cadence and microphone ownership retained.
- [x] Native light/dark/large-text captures, direct comparisons and relevant regressions reviewed.
- [x] Analyzer clean; source and session evidence retained.

final result: passed

## Follow-up: Android cloud label alignment (2026-10-21)

The user's physical screenshot revealed a gap in the previous review: rectangular widget bounds do not establish that the content stays on an irregular cloud's white face. The icon/label group overlapped blue pinches and was spread too far vertically. The user confirmed these are the two affected controls.

Resolution: stretch the flat white image strip using centerSlice, keep the blue inward billows, and align the complete rotated label and upright icon inside the white body. Width responds to text scale (48–56dp); both tabs retain equal height and a stable hit target during the original press animation. Navigation and device behavior are untouched.

Reviewed native Flutter captures at 360×800dp/DPR3/insets36–42, 411.43×914.29dp/DPR2.625/insets40–24, 458×954, dark390×844 and 320×568 at200% text. These profiles cover Android density/insets but are not claimed to be the exact unknown metrics of the submitted screenshot. The golden harness now includes the app's Roboto-Medium font. New assertions inspect painted white pixels around both icons and labels; this caught the large-text edge collision before the final fix. Visual comparisons and final captures are saved in ../docs/session-artifacts/2026-10-21-home-cloud-responsive/.

88 relevant regression tests and 6 golden/profile tests passed; analyzer clean. The existing large-text header truncation remains outside this two-control fix. No physical device installation/runtime result is claimed. The previous source and generated captures remain preserved for comparison.

final result: passed (scoped Flutter render verification; physical device confirmation pending)

Debug APK build completed successfully (assembleDebug51.7s); dart format and git diff --check passed. Artifact: build/app/outputs/flutter-apk/app-debug.apk.

## Follow-up: natural cloud ends (2026-10-21)

User reported that the stretched cloud strip terminated in square horizontal ledges. The previous round-rectangle clip did not preserve the raster's curved blue rim. Reproduced the defect with an alpha-based assertion against the actual rendered artwork: the old code paints a broad flat tip (50px at DPR3, above the40.32px limit).

Replaced both raster assets using built-in ImageGen, with a broad white core, shallow varied billows and naturally tapered curved ends. Removed centerSlice and cap clipping. Right-side transparent padding is placed outside the screen edge using its measured content width, and the right content group is inset into the white face. Preserved the responsive tab target, full rotated labels, upright icons, press feedback and navigation behavior.

Inspected comparison-caps.png plus final light458×954, dark390×844, Android360×800/DPR3/insets36–42, Android411.43×914.29/DPR2.625/insets40–24, and320×568/chữ200% captures. Caps now curve into the edge without a horizontal ledge; both labels/icons remain on the white face. Verified actual alpha taper and painted white pixels in addition to bounds. Evidence, selected PNG paths and full prompts: ../docs/session-artifacts/2026-10-21-home-cloud-natural-caps/.

88 regression tests and6 golden/profile tests passed; analyzer, format and diff checks clean. Physical device installation/runtime verification is not claimed. The earlier out-of-scope header truncation at200% text remains documented.

final result: passed (scoped Flutter render verification)

Debug build passed (assembleDebug33.4s); APK: build/app/outputs/flutter-apk/app-debug.apk. No install was performed.
