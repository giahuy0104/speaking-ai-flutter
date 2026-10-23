import 'dart:async';

import 'package:ai_speaking_flutter_app/app/di/app_dependencies.dart';
import 'package:ai_speaking_flutter_app/presentation/app/bloc/app_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

AppStartupSnapshot snapshot({
  bool consent = false,
  bool limited = false,
  bool complete = false,
  bool profile = true,
}) => AppStartupSnapshot(
  privacyConsentGranted: consent,
  limitedModeSelected: limited,
  setupCompleted: complete,
  hasValidProfile: profile,
);

void main() {
  AppBloc create({AppStartupLoader? load, void Function()? resume}) {
    final deps = AppDependencies(
      initialize: load ?? () async => snapshot(),
      onResumed: resume ?? () {},
    );
    addTearDown(deps.dispose);
    return deps.bloc;
  }

  test(
    'first install progresses initial, initializing, onboarding without granting access',
    () async {
      final bloc = create();
      final states = <AppState>[];
      final sub = bloc.stream.listen(states.add);
      addTearDown(sub.cancel);
      expect(bloc.state.status, AppStatus.initial);
      await bloc.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.status), [
        AppStatus.initializing,
        AppStatus.onboardingRequired,
      ]);
      expect(bloc.state.privacyConsentGranted, isFalse);
      expect(bloc.state.isLimited, isFalse);
    },
  );

  for (final limited in [false, true]) {
    test(
      'restores completed ${limited ? 'limited' : 'full'} setup independently of any device',
      () async {
        final bloc = create(
          load: () async =>
              snapshot(consent: !limited, limited: limited, complete: true),
        );
        await bloc.initialize();
        expect(bloc.state.isReady, isTrue);
        expect(bloc.state.isLimited, limited);
        expect(bloc.state.privacyConsentGranted, !limited);
      },
    );
  }

  for (final missing in ['profile', 'consent', 'completion']) {
    test('stored completion cannot bypass missing $missing', () async {
      final bloc = create(
        load: () async => snapshot(
          consent: missing != 'consent',
          complete: missing != 'completion',
          profile: missing != 'profile',
        ),
      );
      await bloc.initialize();
      expect(bloc.state.status, AppStatus.onboardingRequired);
    });
  }

  test('consent takes precedence over stale limited-mode storage', () async {
    final bloc = create(
      load: () async => snapshot(consent: true, limited: true, complete: true),
    );
    await bloc.initialize();
    expect(
      bloc.state,
      const AppState(status: AppStatus.ready, privacyConsentGranted: true),
    );
  });

  test(
    'granting consent alone does not finish onboarding; completion requires profile',
    () async {
      final bloc = create();
      await bloc.initialize();
      await bloc.dispatch(AppOnboardingCompleted(hasValidProfile: true));
      expect(bloc.state.isReady, isFalse);
      await bloc.dispatch(AppConsentGranted());
      await bloc.dispatch(AppOnboardingCompleted(hasValidProfile: false));
      expect(bloc.state.isReady, isFalse);
      await bloc.dispatch(AppOnboardingCompleted(hasValidProfile: true));
      expect(bloc.state.isReady, isTrue);
    },
  );

  test(
    'limited setup, reopen, grant and revoke preserve access boundaries',
    () async {
      final bloc = create();
      await bloc.initialize();
      await bloc.dispatch(AppLimitedModeSelected());
      expect(bloc.state.isReady, isFalse);
      await bloc.dispatch(AppOnboardingCompleted(hasValidProfile: true));
      expect(bloc.state.isReady, isTrue);
      expect(bloc.state.privacyConsentGranted, isFalse);
      await bloc.dispatch(AppOnboardingReopened());
      expect(bloc.state.isLimited, isFalse);
      expect(bloc.state.isReady, isFalse);
      await bloc.dispatch(AppConsentGranted());
      expect(bloc.state.isReady, isFalse);
      await bloc.dispatch(AppOnboardingCompleted(hasValidProfile: true));
      await bloc.dispatch(AppConsentRevoked());
      expect(bloc.state, const AppState(status: AppStatus.onboardingRequired));
    },
  );

  test('initialization failure is typed and retry can recover', () async {
    var loads = 0;
    final bloc = create(
      load: () async {
        if (++loads == 1) throw StateError('preferences unavailable');
        return snapshot(consent: true, complete: true);
      },
    );
    await bloc.initialize();
    expect(bloc.state.status, AppStatus.initializationFailed);
    expect(bloc.state.failure, AppInitializationFailure.startupUnavailable);
    await bloc.initialize();
    expect(bloc.state.isReady, isTrue);
    expect(bloc.state.failure, isNull);
    expect(loads, 2);
    await bloc.initialize();
    expect(loads, 2, reason: 'A ready app must not reload over user choices');
  });

  test('duplicate startup joins the same load', () async {
    var loads = 0;
    final gate = Completer<AppStartupSnapshot>();
    final bloc = create(
      load: () {
        loads++;
        return gate.future;
      },
    );
    final first = bloc.initialize();
    final second = bloc.initialize();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(loads, 1);
    gate.complete(snapshot());
    await Future.wait([first, second]);
  });

  test('revocation invalidates late bootstrap consent and readiness', () async {
    final gate = Completer<AppStartupSnapshot>();
    final bloc = create(load: () => gate.future);
    final pending = bloc.initialize();
    await Future<void>.delayed(Duration.zero);
    await bloc.dispatch(AppConsentRevoked());
    gate.complete(snapshot(consent: true, complete: true));
    await pending;
    expect(bloc.state, const AppState(status: AppStatus.onboardingRequired));
  });

  test(
    'resume delegates once without replacing ready or reloading preferences',
    () async {
      var resumes = 0;
      var loads = 0;
      final bloc = create(
        load: () async {
          loads++;
          return snapshot(limited: true, complete: true);
        },
        resume: () => resumes++,
      );
      await bloc.initialize();
      final before = bloc.state;
      await bloc.dispatch(AppResumed());
      expect(identical(bloc.state, before), isTrue);
      expect(resumes, 1);
      expect(loads, 1);
    },
  );

  test(
    'resume error does not turn a ready app into a startup failure',
    () async {
      final bloc = create(
        load: () async => snapshot(consent: true, complete: true),
        resume: () => throw StateError('native unavailable'),
      );
      await bloc.initialize();
      await bloc.dispatch(AppResumed());
      expect(bloc.state.isReady, isTrue);
      expect(bloc.state.failure, isNull);
    },
  );

  test('dispose releases a pending load and ignores its late result', () async {
    final gate = Completer<AppStartupSnapshot>();
    final deps = AppDependencies(
      initialize: () => gate.future,
      onResumed: () => fail('closed'),
    );
    final pending = deps.bloc.initialize();
    await Future<void>.delayed(Duration.zero);
    await deps.dispose();
    await pending;
    gate.complete(snapshot(consent: true, complete: true));
    await Future<void>.delayed(Duration.zero);
    expect(deps.bloc.isClosed, isTrue);
    expect(deps.bloc.state.isReady, isFalse);
    await deps.bloc.dispatch(AppResumed());
  });

  test('DI instances do not share access state', () async {
    final first = create();
    final second = create();
    await Future.wait([first.initialize(), second.initialize()]);
    await first.dispatch(AppConsentGranted());
    expect(second.state.privacyConsentGranted, isFalse);
  });
}
