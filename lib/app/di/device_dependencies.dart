import '../../core/device/device_connection_service.dart';
import '../../domain/device/device_connection.dart';
import '../../presentation/device/device_bloc.dart';

/// Explicit scoped DI. No global singleton: only onboarding receives this Bloc.
/// Tests inject a fake port without MethodChannels or a physical device.
class DeviceDependencies {
  DeviceDependencies({required DeviceConnectionPort port}) {
    service = DeviceConnectionService(port: port);
    bloc = DeviceBloc(service: service);
  }
  late final DeviceConnectionService service;
  late final DeviceBloc bloc;
  Future<void> dispose() async {
    await bloc.close();
    await service.dispose();
  }
}
