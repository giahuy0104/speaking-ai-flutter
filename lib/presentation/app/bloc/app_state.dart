part of 'app_bloc.dart';

enum AppStatus {
  initial,
  initializing,
  onboardingRequired,
  ready,
  initializationFailed,
}

enum AppUsageMode { full, limited }

enum AppInitializationFailure { startupUnavailable }

/// Bootstrap input only; profile/settings and native permissions keep their
/// existing owners. Validity is checked by the injected startup loader.
class AppStartupSnapshot {
  const AppStartupSnapshot({
    required this.privacyConsentGranted,
    required this.limitedModeSelected,
    required this.setupCompleted,
    required this.hasValidProfile,
  });

  final bool privacyConsentGranted;
  final bool limitedModeSelected;
  final bool setupCompleted;
  final bool hasValidProfile;
}

class AppState {
  const AppState({
    this.status = AppStatus.initial,
    this.usageMode = AppUsageMode.full,
    this.privacyConsentGranted = false,
    this.failure,
  });

  final AppStatus status;
  final AppUsageMode usageMode;
  final bool privacyConsentGranted;
  final AppInitializationFailure? failure;

  bool get isReady => status == AppStatus.ready;
  bool get isLoading =>
      status == AppStatus.initial || status == AppStatus.initializing;
  bool get isLimited => usageMode == AppUsageMode.limited;

  @override
  bool operator ==(Object other) =>
      other is AppState &&
      other.status == status &&
      other.usageMode == usageMode &&
      other.privacyConsentGranted == privacyConsentGranted &&
      other.failure == failure;

  @override
  int get hashCode =>
      Object.hash(status, usageMode, privacyConsentGranted, failure);
}
