import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

part 'app_event.dart';
part 'app_state.dart';

typedef AppStartupLoader = Future<AppStartupSnapshot> Function();

/// Owns application access/readiness only. No Bluetooth, audio, settings,
/// persistence implementation, BuildContext or Navigator is held here.
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc({
    required AppStartupLoader initialize,
    required void Function() onResumed,
    void Function(Object, StackTrace)? onFailure,
  }) : _initialize = initialize,
       _onResumed = onResumed,
       _onFailure = onFailure,
       super(const AppState()) {
    on<AppEvent>(_handle);
  }

  final AppStartupLoader _initialize;
  final void Function() _onResumed;
  final void Function(Object, StackTrace)? _onFailure;
  final _closingSignal = Completer<AppStartupSnapshot?>();
  Future<void>? _initialization;
  bool _loading = false;
  bool _closing = false;
  int _revision = 0;

  Future<void> initialize() {
    if (_closing || isClosed) return Future.value();
    return _initialization ??= dispatch(
      AppStarted(),
    ).whenComplete(() => _initialization = null);
  }

  Future<void> dispatch(AppEvent event) {
    if (_closing || isClosed) return Future.value();
    add(event);
    return event._completed.future;
  }

  Future<void> _handle(AppEvent event, Emitter<AppState> emit) async {
    try {
      if (_closing) return;
      switch (event) {
        case AppStarted():
          if (_loading ||
              (!state.isLoading &&
                  state.status != AppStatus.initializationFailed)) {
            return;
          }
          _loading = true;
          final revision = ++_revision;
          emit(const AppState(status: AppStatus.initializing));
          try {
            final snapshot = await Future.any<AppStartupSnapshot?>([
              _initialize(),
              _closingSignal.future,
            ]);
            if (_closing || revision != _revision || snapshot == null) return;
            final consent = snapshot.privacyConsentGranted;
            final limited = snapshot.limitedModeSelected && !consent;
            emit(
              AppState(
                status:
                    snapshot.setupCompleted &&
                        snapshot.hasValidProfile &&
                        (consent || limited)
                    ? AppStatus.ready
                    : AppStatus.onboardingRequired,
                privacyConsentGranted: consent,
                usageMode: limited ? AppUsageMode.limited : AppUsageMode.full,
              ),
            );
          } catch (error, stack) {
            if (!_closing && revision == _revision) {
              emit(
                const AppState(
                  status: AppStatus.initializationFailed,
                  failure: AppInitializationFailure.startupUnavailable,
                ),
              );
              _report(error, stack);
            }
          } finally {
            _loading = false;
          }
        case AppConsentGranted():
          ++_revision;
          emit(
            AppState(
              status: state.isReady
                  ? AppStatus.ready
                  : AppStatus.onboardingRequired,
              privacyConsentGranted: true,
            ),
          );
        case AppLimitedModeSelected():
          ++_revision;
          emit(
            AppState(
              status: state.isReady
                  ? AppStatus.ready
                  : AppStatus.onboardingRequired,
              usageMode: AppUsageMode.limited,
            ),
          );
        case AppOnboardingCompleted():
          if (!event.hasValidProfile ||
              (!state.privacyConsentGranted && !state.isLimited) ||
              state.isLoading ||
              state.failure != null) {
            return;
          }
          ++_revision;
          emit(
            AppState(
              status: AppStatus.ready,
              usageMode: state.usageMode,
              privacyConsentGranted: state.privacyConsentGranted,
            ),
          );
        case AppOnboardingReopened():
          ++_revision;
          emit(
            AppState(
              status: AppStatus.onboardingRequired,
              privacyConsentGranted: state.privacyConsentGranted,
            ),
          );
        case AppConsentRevoked():
          ++_revision;
          emit(const AppState(status: AppStatus.onboardingRequired));
        case AppResumed():
          // Retain the legacy ordering and don't reload stored consent over a
          // user's in-memory choice or turn a profile disconnect into app failure.
          _onResumed();
      }
    } catch (error, stack) {
      _report(error, stack);
    } finally {
      if (!event._completed.isCompleted) event._completed.complete();
    }
  }

  void _report(Object error, StackTrace stack) {
    try {
      _onFailure?.call(error, stack);
    } catch (_) {
      /* Reporting is optional. */
    }
  }

  @override
  Future<void> close() {
    _closing = true;
    ++_revision;
    if (!_closingSignal.isCompleted) _closingSignal.complete(null);
    return super.close();
  }
}
