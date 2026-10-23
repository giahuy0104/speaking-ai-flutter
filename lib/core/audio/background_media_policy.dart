import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Android is designed to keep an explicit HOMI/HM-D001 session alive when the
/// child opens another application. Other platforms retain the conservative
/// stop-on-background default until their background audio flow is handled
/// separately.
bool defaultStopMediaWhenBackgrounded() =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.android;

bool shouldStopMediaForLifecycle({
  required AppLifecycleState state,
  required bool enabled,
}) {
  if (!enabled) return false;
  return state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}
