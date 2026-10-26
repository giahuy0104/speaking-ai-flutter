import 'package:flutter/material.dart';

import 'app_route.dart';
import 'app_route_names.dart';
import 'app_router.dart';

export 'app_route.dart';
export 'app_route_names.dart';

/// Dispatches through the nearest Navigator's registered onGenerateRoute.
/// Device/parental gates and audio lifecycle remain with their existing owners.
class AppNavigator {
  const AppNavigator();

  static AppNavigator of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppNavigationScope>()?.navigator ??
      const AppNavigator();

  Future<T?> push<T extends Object?>(
    BuildContext context,
    AppRoute<Object?> destination, {
    void Function(Route<T> route)? onRouteCreated,
    Duration? foregroundTransitionDuration,
    Duration? foregroundReverseTransitionDuration,
    RouteTransitionsBuilder? foregroundTransitionsBuilder,
  }) {
    final request = TypedAppRouteRequest<T>(
      context: context,
      destination: destination,
      presentation: AppRoutePresentation.learningPage,
      onRouteCreated: onRouteCreated,
      foregroundTransitionDuration: foregroundTransitionDuration,
      foregroundReverseTransitionDuration: foregroundReverseTransitionDuration,
      foregroundTransitionsBuilder: foregroundTransitionsBuilder,
    );
    final closed = Navigator.of(
      context,
    ).pushNamed<T>(destination.name, arguments: request);
    if (request.mobileBackground) WidgetsBinding.instance.scheduleWarmUpFrame();
    return closed;
  }

  Future<T?> replace<T extends Object?, TO extends Object?>(
    BuildContext context,
    AppRoute<Object?> destination, {
    TO? result,
  }) {
    final request = TypedAppRouteRequest<T>(
      context: context,
      destination: destination,
      presentation: AppRoutePresentation.learningPage,
    );
    final closed = Navigator.of(context).pushReplacementNamed<T, TO>(
      destination.name,
      arguments: request,
      result: result,
    );
    if (request.mobileBackground) WidgetsBinding.instance.scheduleWarmUpFrame();
    return closed;
  }

  Future<T?> replaceLearningContinuation<T extends Object?, TO extends Object?>(
    BuildContext context,
    WidgetBuilder builder, {
    TO? result,
  }) => replace<T, TO>(
    context,
    AppRoute<void>(
      name: AppRouteNames.learningContinuation,
      arguments: null,
      bindings: () => LearningContinuationBindings(builder),
    ),
    result: result,
  );

  /// Opens a regular page without committing an active-learning exit on Back.
  Future<T?> pushPage<T extends Object?>(
    BuildContext context,
    AppRoute<Object?> destination,
  ) => Navigator.of(context).pushNamed<T>(
    destination.name,
    arguments: TypedAppRouteRequest<T>(
      context: context,
      destination: destination,
      presentation: AppRoutePresentation.page,
    ),
  );

  Future<T?> showSheet<T extends Object?>(
    BuildContext context,
    AppRoute<Object?> destination,
  ) => Navigator.of(context).pushNamed<T>(
    destination.name,
    arguments: TypedAppRouteRequest<T>(
      context: context,
      destination: destination,
      presentation: AppRoutePresentation.bottomSheet,
    ),
  );
}

/// Optional composition/test seam; no global service locator or stored context.
class AppNavigationScope extends InheritedWidget {
  const AppNavigationScope({
    required this.navigator,
    required super.child,
    super.key,
  });

  final AppNavigator navigator;

  @override
  bool updateShouldNotify(AppNavigationScope oldWidget) =>
      navigator != oldWidget.navigator;
}
