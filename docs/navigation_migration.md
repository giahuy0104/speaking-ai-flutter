# Registered navigation — 2026-10-21

Navigation is registered on the real `AiSpeakingApp` MaterialApp:

```dart
late final _appRouter = createAppRouter();

// In MaterialApp:
onGenerateRoute: _appRouter.onGenerateRoute,
```

The existing `home` startup/onboarding gate, navigator key, global Overlay and
`_MainOverlayNavigatorObserver` remain in place. This phase does not introduce
Bloc, a DI container, go_router, a new tab stack or a project-wide migration.

## Structure

- `core/navigation/app_navigator.dart`: injectable dispatch adapter. Calls the
  nearest Navigator's `pushNamed` / `pushReplacementNamed`, including sheets.
- `core/navigation/app_router.dart`: route generation and presentation handling;
  imports no feature screens. Validates input types and presentation mode.
- `core/navigation/app_route.dart`: route name, typed view arguments and a lazy
  provider of existing presentation dependencies. Ordinary routes no longer
  carry a caller-owned screen builder.
- `core/navigation/app_route_names.dart`: centralized names;
  `ListeningRouteNames` remains a compatibility alias.
- `core/navigation/view_arguments/`: nine view-input classes. They contain no
  device/audio services or callbacks.
- `presentation/navigation/app_view_registry.dart`: central registration of the
  twelve page/sheet/continuation destinations and their screen constructors.
- `presentation/navigation/view_bindings.dart`: typed holders for existing
  services, controllers, callbacks and live presentation flags. These are
  supplied lazily by their current owner; the router does not own their lifecycle.
- `core/navigation/active_learning_navigation.dart`: existing background-aware
  behavior, with its route factory made public for reuse by the named router.

## Usage

```dart
await AppNavigator.of(context).push<void>(
  context,
  AppRoute<TopicListeningArguments>(
    name: AppRouteNames.topicCatalog,
    arguments: TopicListeningArguments(
      language: language,
      childAge: childAge,
    ),
    bindings: () => TopicListeningBindings(
      controller: controller,
      ensureDeviceConnected: ensureDeviceConnected,
    ),
  ),
);
```

The central registry constructs `TopicListeningScreen`. View arguments preserve
existing content/session object identities. Live dependencies are evaluated when
building the destination, as the former screen builder did; theme/consent and
MAIN pause flags are not frozen at dispatch time.

`push<T>` returns the eventual pop result. `replace<T, TO>` preserves both result
types, including the result of the replaced route. `onRouteCreated` is invoked
synchronously before push so Home can retain its route-installed coordination.
Foreground transitions and mobile-background zero-duration routes/warm-up frames
reuse the existing behavior. The final `RouteSettings.arguments` contains only
view input data, not the temporary transport or caller BuildContext.

`pushPage` opens Settings as a regular `MaterialPageRoute` with a full-screen
Scaffold. It deliberately omits the learning-exit PopScope: closing Settings must
not cancel an active learning/voice session. Its existing access gate, pause/resume
and modal-visibility callback remain responsible for suspending Home and hiding
floating MAIN while Settings is open. The existing Settings content and its inner
age/language/theme pickers are reused unchanged.

`showSheet` still creates a registered `ModalBottomSheetRoute` for History, with
safe area, drag handle, scroll control, theme capture, barrier and accessibility
semantics. Both Settings and History use `AppRoute<void>` because they have no
view input data; their current dependencies belong in bindings.

## Compatibility boundaries

- Home/Vocabulary keep their PageView, mounted state and voice activation.
- Startup/onboarding keep their root gate and existing callbacks.
- Device/parental gates, audio handoff, BLE retry cadence, checkpoint saves,
  cancellation and pop/popUntil stay with their current owners.
- Karaoke has its own registry key but keeps the legacy `lessonPractice` name
  in its resulting RouteSettings for MAIN visibility and return predicates.
- Three review/karaoke continuations still accept existing WidgetBuilders through
  `replaceLearningContinuation`; their registered route remains unnamed to the
  existing observer. This is an explicit compatibility bridge.
- Local dialogs and device pickers retain their current implementation.
- The MAIN observer is unchanged. The active-learning route factory body is
  unchanged; only its visibility/name changed to allow reuse.

## Scope and future work

Use AppNavigator for these destinations. Raw `pushNamed(name, arguments: data)`
is not the public interface: generation also needs a typed result/presentation
request and existing dependencies. Unknown names return null to Flutter, allowing
normal initialRoute path probing/onUnknownRoute behavior; malformed requests to
registered destinations fail explicitly.

These are in-app named routes, not serialized deep links. External URLs, browser
history/restoration and cold-start reconstruction need a separate design. Some
view input types currently reside in feature data/application folders; move their
contracts to domain during the future MVI migration, without moving persistence
code in this phase.

For MVI, dispatch from a presentation listener consuming navigation effects;
keep BuildContext out of Bloc. AppNavigationScope is an optional DI/test injection
point. Bindings can later be supplied by the composition root while preserving
route names and view arguments.

Validation and baseline comparison: [navigation_validation.md](navigation_validation.md).

## Page animations

Both light and dark themes use `AppPageTransitionsBuilder` for every platform.
Regular MaterialPageRoute destinations slide in from the right over 300 ms and
reverse on Back, using Flutter's Cupertino transition implementation to retain interactive
Back support. Settings continues to be a regular page without learning-exit
callbacks. Sheets/dialogs retain their own presentation.

Home's Topics route uses a full-width right-to-left slide with its existing
260 ms timing and route-installed callback. Vocabulary remains logical page 1
in the existing PageView, now reversed so it enters from the left; Home remains
page 0 and returns from the right. Neither state ownership nor audio handoff
changes. Existing background zero-duration route handling and disabled-animation
accessibility behavior remain in place.
