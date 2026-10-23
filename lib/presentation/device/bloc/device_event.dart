part of 'device_bloc.dart';

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
  final DeviceConnectionState value;
}
