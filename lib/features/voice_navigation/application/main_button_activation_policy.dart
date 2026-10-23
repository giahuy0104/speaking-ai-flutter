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
    required bool isHomiReady,
    bool? isHomiAudioReady,
    bool hasSelectedHfpInput = false,
  }) {
    // MAIN is an independent control link. Losing it must never change the
    // selected microphone while its verified HFP connection is still alive.
    if (isHomiAudioReady ?? isHomiReady) {
      return MainButtonAudioRoute.selectedHfp;
    }
    // Keep a lost/unverified selected headset explicit instead of silently
    // recording from the handset. Phone-only use still works without one.
    if (hasSelectedHfpInput) return MainButtonAudioRoute.unavailable;
    if (source == MainButtonSource.ble && isIos && !isHomiReady) {
      return MainButtonAudioRoute.unavailable;
    }
    if (source == MainButtonSource.screen && isNativeMobile && !isHomiReady) {
      return MainButtonAudioRoute.phoneMicrophone;
    }
    return MainButtonAudioRoute.selectedHfp;
  }

  /// A module's follow-up question (the vocabulary menu, for example)
  /// continues with the selected microphone even when BLE MAIN is recovering.
  /// The handset route is retained only for a session without a selected HFP
  /// device. An unavailable selected headset requires reconnection.
  static MainButtonAudioRoute followUpAudioRoute({
    required bool isAndroid,
    required bool isHomiReady,
    bool? isHomiAudioReady,
    bool hasSelectedHfpInput = false,
  }) {
    if (isHomiAudioReady ?? isHomiReady) {
      return MainButtonAudioRoute.selectedHfp;
    }
    if (hasSelectedHfpInput) return MainButtonAudioRoute.unavailable;
    return isAndroid
        ? MainButtonAudioRoute.phoneMicrophone
        : MainButtonAudioRoute.selectedHfp;
  }
}
