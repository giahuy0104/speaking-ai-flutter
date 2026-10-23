import 'package:flutter/material.dart' show ThemeMode;
import '../../l10n/display_language.dart';

enum SettingsField { theme, language, childAge, stopMediaWhenBackgrounded }

enum SettingsOperation { read, write }

/// Preference boundary. No controller, navigation or device connection work.
abstract interface class SettingsRepository {
  Future<ThemeMode> readTheme();
  Future<DisplayLanguage> readLanguage();
  Future<int?> readChildAge();
  Future<void> writeTheme(ThemeMode value);
  Future<void> writeLanguage(DisplayLanguage value);
  Future<void> writeChildAge(int value);
  Future<void> clearChildAge();
  Future<bool> readStopMediaWhenBackgrounded();
  Future<void> writeStopMediaWhenBackgrounded(bool enabled);
}
