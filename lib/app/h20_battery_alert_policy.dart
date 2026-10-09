enum H20BatteryAction { chargeSoon, chargeCritical, disconnectDepleted }

/// Emits each low-battery transition once without coupling battery telemetry to
/// learning, audio, or navigation state.
class H20BatteryAlertPolicy {
  String? _deviceId;
  bool _chargeSoonShown = false;
  bool _chargeCriticalShown = false;
  bool _depletedHandled = false;

  List<H20BatteryAction> observe({
    required bool connected,
    required String? deviceId,
    required int? batteryPercent,
  }) {
    final normalizedDeviceId = deviceId?.trim().isNotEmpty == true
        ? deviceId!.trim()
        : 'unknown-h20';
    if (_deviceId != normalizedDeviceId) {
      _deviceId = normalizedDeviceId;
      _chargeSoonShown = false;
      _chargeCriticalShown = false;
      _depletedHandled = false;
    }
    if (!connected || batteryPercent == null) return const [];

    final percent = batteryPercent.clamp(0, 100);
    // Re-arm only after an actual charging recovery, with hysteresis so a
    // noisy reading around 20% or 5% cannot repeatedly notify the child.
    if (percent >= 25) _chargeSoonShown = false;
    if (percent >= 8) _chargeCriticalShown = false;
    if (percent > 0) _depletedHandled = false;

    if (percent == 0) {
      _chargeSoonShown = true;
      _chargeCriticalShown = true;
      if (_depletedHandled) return const [];
      _depletedHandled = true;
      return const [H20BatteryAction.disconnectDepleted];
    }
    if (percent < 5) {
      _chargeSoonShown = true;
      if (_chargeCriticalShown) return const [];
      _chargeCriticalShown = true;
      return const [H20BatteryAction.chargeCritical];
    }
    if (percent <= 20 && !_chargeSoonShown) {
      _chargeSoonShown = true;
      return const [H20BatteryAction.chargeSoon];
    }
    return const [];
  }
}
