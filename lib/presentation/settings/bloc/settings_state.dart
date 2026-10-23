part of 'settings_bloc.dart';

class SettingsFailure {
  const SettingsFailure(this.field, this.operation);
  final SettingsField field;
  final SettingsOperation operation;
}

class SettingsState {
  SettingsState({
    this.themeMode = ThemeMode.system,
    this.displayLanguage = DisplayLanguage.vietnamese,
    this.childAge,
    this.vadSilenceMs = 700,
    this.stopMediaWhenBackgrounded = true,
    Set<SettingsField> loadingFields = const {},
    Set<SettingsField> savingFields = const {},
    Set<SettingsField> loadedFields = const {},
    Map<SettingsField, SettingsFailure> failures = const {},
  }) : loadingFields = Set.unmodifiable(loadingFields),
       savingFields = Set.unmodifiable(savingFields),
       loadedFields = Set.unmodifiable(loadedFields),
       failures = Map.unmodifiable(failures);
  final ThemeMode themeMode;
  final DisplayLanguage displayLanguage;
  final int? childAge;
  // VAD is session-only, matching the existing controller behavior.
  final int vadSilenceMs;
  final bool stopMediaWhenBackgrounded;
  final Set<SettingsField> loadingFields;
  final Set<SettingsField> savingFields;
  final Set<SettingsField> loadedFields;
  final Map<SettingsField, SettingsFailure> failures;
  bool get loading => loadingFields.isNotEmpty;
  bool get saving => savingFields.isNotEmpty;

  SettingsState copyWith({
    ThemeMode? themeMode,
    DisplayLanguage? displayLanguage,
    int? childAge,
    int? vadSilenceMs,
    bool? stopMediaWhenBackgrounded,
    bool clearChildAge = false,
    Set<SettingsField>? loadingFields,
    Set<SettingsField>? savingFields,
    Set<SettingsField>? loadedFields,
    Map<SettingsField, SettingsFailure>? failures,
  }) => SettingsState(
    themeMode: themeMode ?? this.themeMode,
    displayLanguage: displayLanguage ?? this.displayLanguage,
    childAge: clearChildAge ? null : childAge ?? this.childAge,
    vadSilenceMs: vadSilenceMs ?? this.vadSilenceMs,
    stopMediaWhenBackgrounded:
        stopMediaWhenBackgrounded ?? this.stopMediaWhenBackgrounded,
    loadingFields: loadingFields ?? this.loadingFields,
    savingFields: savingFields ?? this.savingFields,
    loadedFields: loadedFields ?? this.loadedFields,
    failures: failures ?? this.failures,
  );
}
