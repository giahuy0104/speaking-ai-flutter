import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/device/device_connection_diagnostics.dart';
import '../../core/device/device_connection_service.dart';
import '../../domain/device/device_connection.dart';
import '../../presentation/device/bloc/device_bloc.dart';

/// Explicit scoped DI. No global singleton: only onboarding receives this Bloc.
/// Tests inject a fake port without MethodChannels or a physical device.
class DeviceDependencies {
  DeviceDependencies({required DeviceConnectionPort port}) {
    service = DeviceConnectionService(
      port: port,
      diagnostics: DeviceConnectionDiagnostics(
        enabled:
            kDebugMode || const bool.fromEnvironment('HOMI_BLE_DIAGNOSTICS'),
        sink: (record) =>
            debugPrint('HomiConnectionDiag: ${jsonEncode(record)}'),
      ),
    );
    bloc = DeviceBloc(service: service);
  }
  late final DeviceConnectionService service;
  late final DeviceBloc bloc;
  Future<void> dispose() async {
    await bloc.close();
    await service.dispose();
  }
}
