import 'package:flutter/material.dart' show ThemeMode;
import '../../domain/settings/settings_repository.dart';
import '../../l10n/display_language.dart';
import 'app_theme_mode_store.dart';
import 'child_age_store.dart';
import 'background_media_settings_store.dart';

/// Keeps the existing preference keys, native language file/web storage and
/// read fallbacks. Migration does not reset any installed user's settings.
class StoredSettingsRepository implements SettingsRepository {
  const StoredSettingsRepository({
    this.themeStore = const AppThemeModeStore(),
    this.languageStore = const DisplayLanguageStore(),
    this.ageStore = const ChildAgeStore(),
    this.mediaStore = const SharedPreferencesParentMediaSettingsStore(),
  });
  final AppThemeModeStore themeStore;
  final DisplayLanguageStore languageStore;
  final ChildAgeStore ageStore;
  final ParentMediaSettingsStore mediaStore;

  @override
  Future<ThemeMode> readTheme() => themeStore.read();
  @override
  Future<DisplayLanguage> readLanguage() => languageStore.read();
  @override
  Future<int?> readChildAge() => ageStore.read();
  @override
  Future<void> writeTheme(ThemeMode value) => themeStore.write(value);
  @override
  Future<void> writeLanguage(DisplayLanguage value) =>
      languageStore.write(value);
  @override
  Future<void> writeChildAge(int value) => ageStore.write(value);
  @override
  Future<void> clearChildAge() => ageStore.clear();
  @override
  Future<bool> readStopMediaWhenBackgrounded() =>
      mediaStore.readStopMediaWhenBackgrounded();
  @override
  Future<void> writeStopMediaWhenBackgrounded(bool enabled) =>
      mediaStore.writeStopMediaWhenBackgrounded(enabled);
}
