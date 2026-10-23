import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'audio_input.dart';
import '../device/device_connection_diagnostics.dart';
import '../device/homi_connection_state.dart';

class HfpAudioDevice {
  const HfpAudioDevice({
    required this.id,
    required this.name,
    required this.isConnected,
  });

  factory HfpAudioDevice.fromJson(Map<dynamic, dynamic> json) {
    return HfpAudioDevice(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}'.trim(),
      isConnected: json['isConnected'] == true,
    );
  }

  final String id;
  final String name;
  final bool isConnected;

  String get displayName => name.trim();
}

/// Selects only an HFP input that can be tied to the connected HOMI control
/// device. iOS may expose unrelated headsets (for example AirPods) at the same
/// time, so automatic startup must never pick an arbitrary Bluetooth mic.
HfpAudioDevice? selectLikelyHomiHfpDevice(
  Iterable<HfpAudioDevice> devices, {
  String? bleDeviceName,
  String? bleDeviceId,
  String? preferredDeviceId,
  bool connectedOnly = false,
}) {
  final normalizedBleName = _normalizeHomiDeviceName(bleDeviceName ?? '');
  final candidates = devices
      .where((device) {
        if (connectedOnly && !device.isConnected) return false;
        return sameConnectionDeviceId(device.id, bleDeviceId) ||
            sameConnectionDeviceId(device.id, preferredDeviceId) ||
            isRecognizedHomiMicrophoneName(device.name);
      })
      .toList(growable: false);
  if (candidates.isEmpty) return null;
  int rank(HfpAudioDevice device) {
    if (sameConnectionDeviceId(device.id, bleDeviceId)) return 0;
    if (sameConnectionDeviceId(device.id, preferredDeviceId)) return 1;
    final name = _normalizeHomiDeviceName(device.name);
    if (normalizedBleName.isNotEmpty && name == normalizedBleName) return 2;
    if (name == 'hmd001') return 3;
    return 4;
  }

  candidates.sort((first, second) => rank(first).compareTo(rank(second)));
  final best = candidates.first;
  // Two identical advertised names do not identify one physical device. Let
  // the parent select one rather than depending on discovery/sort order.
  if (candidates
      .skip(1)
      .any(
        (device) =>
            rank(device) == rank(best) &&
            !sameConnectionDeviceId(device.id, best.id),
      )) {
    return null;
  }
  return best;
}

bool isRecognizedHomiMicrophoneName(String value) {
  final name = _normalizeHomiDeviceName(value);
  return name == 'hmd001' ||
      name.contains('homi') ||
      name.contains('innotrik') ||
      name.contains('ailingo') ||
      name.contains('yinluo') ||
      value.contains('音洛');
}

String _normalizeHomiDeviceName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '');

abstract interface class HfpAudioControl {
  bool get usesBrowserAudioInput;
  BluetoothAudioStatus get status;
  Stream<BluetoothAudioStatus> get statusChanges;

  Future<void> initialize();
  Future<List<HfpAudioDevice>> findDevices();
  Future<void> connect(HfpAudioDevice device);
  Future<void> disconnect();
  Future<void> startAudioRoute();
  Future<void> stopAudioRoute();
  Future<void> dispose();
}

/// Optional cancellation capability. Cancels only an unfinished selection;
/// a microphone that was already selected remains available.
abstract interface class HfpConnectionAttemptControl {
  Future<void> cancelConnectionAttempt();
}

/// Controls the native Bluetooth HFP microphone route.
///
/// Android exposes paired HFP devices and routes SCO. iOS exposes the HFP
/// inputs already connected in Settings and lets the bridge select a preferred
/// input through AVAudioSession. Neither platform pairs a headset in-app.
class MethodChannelHfpAudioControl
    implements HfpAudioControl, HfpConnectionAttemptControl {
  MethodChannelHfpAudioControl({
    required this.enabled,
    MethodChannel methodChannel = const MethodChannel('ailingo_hfp_audio'),
    EventChannel eventChannel = const EventChannel('ailingo_hfp_audio/events'),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final bool enabled;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<BluetoothAudioStatus> _statusController =
      StreamController<BluetoothAudioStatus>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  Future<void>? _initialization;
  BluetoothAudioStatus _status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.idle,
    sampleRate: 16000,
  );
  bool _disposed = false;
  int _routeRequestGeneration = 0;
  int _connectionRequestGeneration = 0;
  int? _pendingNativeConnection;
  int? _pendingNativeDiscovery;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _statusController.stream;

  @override
  Future<void> initialize() {
    if (!enabled) {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.disabled,
          message: 'HFP đang tắt trong cấu hình bản build.',
          sampleRate: 16000,
        ),
      );
      return Future<void>.value();
    }
    return _initialization ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error) => _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      ),
    );
    try {
      final snapshot = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'initialize',
      );
      if (snapshot != null) {
        _setStatus(_statusFromMap(snapshot));
      }
    } on MissingPluginException {
      _setStatus(
        const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.unsupported,
          message: 'Bản native này chưa có cầu nối HFP.',
          sampleRate: 16000,
        ),
      );
    } on PlatformException catch (error) {
      _setStatus(
        BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.error,
          message: _friendlyError(error),
          sampleRate: 16000,
        ),
      );
    }
  }

  /// Reads authorization only; never starts a permission request or scan.
  Future<bool> hasPermissions() async {
    if (!enabled) return true;
    return await _methodChannel.invokeMethod<bool>('hasPermissions') ?? false;
  }

  /// Requests the platform Bluetooth permission during app setup when needed.
  Future<bool> requestPermissions() async {
    if (!enabled) return true;
    await initialize();
    return await _methodChannel.invokeMethod<bool>('requestPermissions') ??
        false;
  }

  @override
  Future<List<HfpAudioDevice>> findDevices() async {
    final generation = ++_connectionRequestGeneration;
    await initialize();
    _ensureConnectionCurrent(generation);
    _requireSupport();
    final permissions = await requestPermissions();
    _ensureConnectionCurrent(generation);
    if (!permissions) {
      throw const HfpAudioException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để tìm thiết bị HFP.',
      );
    }
    _pendingNativeDiscovery = generation;
    try {
      final result = await _methodChannel.invokeListMethod<dynamic>(
        'findDevices',
        DeviceConnectionDiagnostics.channelFields.isEmpty
            ? null
            : DeviceConnectionDiagnostics.channelFields,
      );
      _ensureConnectionCurrent(generation);
      return (result ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map(HfpAudioDevice.fromJson)
          .where((device) => device.id.isNotEmpty)
          .toList(growable: false);
    } finally {
      if (_pendingNativeDiscovery == generation) _pendingNativeDiscovery = null;
    }
  }

  @override
  Future<void> connect(HfpAudioDevice device) async {
    final generation = ++_connectionRequestGeneration;
    await initialize();
    _ensureConnectionCurrent(generation);
    _requireSupport();
    final permissions = await requestPermissions();
    _ensureConnectionCurrent(generation);
    if (!permissions) {
      throw const HfpAudioException(
        'Cần cho phép Thiết bị ở gần/Bluetooth để dùng HFP.',
      );
    }
    _pendingNativeConnection = generation;
    try {
      final snapshot = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'connect',
        <String, dynamic>{'deviceId': device.id, 'deviceName': device.name},
      );
      _ensureConnectionCurrent(generation);
      if (snapshot != null) _setStatus(_statusFromMap(snapshot));
    } finally {
      if (_pendingNativeConnection == generation) {
        _pendingNativeConnection = null;
      }
    }
  }

  void _ensureConnectionCurrent(int generation) {
    if (_disposed || generation != _connectionRequestGeneration) {
      throw const HfpAudioException('Device connection was cancelled.');
    }
  }

  @override
  Future<void> cancelConnectionAttempt() async {
    final generation = ++_connectionRequestGeneration;
    final wasPending =
        _pendingNativeConnection != null || _pendingNativeDiscovery != null;
    _pendingNativeConnection = null;
    _pendingNativeDiscovery = null;
    if (!enabled || !wasPending) return;
    try {
      final snapshot = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'cancelConnectionAttempt',
      );
      if (!_disposed &&
          generation == _connectionRequestGeneration &&
          snapshot != null) {
        _setStatus(_statusFromMap(snapshot));
      }
    } on MissingPluginException {
      // Older native bridges still need to release an unfinished selection.
      // Dart generation guards prevent a late completion becoming selected.
      await _methodChannel.invokeMethod<void>('disconnect');
    }
  }

  @override
  Future<void> disconnect() async {
    _connectionRequestGeneration += 1;
    _pendingNativeConnection = null;
    _pendingNativeDiscovery = null;
    if (!enabled) {
      return;
    }
    _routeRequestGeneration += 1;
    try {
      await _methodChannel.invokeMethod<void>('disconnect');
    } on MissingPluginException {
      // The bridge is optional outside Android/iOS native.
    }
  }

  @override
  Future<void> startAudioRoute() async {
    final requestGeneration = ++_routeRequestGeneration;
    await initialize();
    if (_disposed || requestGeneration != _routeRequestGeneration) return;
    _requireSupport();
    const retryDelays = <Duration>[
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
    ];
    for (var attempt = 0; ; attempt += 1) {
      if (_disposed || requestGeneration != _routeRequestGeneration) return;
      try {
        final snapshot = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
          'startAudioRoute',
        );
        if (_disposed || requestGeneration != _routeRequestGeneration) return;
        if (snapshot != null) {
          final nextStatus = _statusFromMap(snapshot);
          _setStatus(nextStatus);
          if (snapshot.containsKey('routeActive') &&
              (!nextStatus.routeActive ||
                  nextStatus.inputDeviceName == null ||
                  nextStatus.outputDeviceName == null)) {
            throw const HfpAudioException(
              'Android/iOS chưa xác nhận đủ mic và loa HM-D001 trên đường HFP/SCO.',
            );
          }
        }
        return;
      } on PlatformException catch (error) {
        if (_disposed || requestGeneration != _routeRequestGeneration) return;
        final canRetry =
            (error.code == 'HFP_ROUTE_UNAVAILABLE' ||
                error.code == 'HFP_ROUTE_FAILED' ||
                error.code == 'HFP_ROUTE_TIMEOUT' ||
                (defaultTargetPlatform == TargetPlatform.android &&
                    error.code == 'HFP_ROUTE_CANCELLED')) &&
            attempt < retryDelays.length;
        if (!canRetry) {
          throw HfpAudioException(_friendlyError(error));
        }
        await Future<void>.delayed(retryDelays[attempt]);
        if (_disposed || requestGeneration != _routeRequestGeneration) return;
      }
    }
  }

  @override
  Future<void> stopAudioRoute() async {
    _routeRequestGeneration += 1;
    if (!enabled) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stopAudioRoute');
    } on MissingPluginException {
      // The bridge is optional outside Android/iOS native.
    }
  }

  void _requireSupport() {
    if (!_status.isBridgeSupported) {
      throw HfpAudioException(
        _status.message ?? 'Điện thoại này không hỗ trợ âm thanh HFP.',
      );
    }
  }

  void _handleNativeEvent(dynamic event) {
    if (event is Map<dynamic, dynamic>) {
      _setStatus(_statusFromMap(event));
    }
  }

  BluetoothAudioStatus _statusFromMap(Map<dynamic, dynamic> map) {
    final phaseName = '${map['phase'] ?? 'idle'}';
    final hasSelectedInput = map['hasSelectedInput'];
    final clearsSelectedInput = hasSelectedInput == false;
    final suppliedDeviceId = _nullableString(map['deviceId']);
    final sameDevice =
        suppliedDeviceId == null ||
        sameConnectionDeviceId(suppliedDeviceId, _status.deviceId);
    final deviceName = map.containsKey('deviceName')
        ? _nullableString(map['deviceName'])
        : sameDevice
        ? _status.deviceName
        : null;
    final phase = BluetoothAudioConnectionPhase.values.firstWhere(
      (item) => item.name == phaseName,
      orElse: () => BluetoothAudioConnectionPhase.error,
    );
    return BluetoothAudioStatus(
      phase: phase,
      deviceId: clearsSelectedInput
          ? null
          : suppliedDeviceId ?? _status.deviceId,
      deviceName: clearsSelectedInput ? null : deviceName,
      message: _nullableString(map['message']),
      sampleRate: 16000,
      routeActive: map['routeActive'] == true,
      inputDeviceName: _nullableString(map['inputDeviceName']),
      outputDeviceName: _nullableString(map['outputDeviceName']),
      outputPortType: _nullableString(map['outputPortType']),
      routeSequence: (map['routeSequence'] as num?)?.toInt(),
      audioRoute: _nullableString(map['audioRoute']),
    );
  }

  String? _nullableString(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  void _setStatus(BluetoothAudioStatus next) {
    if (_disposed) {
      return;
    }
    final previousRouteSequence = _status.routeSequence;
    final nextRouteSequence = next.routeSequence;
    if (previousRouteSequence != null &&
        nextRouteSequence != null &&
        nextRouteSequence < previousRouteSequence) {
      return;
    }
    _status = next;
    _statusController.add(next);
  }

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : error.code;
    }
    return '$error';
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await stopAudioRoute();
    _disposed = true;
    await _eventSubscription?.cancel();
    await _statusController.close();
  }
}

class HfpAudioException implements Exception {
  const HfpAudioException(this.message);

  final String message;

  @override
  String toString() => message;
}
