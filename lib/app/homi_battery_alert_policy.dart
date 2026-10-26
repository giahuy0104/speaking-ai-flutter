enum HomiBatteryAction {
  chargeSoon,
  chargeLow,
  chargeCritical,
  disconnectDepleted,
}

class HomiBatteryAlertPolicy {
  final Map<String, _BatteryAlerts> _devices = {};

  List<HomiBatteryAction> observe({
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
      id == null || id.isEmpty ? 'unknown-hm-d001' : id,
      _BatteryAlerts.new,
    );
    final percent = batteryPercent;
    if (percent >= 25) state.soon = false;
    if (percent >= 13) state.low = false;
    if (percent >= 8) state.critical = false;
    if (percent > 0) state.depleted = false;

    final actions = <HomiBatteryAction>[];
    if (percent < 5) {
      state.soon = state.low = true;
      if (!state.critical) actions.add(HomiBatteryAction.chargeCritical);
      state.critical = true;
    } else if (percent < 10) {
      state.soon = true;
      if (!state.low) actions.add(HomiBatteryAction.chargeLow);
      state.low = true;
    } else if (percent < 20) {
      if (!state.soon) actions.add(HomiBatteryAction.chargeSoon);
      state.soon = true;
    }
    if (percent == 0 && !state.depleted) {
      state.depleted = true;
      actions.add(HomiBatteryAction.disconnectDepleted);
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
