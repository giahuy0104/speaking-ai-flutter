enum H20BatteryAction {
  chargeSoon,
  chargeLow,
  chargeCritical,
  disconnectDepleted,
}

class H20BatteryAlertPolicy {
  final Map<String, _BatteryAlerts> _devices = {};

  List<H20BatteryAction> observe({
    required bool connected,
    required String? deviceId,
    required int? batteryPercent,
  }) {
    if (!connected ||
        batteryPercent == null ||
        batteryPercent < 0 ||
        batteryPercent > 100) {
      return const [];
    }
    final id = deviceId?.trim();
    final state = _devices.putIfAbsent(
      id == null || id.isEmpty ? 'unknown-h20' : id,
      _BatteryAlerts.new,
    );
    final percent = batteryPercent;
    if (percent >= 25) state.soon = false;
    if (percent >= 13) state.low = false;
    if (percent >= 8) state.critical = false;
    if (percent > 0) state.depleted = false;

    final actions = <H20BatteryAction>[];
    if (percent < 5) {
      state.soon = state.low = true;
      if (!state.critical) actions.add(H20BatteryAction.chargeCritical);
      state.critical = true;
    } else if (percent < 10) {
      state.soon = true;
      if (!state.low) actions.add(H20BatteryAction.chargeLow);
      state.low = true;
    } else if (percent < 20) {
      if (!state.soon) actions.add(H20BatteryAction.chargeSoon);
      state.soon = true;
    }
    if (percent == 0 && !state.depleted) {
      state.depleted = true;
      actions.add(H20BatteryAction.disconnectDepleted);
    }
    return actions;
  }
}

class _BatteryAlerts {
  bool soon = false;
  bool low = false;
  bool critical = false;
  bool depleted = false;
}
