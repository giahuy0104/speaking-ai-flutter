# Navigation final review — 2026-10-21

The registered route migration works for the normal tested workflows. Settings has a conditional reentry risk while pre-navigation asynchronous work is pending; ordinary double taps did not reproduce it in widget probes. The original callback-only probe overstated the evidence for a normal user gesture.

## Confirmed finding [P2]: duplicate Settings pages release visibility too early

`home_learning_shell.dart:1401` awaits access and voice pause without an opening/open guard. Two calls to ConversationScreen.onOpenSettings before either completes both reach `_openSettingsPage` and push `/settings`. Each pushes with `onModalVisibilityChanged(true)` and independently releases it with false in finally at line1451.

A temporary diagnostic test called the actual Home callback twice, using the existing Home test harness/controller and production router. It observed two registered Settings pushes, visibility `[true, true]`, then after popping only the top page the lower Settings page remained current while visibility became `[true, true, false]`.

This confirms route duplication and incorrect global-modal visibility. The same finally path proceeds to `_resumeVoiceNavigation` while another Settings page remains. AiSpeakingApp uses the boolean to hide floating MAIN and gate background voice activation, so early release can restore assistant UI/behavior in Settings. That downstream impact is inferred from the call sites; the probe did not simulate physical MAIN or native speech.

Recommendation: own one in-flight/open Settings operation starting before the first await, ignore or coalesce further open requests, release ownership only after the page fully exits; check mounted after asynchronous access/pause. Apply the same ownership principle to History and cross-modal entry so they cannot independently release a shared boolean. Keep BLE retry/audio services unchanged. Add regression cases for duplicate entry, cancelled parent access, Back/Close, and Settings-vs-History overlap. No fix applied in this review-only turn.

## Validated normal behavior

Fresh run: 73 core-route/helper/Home tests passed. Covers named registration, typed pop/replacement results, nearest Navigator, paused Android/iOS learning initialization, no learning-exit on Settings Back, full Settings page, live theme, PageView navigation, horizontal animation and reduced motion. One additional diagnostic probe passed its assertions reproducing the defect; it is not counted as evidence that the defect is fixed.

The earlier broad suite had831 pass/29 known baseline failures; those were separately audited. This review did not rerun the broad suite or build/install APK. No physical-device swipe-Back, radio/audio or Android predictive-Back validation was done.

## Deliberate remaining boundaries

- Home/Vocabulary still use PageView; root startup/onboarding retain home gate. Dialogs/device pickers remain local modal routes.
- Three review/karaoke continuations retain a WidgetBuilder and unnamed route; karaoke retains lessonPractice observer identity. Keep these until observer/audio-flow refactoring has its own tests.
- AppRoute carries in-memory arguments and lazy bindings. Use AppNavigator rather than raw pushNamed(data). Presentation/type validation currently occurs at runtime; stronger typed destination APIs can be introduced during MVI/DI migration.
- Web URL deep links, browser-history integration, cold-start route reconstruction and restoration are not implemented by this named-route phase.
- Default slide transitions reuse Cupertino behavior. Interactive Back and Android predictive Back still need actual device verification, especially the custom Topics route.

Evidence: HOMI/docs/session-artifacts/2026-10-21-route-final-review/. Temporary test removed from discovery; production source not edited in this turn.


## Clarification after actual tap probes

The earlier probe invoked onOpenSettings twice directly. It did not establish that ordinary fast tapping reproduces duplicate pages. Four additional actual hit-tested tap probes on Android, with inter-tap gaps0,16,60,120ms and the existing quick-return harness, each produced exactly one Settings push. This matches the user's inability to reproduce normal double taps.

A fifth probe delayed only markParentDiagnosticsOpened via a Completer (simulating the awaited native diagnostic call before navigation). Two actual taps60ms apart both entered that pending stage; releasing it produced two /settings routes. Popping one left Settings current while visibility was false. This establishes a conditional asynchronous reentry defect, not its frequency on a physical phone. The native call's real latency was not measured.

The production opening flow awaits parent access, voice pause and native marker before push; if these complete promptly, the destination takes over input before a second ordinary tap can request another opening. If a stage remains pending and Home still accepts taps, duplicate work is possible. Reframe the recommendation as a small preventive guard for the pending/open period, not a claim that normal users can readily reproduce a navigation failure. No production changes in this clarification turn. All5 tap probes passed their intended diagnostic assertions; the temporary test was removed.
