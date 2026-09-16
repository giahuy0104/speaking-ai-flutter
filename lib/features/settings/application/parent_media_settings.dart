import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ParentMediaSettingsStore {
  Future<bool> readStopMediaWhenBackgrounded();

  Future<void> writeStopMediaWhenBackgrounded(bool enabled);
}

class SharedPreferencesParentMediaSettingsStore
    implements ParentMediaSettingsStore {
  const SharedPreferencesParentMediaSettingsStore();

  static const String _stopMediaWhenBackgroundedKey =
      'homi.parent.stop-media-when-backgrounded.v1';

  @override
  Future<bool> readStopMediaWhenBackgrounded() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_stopMediaWhenBackgroundedKey) ?? true;
    } catch (_) {
      // Failing closed keeps HOMI from unexpectedly speaking over another app.
      return true;
    }
  }

  @override
  Future<void> writeStopMediaWhenBackgrounded(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_stopMediaWhenBackgroundedKey, enabled);
  }
}

bool shouldStopMediaForLifecycle({
  required AppLifecycleState state,
  required bool enabled,
}) {
  if (!enabled) return false;
  return state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}
