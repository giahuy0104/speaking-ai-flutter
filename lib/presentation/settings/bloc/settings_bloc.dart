import 'dart:async';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/settings/settings_repository.dart';
import '../../../l10n/display_language.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({
    required SettingsRepository repository,
    required int? Function(int?) validateAge,
    required void Function(DisplayLanguage) onLanguageApplied,
    required void Function(int?) onChildAgeApplied,
    bool initialStopMediaWhenBackgrounded = true,
    bool Function()? canChangeVad,
    void Function(int)? onVadApplied,
  }) : _repository = repository,
       _validateAge = validateAge,
       _onLanguageApplied = onLanguageApplied,
       _onChildAgeApplied = onChildAgeApplied,
       _canChangeVad = canChangeVad,
       _onVadApplied = onVadApplied,
       super(
         SettingsState(
           stopMediaWhenBackgrounded: initialStopMediaWhenBackgrounded,
         ),
       ) {
    on<SettingsEvent>(_handle);
  }
  final bool Function()? _canChangeVad;
  final void Function(int)? _onVadApplied;
  final SettingsRepository _repository;
  final int? Function(int?) _validateAge;
  final void Function(DisplayLanguage) _onLanguageApplied;
  final void Function(int?) _onChildAgeApplied;
  final _revisions = <SettingsField, int>{};
  final _loads = <SettingsField, Future<void>>{};
  final _writes = <SettingsField, Future<void>>{};
  final _pendingWrites = <SettingsField, int>{};
  final _closedSignal = Completer<void>();
  bool _closing = false;

  Future<void> dispatch(SettingsEvent event) {
    if (_closing || isClosed) return Future.value();
    add(event);
    return event._completed.future;
  }

  Future<void> load() async {
    await Future.wait(SettingsField.values.map(loadField));
  }

  Future<void> loadField(SettingsField field) {
    if (_closing || state.loadedFields.contains(field)) return Future.value();
    return _loads[field] ??= dispatch(SettingsLoadRequested(field))
        .whenComplete(() {
          _loads.remove(field);
        });
  }

  Object? _value(SettingsField field) => switch (field) {
    SettingsField.theme => state.themeMode,
    SettingsField.language => state.displayLanguage,
    SettingsField.childAge => state.childAge,
    SettingsField.stopMediaWhenBackgrounded => state.stopMediaWhenBackgrounded,
  };
  Future<Object?> _read(SettingsField field) => switch (field) {
    SettingsField.theme => _repository.readTheme(),
    SettingsField.language => _repository.readLanguage(),
    SettingsField.childAge => _repository.readChildAge(),
    SettingsField.stopMediaWhenBackgrounded =>
      _repository.readStopMediaWhenBackgrounded(),
  };
  Future<void> _write(SettingsField field, Object? value) => switch (field) {
    SettingsField.theme => _repository.writeTheme(value as ThemeMode),
    SettingsField.language => _repository.writeLanguage(
      value as DisplayLanguage,
    ),
    SettingsField.childAge =>
      value == null
          ? _repository.clearChildAge()
          : _repository.writeChildAge(value as int),
    SettingsField.stopMediaWhenBackgrounded =>
      _repository.writeStopMediaWhenBackgrounded(value as bool),
  };
  void _apply(SettingsField field, Object? value, Emitter<SettingsState> emit) {
    emit(switch (field) {
      SettingsField.theme => state.copyWith(themeMode: value as ThemeMode),
      SettingsField.stopMediaWhenBackgrounded => state.copyWith(
        stopMediaWhenBackgrounded: value as bool,
      ),
      SettingsField.language => state.copyWith(
        displayLanguage: value as DisplayLanguage,
      ),
      SettingsField.childAge => state.copyWith(
        childAge: value as int?,
        clearChildAge: value == null,
      ),
    });
    switch (field) {
      case SettingsField.theme:
      case SettingsField.stopMediaWhenBackgrounded:
        break;
      case SettingsField.language:
        _onLanguageApplied(value as DisplayLanguage);
      case SettingsField.childAge:
        _onChildAgeApplied(value as int?);
    }
  }

  Future<void> _handle(SettingsEvent event, Emitter<SettingsState> emit) async {
    try {
      if (_closing) return;
      switch (event) {
        case SettingsLoadRequested():
          await _load(event.field, emit);
        case SettingsThemeChanged():
          await _save(SettingsField.theme, event.value, emit);
        case SettingsLanguageChanged():
          await _save(SettingsField.language, event.value, emit);
        case SettingsChildAgeChanged():
          if (_validateAge(event.value) == event.value) {
            await _save(SettingsField.childAge, event.value, emit);
          }
        case SettingsVadSilenceChanged():
          // No storage write: this setting has always reset with the runtime.
          if (_canChangeVad?.call() != false) {
            final value = event.milliseconds.clamp(400, 1600).toInt();
            _onVadApplied?.call(value);
            emit(state.copyWith(vadSilenceMs: value));
          }
        case SettingsStopMediaWhenBackgroundedChanged():
          await _save(
            SettingsField.stopMediaWhenBackgrounded,
            event.enabled,
            emit,
          );
        case SettingsChildAgeCleared():
          await _save(SettingsField.childAge, null, emit);
        case SettingsRetryRequested():
          final failure = state.failures[event.field];
          if (failure?.operation == SettingsOperation.read) {
            await _load(event.field, emit);
          } else if (failure != null) {
            await _save(event.field, _value(event.field), emit);
          }
      }
    } finally {
      if (!event._completed.isCompleted) event._completed.complete();
    }
  }

  Future<void> _load(SettingsField field, Emitter<SettingsState> emit) async {
    if (state.loadingFields.contains(field) ||
        state.loadedFields.contains(field)) {
      return;
    }
    final revision = _revisions[field] ?? 0;
    emit(state.copyWith(loadingFields: {...state.loadingFields, field}));
    try {
      final value = await Future.any<Object?>([
        _read(field),
        _closedSignal.future,
      ]);
      if (_closing) return;
      if (revision == (_revisions[field] ?? 0)) {
        _apply(
          field,
          field == SettingsField.childAge ? _validateAge(value as int?) : value,
          emit,
        );
        emit(state.copyWith(failures: {...state.failures}..remove(field)));
      }
      emit(state.copyWith(loadedFields: {...state.loadedFields, field}));
    } catch (_) {
      if (!_closing && revision == (_revisions[field] ?? 0)) {
        emit(
          state.copyWith(
            failures: {
              ...state.failures,
              field: SettingsFailure(field, SettingsOperation.read),
            },
          ),
        );
      }
    } finally {
      if (!_closing) {
        emit(
          state.copyWith(
            loadingFields: {...state.loadingFields}..remove(field),
          ),
        );
      }
    }
  }

  Future<void> _save(
    SettingsField field,
    Object? value,
    Emitter<SettingsState> emit,
  ) async {
    final revision = (_revisions[field] ?? 0) + 1;
    _revisions[field] = revision;
    _pendingWrites[field] = (_pendingWrites[field] ?? 0) + 1;
    _apply(
      field,
      value,
      emit,
    ); // Same immediate UI update as the legacy setters.
    emit(
      state.copyWith(
        savingFields: {...state.savingFields, field},
        // A local choice is authoritative even if startup hydration has not begun.
        loadedFields: {...state.loadedFields, field},
        failures: {...state.failures}..remove(field),
      ),
    );
    // Serialize storage for each preference so rapid taps cannot persist an
    // older choice after the latest one. Different preferences remain independent.
    final previous = _writes[field] ?? Future<void>.value();
    final write = previous.then((_) => _write(field, value));
    _writes[field] = write.catchError((Object _) {});
    try {
      await Future.any<void>([write, _closedSignal.future]);
    } catch (_) {
      if (!_closing && _revisions[field] == revision) {
        emit(
          state.copyWith(
            failures: {
              ...state.failures,
              field: SettingsFailure(field, SettingsOperation.write),
            },
          ),
        );
      }
    } finally {
      _pendingWrites[field] = _pendingWrites[field]! - 1;
      if (!_closing && _pendingWrites[field] == 0) {
        emit(
          state.copyWith(savingFields: {...state.savingFields}..remove(field)),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    return super.close();
  }
}
