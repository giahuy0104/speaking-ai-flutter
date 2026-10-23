import 'package:ai_speaking_flutter_app/data/settings/background_media_settings_store.dart';
import 'package:ai_speaking_flutter_app/core/audio/background_media_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:ai_speaking_flutter_app/data/settings/stored_settings_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android keeps HOMI media running by default and persists an override',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const store = SharedPreferencesParentMediaSettingsStore();

      expect(await store.readStopMediaWhenBackgrounded(), isFalse);

      await store.writeStopMediaWhenBackgrounded(true);

      expect(await store.readStopMediaWhenBackgrounded(), isTrue);
    },
  );

  test('iOS retains the stop-on-background default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      await const SharedPreferencesParentMediaSettingsStore()
          .readStopMediaWhenBackgrounded(),
      isTrue,
    );
  });

  test(
    'SettingsRepository reads and writes the existing media preference key',
    () async {
      SharedPreferences.setMockInitialValues({
        'homi.parent.stop-media-when-backgrounded.v1': false,
      });
      const repository = StoredSettingsRepository();
      expect(await repository.readStopMediaWhenBackgrounded(), isFalse);
      await repository.writeStopMediaWhenBackgrounded(true);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getBool('homi.parent.stop-media-when-backgrounded.v1'),
        isTrue,
      );
      expect(
        await const SharedPreferencesParentMediaSettingsStore()
            .readStopMediaWhenBackgrounded(),
        isTrue,
      );
    },
  );

  test('lifecycle policy stops only after HOMI has left the foreground', () {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(shouldStopMediaForLifecycle(state: state, enabled: true), isTrue);
    }

    for (final state in <AppLifecycleState>[
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
    ]) {
      expect(shouldStopMediaForLifecycle(state: state, enabled: true), isFalse);
    }

    for (final state in AppLifecycleState.values) {
      expect(
        shouldStopMediaForLifecycle(state: state, enabled: false),
        isFalse,
      );
    }
  });
}
