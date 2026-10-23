part of 'settings_bloc.dart';

sealed class SettingsEvent {
  final _completed = Completer<void>();
}

final class SettingsLoadRequested extends SettingsEvent {
  SettingsLoadRequested(this.field);
  final SettingsField field;
}

final class SettingsThemeChanged extends SettingsEvent {
  SettingsThemeChanged(this.value);
  final ThemeMode value;
}

final class SettingsLanguageChanged extends SettingsEvent {
  SettingsLanguageChanged(this.value);
  final DisplayLanguage value;
}

final class SettingsChildAgeChanged extends SettingsEvent {
  SettingsChildAgeChanged(this.value);
  final int value;
}

final class SettingsChildAgeCleared extends SettingsEvent {}

final class SettingsRetryRequested extends SettingsEvent {
  SettingsRetryRequested(this.field);
  final SettingsField field;
}

final class SettingsVadSilenceChanged extends SettingsEvent {
  SettingsVadSilenceChanged(this.milliseconds);
  final int milliseconds;
}

final class SettingsStopMediaWhenBackgroundedChanged extends SettingsEvent {
  SettingsStopMediaWhenBackgroundedChanged(this.enabled);
  final bool enabled;
}
