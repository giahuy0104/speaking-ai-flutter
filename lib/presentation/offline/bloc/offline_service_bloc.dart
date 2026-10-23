import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/offline/offline_service.dart';
import '../../../features/listening/application/android_offline_speech_model_service.dart';

part 'offline_service_event.dart';
part 'offline_service_state.dart';

class OfflineServiceBloc
    extends Bloc<OfflineServiceEvent, OfflineServiceState> {
  OfflineServiceBloc({required OfflineService service})
    : _service = service,
      super(OfflineServiceState(isAndroid: service.isAndroid)) {
    on<OfflineServiceEvent>(_handle);
  }
  final OfflineService _service;
  final _closedSignal = Completer<void>();
  Timer? _refreshTimer;
  bool _closing = false;
  bool _refreshing = false;
  bool _changing = false;
  bool _preparing = false;
  int _revision = 0;

  Future<void> dispatch(OfflineServiceEvent event) {
    if (_closing || isClosed) return Future.value();
    add(event);
    return event._completed.future;
  }

  Future<T> _wait<T>(Future<T> future) => Future.any([
    future,
    _closedSignal.future.then<T>((_) => throw const _OfflineClosed()),
  ]);

  Future<void> _handle(
    OfflineServiceEvent event,
    Emitter<OfflineServiceState> emit,
  ) async {
    try {
      if (_closing) return;
      switch (event) {
        case OfflineServiceRefreshRequested():
          await _refresh(emit);
        case OfflineServiceAutomaticDownloadChanged():
          await _change(event.enabled, emit);
        case _OfflineServicePrepareRequested():
          await _prepare(emit);
      }
    } on _OfflineClosed {
      // The native download may outlive its UI. Never update a closed scope.
    } finally {
      if (!event._completed.isCompleted) event._completed.complete();
    }
  }

  Future<void> _refresh(Emitter<OfflineServiceState> emit) async {
    if (_refreshing || _changing) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final consent = await _wait(_service.readConsent());
      if (_closing || revision != _revision) return;
      final status = await _wait(
        _service.readStatus(
          consent: consent,
          preparingIosModels: state.preparingIosModels,
        ),
      );
      if (_closing || revision != _revision) return;
      emit(state.copyWith(consent: consent, status: status, busy: false));
      _updateTimer();
    } on _OfflineClosed {
      rethrow;
    } catch (_) {
      if (!_closing && revision == _revision) emit(state.copyWith(busy: false));
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _change(bool enabled, Emitter<OfflineServiceState> emit) async {
    if (state.busy || _changing) return;
    _changing = true;
    ++_revision;
    final consent = enabled
        ? AndroidOfflineSpeechModelConsent.allowed
        : AndroidOfflineSpeechModelConsent.declined;
    emit(state.copyWith(consent: consent, busy: true, clearPreparation: true));
    try {
      await _wait(_service.writeConsent(consent));
      if (_closing) return;
      if (enabled) {
        emit(
          state.copyWith(
            preparation:
                AndroidOfflineSpeechModelPreparationResult.downloadRequested,
            status: const AndroidOfflineSpeechModelStatus(
              state: AndroidOfflineSpeechModelState.pending,
              appManaged: true,
            ),
            busy: false,
            notify: true,
          ),
        );
        _updateTimer();
        add(_OfflineServicePrepareRequested());
      } else {
        final status = await _wait(_service.disableDownloads());
        if (_closing) return;
        emit(state.copyWith(status: status, busy: false));
        _updateTimer();
      }
    } on _OfflineClosed {
      rethrow;
    } catch (_) {
      if (!_closing) {
        emit(state.copyWith(busy: false, notify: true, saveFailed: true));
      }
    } finally {
      _changing = false;
    }
  }

  Future<void> _prepare(Emitter<OfflineServiceState> emit) async {
    if (_preparing) return;
    _preparing = true;
    emit(state.copyWith(preparingIosModels: !state.isAndroid));
    try {
      await _wait(_service.prepareModels(isActive: () => !_closing));
    } on _OfflineClosed {
      rethrow;
    } catch (_) {
      // As before, re-read native status after preparation; avoid an unhandled
      // asynchronous plugin error escaping the UI's background task.
    } finally {
      _preparing = false;
      if (!_closing) {
        ++_revision;
        emit(state.copyWith(preparingIosModels: false));
        await _refresh(emit);
      }
    }
  }

  void _updateTimer() {
    if (state.status?.state == AndroidOfflineSpeechModelState.pending) {
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_closing) add(OfflineServiceRefreshRequested());
      });
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _refreshTimer?.cancel();
    _closedSignal.complete();
    await super.close();
    await _service.close();
  }
}

class _OfflineClosed implements Exception {
  const _OfflineClosed();
}
