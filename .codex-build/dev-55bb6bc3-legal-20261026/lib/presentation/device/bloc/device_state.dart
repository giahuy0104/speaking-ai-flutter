part of 'device_bloc.dart';

/// Presentation state mirrors the service model without making core/domain
/// depend on Bloc. Connection behavior remains owned by the service.
class DeviceState extends DeviceConnectionState {
  const DeviceState({
    super.stage,
    super.snapshot,
    super.issue,
    super.attempt,
    super.microphones,
  });

  factory DeviceState.fromConnectionState(DeviceConnectionState state) =>
      DeviceState(
        stage: state.stage,
        snapshot: state.snapshot,
        issue: state.issue,
        attempt: state.attempt,
        microphones: state.microphones,
      );
}
