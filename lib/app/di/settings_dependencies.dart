import '../../data/settings/stored_settings_repository.dart';
import '../../core/audio/background_media_policy.dart';
import '../../domain/settings/settings_repository.dart';
import '../../l10n/display_language.dart';
import '../../presentation/settings/bloc/settings_bloc.dart';

class SettingsDependencies {
  SettingsDependencies({
    SettingsRepository repository = const StoredSettingsRepository(),
    required int? Function(int?) validateAge,
    required void Function(DisplayLanguage) onLanguageApplied,
    required void Function(int?) onChildAgeApplied,
    bool? initialStopMediaWhenBackgrounded,
    bool Function()? canChangeVad,
    void Function(int)? onVadApplied,
  }) : bloc = SettingsBloc(
         repository: repository,
         validateAge: validateAge,
         onLanguageApplied: onLanguageApplied,
         onChildAgeApplied: onChildAgeApplied,
         initialStopMediaWhenBackgrounded:
             initialStopMediaWhenBackgrounded ??
             defaultStopMediaWhenBackgrounded(),
         canChangeVad: canChangeVad,
         onVadApplied: onVadApplied,
       );
  final SettingsBloc bloc;
  Future<void> dispose() => bloc.close();
}
