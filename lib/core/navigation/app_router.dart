import 'package:flutter/material.dart';

import 'active_learning_navigation.dart';
import 'app_route.dart';

enum AppRoutePresentation { learningPage, page, bottomSheet }

/// Presentation supplies typed factories; core knows no feature screen classes.
class AppRouteEntry<A, D extends Object> {
  const AppRouteEntry({
    required this.builder,
    this.presentation = AppRoutePresentation.learningPage,
    this.navigatorName,
    this.unnamed = false,
  });

  final Widget Function(BuildContext context, A arguments, D bindings) builder;
  final AppRoutePresentation presentation;

  /// Compatibility identities consumed by the existing MAIN observer.
  final String? navigatorName;
  final bool unnamed;

  void validateArguments(Object? arguments) {
    if (arguments is! A) {
      throw FlutterError(
        'Route expects $A, received ${arguments.runtimeType}.',
      );
    }
  }

  Widget build(BuildContext context, AppRoute<Object?> destination) {
    final bindings = destination.bindings();
    if (bindings is! D) {
      throw FlutterError(
        'Route ${destination.name} expects bindings $D, '
        'received ${bindings.runtimeType}.',
      );
    }
    return builder(context, destination.arguments as A, bindings);
  }
}

/// Registered once on MaterialApp.onGenerateRoute. There is no fallback which
/// silently pushes a caller-built screen when a destination is not registered.
class AppRouter {
  AppRouter(Map<String, AppRouteEntry<dynamic, Object>> routes)
    : _routes = Map.unmodifiable(routes);

  final Map<String, AppRouteEntry<dynamic, Object>> _routes;

  Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final entry = _routes[settings.name];
    // Navigator probes intermediate paths when expanding initialRoute. Return
    // null for unknown names so Flutter can apply its normal initial-route or
    // onUnknownRoute policy; imperative pushes still fail if unregistered.
    if (entry == null) return null;
    final request = settings.arguments;
    if (request is! AppRouteRequest ||
        request.destination.name != settings.name) {
      throw FlutterError(
        'Route ${settings.name} requires a typed AppNavigator '
        'request. External URLs are not supported by this migration.',
      );
    }
    if (entry.presentation != request.presentation) {
      throw FlutterError('Incorrect presentation for route ${settings.name}.');
    }
    entry.validateArguments(request.destination.arguments);
    final destination = request.destination;
    return request.createRoute(
      (context) => entry.build(context, destination),
      RouteSettings(
        name: entry.unnamed ? null : entry.navigatorName ?? settings.name,
        arguments: request.destination.arguments,
      ),
    );
  }
}

/// Transport used only while Navigator synchronously generates a named route.
/// The resulting RouteSettings contains view arguments, not this request or its
/// caller context/dependencies.
abstract class AppRouteRequest {
  AppRoute<Object?> get destination;
  AppRoutePresentation get presentation;
  Route<dynamic> createRoute(WidgetBuilder builder, RouteSettings settings);
}

class TypedAppRouteRequest<T extends Object?> implements AppRouteRequest {
  TypedAppRouteRequest({
    required this.destination,
    required this.presentation,
    required BuildContext context,
    this.onRouteCreated,
    this.foregroundTransitionDuration,
    this.foregroundReverseTransitionDuration,
    this.foregroundTransitionsBuilder,
  }) : mobileBackground = isActiveLearningAppBackground(),
       _callerContext = context;

  @override
  final AppRoute<Object?> destination;
  @override
  final AppRoutePresentation presentation;
  final bool mobileBackground;
  final BuildContext _callerContext;
  final void Function(Route<T>)? onRouteCreated;
  final Duration? foregroundTransitionDuration;
  final Duration? foregroundReverseTransitionDuration;
  final RouteTransitionsBuilder? foregroundTransitionsBuilder;

  @override
  Route<T> createRoute(WidgetBuilder builder, RouteSettings settings) {
    final Route<T> route;
    switch (presentation) {
      case AppRoutePresentation.page:
        // Settings and other utility pages must not emit a learning-exit event.
        route = MaterialPageRoute<T>(builder: builder, settings: settings);
      case AppRoutePresentation.learningPage:
        route = createActiveLearningRoute<T>(
          builder,
          mobileBackground: mobileBackground,
          settings: settings,
          foregroundTransitionDuration: foregroundTransitionDuration,
          foregroundReverseTransitionDuration:
              foregroundReverseTransitionDuration,
          foregroundTransitionsBuilder: foregroundTransitionsBuilder,
        );
      case AppRoutePresentation.bottomSheet:
        // Match showModalBottomSheet defaults, theme capture and accessibility.
        final navigator = Navigator.of(_callerContext);
        final localizations = MaterialLocalizations.of(_callerContext);
        route = ModalBottomSheetRoute<T>(
          builder: builder,
          settings: settings,
          capturedThemes: InheritedTheme.capture(
            from: _callerContext,
            to: navigator.context,
          ),
          barrierLabel: localizations.scrimLabel,
          barrierOnTapHint: localizations.scrimOnTapHint(
            localizations.bottomSheetLabel,
          ),
          modalBarrierColor: Theme.of(
            _callerContext,
          ).bottomSheetTheme.modalBarrierColor,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
        );
    }
    onRouteCreated?.call(route);
    return route;
  }
}

/// Existing review/karaoke continuation, kept separate from view arguments.
class LearningContinuationBindings {
  const LearningContinuationBindings(this.builder);
  final WidgetBuilder builder;
}
