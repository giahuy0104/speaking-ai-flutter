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
}
