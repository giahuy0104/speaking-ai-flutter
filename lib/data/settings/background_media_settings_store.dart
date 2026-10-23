import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/background_media_policy.dart';

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
      return preferences.getBool(_stopMediaWhenBackgroundedKey) ??
          defaultStopMediaWhenBackgrounded();
    } catch (_) {
      return defaultStopMediaWhenBackgrounded();
    }
  }

  @override
  Future<void> writeStopMediaWhenBackgrounded(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_stopMediaWhenBackgroundedKey, enabled);
  }
}
