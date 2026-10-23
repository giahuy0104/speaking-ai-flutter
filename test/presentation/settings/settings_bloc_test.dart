import 'dart:async';

import 'package:ai_speaking_flutter_app/app/di/settings_dependencies.dart';
import 'package:ai_speaking_flutter_app/domain/settings/settings_repository.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/presentation/settings/bloc/settings_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSettingsRepository repository;
  late SettingsDependencies dependencies;
  late SettingsBloc bloc;
  late List<DisplayLanguage> languages;
  late List<int?> ages;
  late List<int> vadValues;
  late bool allowVad;
  setUp(() {
    repository = FakeSettingsRepository();
    languages = [];
    ages = [];
    vadValues = [];
    allowVad = true;
    dependencies = SettingsDependencies(
      repository: repository,
      canChangeVad: () => allowVad,
      onVadApplied: vadValues.add,
      validateAge: (age) => age != null && age >= 3 && age <= 15 ? age : null,
      onLanguageApplied: languages.add,
      onChildAgeApplied: ages.add,
    );
    bloc = dependencies.bloc;
  });
  tearDown(() => dependencies.dispose());

  test(
    'restores preferences once and projects language/age to runtime',
    () async {
      repository.theme = ThemeMode.dark;
      repository.language = DisplayLanguage.simplifiedChinese;
      repository.age = 8;
      await Future.wait([bloc.load(), bloc.load()]);
      expect(bloc.state.themeMode, ThemeMode.dark);
      expect(bloc.state.displayLanguage, DisplayLanguage.simplifiedChinese);
      expect(bloc.state.childAge, 8);
      expect(bloc.state.loadedFields, SettingsField.values.toSet());
      expect(bloc.state.loading, isFalse);
      expect(repository.reads, 4);
      expect(languages, [DisplayLanguage.simplifiedChinese]);
      expect(ages, [8]);
      await bloc.load();
      expect(repository.reads, 4);
    },
  );

  test(
    'VAD is session-only, clamped, and not reset by preference hydration',
    () async {
      expect(bloc.state.vadSilenceMs, 700);
      await bloc.dispatch(SettingsVadSilenceChanged(100));
      expect(bloc.state.vadSilenceMs, 400);
      await bloc.dispatch(SettingsVadSilenceChanged(9999));
      expect(bloc.state.vadSilenceMs, 1600);
      await bloc.dispatch(SettingsVadSilenceChanged(1100));
      await bloc.load();
      expect(bloc.state.vadSilenceMs, 1100);
      expect(vadValues, [400, 1600, 1100]);
      expect(repository.writes, isEmpty);
      expect(bloc.state.saving, isFalse);
      final fresh = SettingsDependencies(
        repository: repository,
        validateAge: (value) => value,
        onLanguageApplied: (_) {},
        onChildAgeApplied: (_) {},
      );
      await fresh.bloc.load();
      expect(fresh.bloc.state.vadSilenceMs, 700);
      await fresh.dispose();
    },
  );

  test(
    'VAD checks busy at handling time and ignores changes after dispose',
    () async {
      final pending = bloc.dispatch(SettingsVadSilenceChanged(900));
      allowVad = false;
      await pending;
      expect(bloc.state.vadSilenceMs, 700);
      expect(vadValues, isEmpty);
      allowVad = true;
      await bloc.dispatch(SettingsVadSilenceChanged(900));
      expect(vadValues, [900]);
      await dependencies.dispose();
      await bloc.dispatch(SettingsVadSilenceChanged(1200));
      expect(vadValues, [900]);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('media default matches existing policy: $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final scope = SettingsDependencies(
        repository: repository,
        validateAge: (value) => value,
        onLanguageApplied: (_) {},
        onChildAgeApplied: (_) {},
      );
      expect(
        scope.bloc.state.stopMediaWhenBackgrounded,
        platform != TargetPlatform.android,
      );
      repository.stopMedia = true;
      await scope.bloc.loadField(SettingsField.stopMediaWhenBackgrounded);
      expect(scope.bloc.state.stopMediaWhenBackgrounded, isTrue);
      await scope.dispose();
    });
  }

  test('media writes stay ordered and failed choice can be retried', () async {
    final gate = Completer<void>();
    repository.writeGate = gate.future;
    final first = bloc.dispatch(SettingsStopMediaWhenBackgroundedChanged(true));
    await flush();
    final last = bloc.dispatch(SettingsStopMediaWhenBackgroundedChanged(false));
    await flush();
    expect(bloc.state.stopMediaWhenBackgrounded, isFalse);
    expect(repository.writes, ['media:true']);
    gate.complete();
    await Future.wait([first, last]);
    expect(repository.writes, ['media:true', 'media:false']);
    expect(repository.stopMedia, isFalse);
    repository.failWrites = true;
    await bloc.dispatch(SettingsStopMediaWhenBackgroundedChanged(true));
    expect(bloc.state.stopMediaWhenBackgrounded, isTrue);
    expect(
      bloc.state.failures[SettingsField.stopMediaWhenBackgrounded]?.operation,
      SettingsOperation.write,
    );
    repository.failWrites = false;
    await bloc.dispatch(
      SettingsRetryRequested(SettingsField.stopMediaWhenBackgrounded),
    );
    expect(repository.stopMedia, isTrue);
    expect(bloc.state.failures, isEmpty);
  });

  test('invalid stored age does not become a valid child profile', () async {
    repository.age = 99;
    await bloc.load();
    expect(bloc.state.childAge, isNull);
    await bloc.dispatch(SettingsChildAgeChanged(99));
    expect(repository.writes, isEmpty);
    expect(ages, [null]);
  });

  for (final field in SettingsField.values) {
    test('late startup read cannot overwrite newer choice: $field', () async {
      final gate = Completer<Object?>();
      repository.readGate = gate.future;
      final reading = bloc.loadField(field);
      await flush();
      final SettingsEvent event = switch (field) {
        SettingsField.theme => SettingsThemeChanged(ThemeMode.dark),
        SettingsField.language => SettingsLanguageChanged(
          DisplayLanguage.simplifiedChinese,
        ),
        SettingsField.childAge => SettingsChildAgeChanged(11),
        SettingsField.stopMediaWhenBackgrounded =>
          SettingsStopMediaWhenBackgroundedChanged(true),
      };
      await bloc.dispatch(event);
      gate.complete(switch (field) {
        SettingsField.theme => ThemeMode.light,
        SettingsField.language => DisplayLanguage.vietnamese,
        SettingsField.childAge => 3,
        SettingsField.stopMediaWhenBackgrounded => false,
      });
      await reading;
      switch (field) {
        case SettingsField.theme:
          expect(bloc.state.themeMode, ThemeMode.dark);
        case SettingsField.language:
          expect(bloc.state.displayLanguage, DisplayLanguage.simplifiedChinese);
          expect(languages, [DisplayLanguage.simplifiedChinese]);
        case SettingsField.childAge:
          expect(bloc.state.childAge, 11);
          expect(ages, [11]);
        case SettingsField.stopMediaWhenBackgrounded:
          expect(bloc.state.stopMediaWhenBackgrounded, isTrue);
      }
    });
  }

  test(
    'rapid choices persist in order without blocking other preferences',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final first = bloc.dispatch(SettingsThemeChanged(ThemeMode.dark));
      await flush();
      final last = bloc.dispatch(SettingsThemeChanged(ThemeMode.light));
      final age = bloc.dispatch(SettingsChildAgeChanged(8));
      await flush();
      expect(bloc.state.themeMode, ThemeMode.light);
      expect(bloc.state.childAge, 8);
      expect(repository.writes, ['theme:dark', 'age:8']);
      expect(bloc.state.savingFields, {
        SettingsField.theme,
        SettingsField.childAge,
      });
      gate.complete();
      await Future.wait([first, last, age]);
      expect(repository.writes, ['theme:dark', 'age:8', 'theme:light']);
      expect(repository.theme, ThemeMode.light);
      expect(bloc.state.saving, isFalse);
    },
  );

  test(
    'choice made before startup load stays authoritative during pending write',
    () async {
      final gate = Completer<void>();
      repository.theme = ThemeMode.light;
      repository.writeGate = gate.future;
      final choice = bloc.dispatch(SettingsThemeChanged(ThemeMode.dark));
      // Queue the startup load immediately, before the event handler runs.
      final load = bloc.loadField(SettingsField.theme);
      await flush();
      await load;
      expect(repository.reads, 0);
      expect(bloc.state.themeMode, ThemeMode.dark);
      gate.complete();
      await choice;
      expect(repository.theme, ThemeMode.dark);
    },
  );

  test('failed write preserves choice and retries that choice', () async {
    repository.failWrites = true;
    await bloc.dispatch(
      SettingsLanguageChanged(DisplayLanguage.simplifiedChinese),
    );
    expect(bloc.state.displayLanguage, DisplayLanguage.simplifiedChinese);
    expect(
      bloc.state.failures[SettingsField.language]?.operation,
      SettingsOperation.write,
    );
    expect(bloc.state.saving, isFalse);
    repository.failWrites = false;
    await bloc.dispatch(SettingsRetryRequested(SettingsField.language));
    expect(repository.language, DisplayLanguage.simplifiedChinese);
    expect(bloc.state.failures, isEmpty);
  });

  test(
    'failure from an older write does not mark a newer choice failed',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final old = bloc.dispatch(SettingsThemeChanged(ThemeMode.dark));
      await flush();
      repository.writeGate = null;
      final latest = bloc.dispatch(SettingsThemeChanged(ThemeMode.light));
      await flush();
      gate.completeError(StateError('old write failed'));
      await Future.wait([old, latest]);
      expect(repository.theme, ThemeMode.light);
      expect(bloc.state.failures, isEmpty);
    },
  );

  test('read failure can be retried without changing defaults', () async {
    repository.failReads = true;
    await bloc.loadField(SettingsField.childAge);
    expect(bloc.state.childAge, isNull);
    expect(
      bloc.state.failures[SettingsField.childAge]?.operation,
      SettingsOperation.read,
    );
    repository.failReads = false;
    repository.age = 13;
    await bloc.dispatch(SettingsRetryRequested(SettingsField.childAge));
    expect(bloc.state.childAge, 13);
    expect(bloc.state.failures, isEmpty);
  });

  test(
    'privacy clear runs after pending age write so saved age stays removed',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final update = bloc.dispatch(SettingsChildAgeChanged(8));
      await flush();
      final clear = bloc.dispatch(SettingsChildAgeCleared());
      await flush();
      expect(bloc.state.childAge, isNull);
      gate.complete();
      await Future.wait([update, clear]);
      expect(repository.writes, ['age:8', 'age:clear']);
      expect(repository.age, isNull);
      expect(ages, [8, null]);
    },
  );

  test(
    'dispose releases pending read and ignores late runtime projection',
    () async {
      final gate = Completer<Object?>();
      repository.readGate = gate.future;
      final load = bloc.loadField(SettingsField.childAge);
      await flush();
      await dependencies.dispose();
      await load;
      gate.complete(8);
      await flush();
      expect(ages, isEmpty);
      expect(bloc.isClosed, isTrue);
    },
  );

  test(
    'dispose finishes accepted persistence without emitting closed state',
    () async {
      final gate = Completer<void>();
      repository.writeGate = gate.future;
      final write = bloc.dispatch(SettingsThemeChanged(ThemeMode.dark));
      await flush();
      await dependencies.dispose();
      await write;
      gate.complete();
      await flush();
      expect(repository.theme, ThemeMode.dark);
      expect(bloc.isClosed, isTrue);
    },
  );
}

class FakeSettingsRepository implements SettingsRepository {
  ThemeMode theme = ThemeMode.system;
  DisplayLanguage language = DisplayLanguage.vietnamese;
  int? age;
  bool stopMedia = false;
  int reads = 0;
  final writes = <String>[];
  Future<Object?>? readGate;
  Future<void>? writeGate;
  bool failReads = false;
  bool failWrites = false;
  Future<Object?> read(Object? value) async {
    reads++;
    if (failReads) throw StateError('read failed');
    return readGate == null ? value : await readGate;
  }

  Future<void> write(String value) async {
    writes.add(value);
    await writeGate;
    if (failWrites) throw StateError('write failed');
  }

  @override
  Future<bool> readStopMediaWhenBackgrounded() async =>
      await read(stopMedia) as bool;
  @override
  Future<void> writeStopMediaWhenBackgrounded(bool enabled) async {
    await write('media:$enabled');
    stopMedia = enabled;
  }

  @override
  Future<ThemeMode> readTheme() async => await read(theme) as ThemeMode;
  @override
  Future<DisplayLanguage> readLanguage() async =>
      await read(language) as DisplayLanguage;
  @override
  Future<int?> readChildAge() async => await read(age) as int?;
  @override
  Future<void> writeTheme(ThemeMode value) async {
    await write('theme:${value.name}');
    theme = value;
  }

  @override
  Future<void> writeLanguage(DisplayLanguage value) async {
    await write('language:${value.code}');
    language = value;
  }

  @override
  Future<void> writeChildAge(int value) async {
    await write('age:$value');
    age = value;
  }

  @override
  Future<void> clearChildAge() async {
    await write('age:clear');
    age = null;
  }
}
