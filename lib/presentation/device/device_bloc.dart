import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/device/device_connection_service.dart';
import '../../domain/device/device_connection.dart';

sealed class DeviceEvent {
  const DeviceEvent();
}

class DeviceConnectRequested extends DeviceEvent {
  DeviceConnectRequested({
    this.interactive = true,
    this.chooseMicrophone = false,
    Completer<bool>? result,
  }) : result = result ?? Completer<bool>();
  final bool interactive;
  final bool chooseMicrophone;
  final Completer<bool> result;
}

class DeviceCancelRequested extends DeviceEvent {
  DeviceCancelRequested() : result = Completer<void>();
  final Completer<void> result;
}

class DeviceMicrophoneSelected extends DeviceEvent {
  const DeviceMicrophoneSelected(this.attempt, this.selection);
  final int attempt;
  final DeviceSelection? selection;
}

class _DeviceStateChanged extends DeviceEvent {
  const _DeviceStateChanged(this.value);
  final DeviceState value;
}

/// Constructor injection keeps Bluetooth operations out of presentation.
/// Events remain concurrent so Cancel/Selection can finish a pending Connect.
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> {
  DeviceBloc({required DeviceConnectionService service})
    : _service = service,
      super(service.state) {
    on<_DeviceStateChanged>((event, emit) => emit(event.value));
    on<DeviceConnectRequested>((event, emit) async {
      if (_closing) {
        event.result.complete(false);
        return;
      }
      try {
        final ready = await _service.connect(
          interactive: event.interactive,
          chooseMicrophone: event.chooseMicrophone,
        );
        if (!event.result.isCompleted) event.result.complete(ready);
      } catch (error, stack) {
        if (!event.result.isCompleted) event.result.completeError(error, stack);
      }
    });
    on<DeviceCancelRequested>((event, emit) async {
      try {
        await _service.cancel();
        event.result.complete();
      } catch (error, stack) {
        event.result.completeError(error, stack);
      }
    });
    on<DeviceMicrophoneSelected>(
      (event, emit) =>
          _service.selectMicrophone(event.attempt, event.selection),
    );
    _subscription = service.states.listen((state) {
      if (!isClosed && !_closing) add(_DeviceStateChanged(state));
    });
  }
  final DeviceConnectionService _service;
  bool _closing = false;
  late final StreamSubscription<DeviceState> _subscription;

  Future<bool> connect({
    bool interactive = true,
    bool chooseMicrophone = false,
  }) {
    if (isClosed || _closing) return Future.value(false);
    final event = DeviceConnectRequested(
      interactive: interactive,
      chooseMicrophone: chooseMicrophone,
    );
    add(event);
    return event.result.future;
  }

  Future<void> cancelAttempt() {
    if (isClosed || _closing) return Future.value();
    final event = DeviceCancelRequested();
    add(event);
    return event.result.future;
  }

  @override
  Future<void> close() async {
    _closing = true;
    if (_service.state.busy) await _service.cancel();
    await _subscription.cancel();
    return super.close();
  }
}
