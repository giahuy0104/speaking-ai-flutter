import '../../../core/device/main_button_coordinator.dart';

enum MainButtonAudioRoute { selectedHfp, phoneMicrophone, unavailable }

/// Keeps MAIN gesture sources on the same assistant lifecycle and audio route.
abstract final class MainButtonActivationPolicy {
  static bool canStart({
    required bool isActivationPending,
    required bool isMainButtonSessionActive,
  }) => !isActivationPending && !isMainButtonSessionActive;

  static MainButtonAudioRoute audioRoute({
    required MainButtonSource source,
    required bool isNativeMobile,
    required bool isIos,
    required bool isH20Ready,
  }) {
    if (source == MainButtonSource.ble && isIos && !isH20Ready) {
      return MainButtonAudioRoute.unavailable;
    }
    if (source == MainButtonSource.screen && isNativeMobile && !isH20Ready) {
      return MainButtonAudioRoute.phoneMicrophone;
    }
    return MainButtonAudioRoute.selectedHfp;
  }

  /// A module's follow-up question (the vocabulary menu, for example)
  /// continues the session that opened it. Android prepares the H20 route
  /// before every activation, so without a ready H20 the follow-up keeps the
  /// handset microphone; otherwise no microphone opens after the prompt. iOS
  /// has no such gate and keeps its route unchanged.
  static MainButtonAudioRoute followUpAudioRoute({
    required bool isAndroid,
    required bool isH20Ready,
  }) => isAndroid && !isH20Ready
      ? MainButtonAudioRoute.phoneMicrophone
      : MainButtonAudioRoute.selectedHfp;
}
