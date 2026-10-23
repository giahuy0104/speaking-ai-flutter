part of 'app_bloc.dart';

sealed class AppEvent {
  AppEvent();
  // Awaitable commands preserve the ordering of existing app side effects.
  final Completer<void> _completed = Completer<void>();
}

final class AppStarted extends AppEvent {}

/// Sent after the existing persistence operation succeeds.
final class AppConsentGranted extends AppEvent {}

final class AppLimitedModeSelected extends AppEvent {}

final class AppConsentRevoked extends AppEvent {}

final class AppOnboardingReopened extends AppEvent {}

final class AppOnboardingCompleted extends AppEvent {
  AppOnboardingCompleted({required this.hasValidProfile});
  final bool hasValidProfile;
}

/// Lifecycle is an input; it must not replace the app's readiness state.
final class AppResumed extends AppEvent {}
