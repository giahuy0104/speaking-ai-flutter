import 'package:ai_speaking_flutter_app/features/settings/application/parent_media_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stopping media outside HOMI defaults to enabled and persists',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesParentMediaSettingsStore();

      expect(await store.readStopMediaWhenBackgrounded(), isTrue);

      await store.writeStopMediaWhenBackgrounded(false);

      expect(await store.readStopMediaWhenBackgrounded(), isFalse);
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
