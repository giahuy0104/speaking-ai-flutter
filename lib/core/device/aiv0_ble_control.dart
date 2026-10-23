import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_connection_diagnostics.dart';

const aiv0ControlServiceUuid = '9E3B0001-4A7C-4D6F-8B21-5C17A2D94010';
const aiv0ButtonEventUuid = '9E3B0002-4A7C-4D6F-8B21-5C17A2D94010';
const aiv0AppStateUuid = '9E3B0003-4A7C-4D6F-8B21-5C17A2D94010';

/// Optional onboarding hook. Bonding does not imply that an audio profile is
/// connected. Returns only identities verified by a fresh profile inventory.
/// Legacy callers keep their existing behavior when this hook is absent.
typedef Aiv0PairingVerifier =
    Future<List<String>> Function(
      String deviceId,
      bool bonded, {
      required bool waitForProfile,
    });

enum Aiv0BlePhase {
  disabled,
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Additional buttons are domain values for simulation, NOT firmware IDs.
/// The production parser still recognizes only observed MAIN packets.
enum Aiv0Button { main, unknown, volumeUp, volumeDown, power }

enum Aiv0ButtonGesture { shortPress, longPress, release, unknown }

enum Aiv0AppState { idle, recording, processing, ready, playing, error, paused }

enum Aiv0AppResult {
  accepted,
  busy,
  noResult,
  micUnavailable,
  bluetoothRouteUnavailable,
  duplicate,
  internalError,
}

class Aiv0BleDevice {
  const Aiv0BleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isLikelyAiv0 = false,
    this.advertisesControlService = false,
  });

  factory Aiv0BleDevice.fromMap(Map<Object?, Object?> map) {
    return Aiv0BleDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString().trim() ?? '',
      rssi: (map['rssi'] as num?)?.toInt() ?? 0,
      isLikelyAiv0: map['isLikelyAiv0'] == true,
      advertisesControlService: map['advertisesControlService'] == true,
    );
  }

  final String id;
  final String name;
  final int rssi;
  final bool isLikelyAiv0;
  final bool advertisesControlService;
}

@visibleForTesting
Aiv0BleDevice? selectAiv0AutoConnectCandidate(
  List<Aiv0BleDevice> devices, {
  String? savedDeviceId,
  String? savedDeviceName,
  Iterable<String> connectedHfpDeviceIds = const <String>[],
}) {
  if (devices.isEmpty) return null;
  final connectedIds = connectedHfpDeviceIds
      .map((id) => id.trim().toUpperCase())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (connectedIds.isNotEmpty) {
    final sameDevice =
        devices
            .where(
              (device) => connectedIds.contains(device.id.trim().toUpperCase()),
            )
            .toList(growable: false)
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
    if (sameDevice.isNotEmpty) return sameDevice.first;
    // A different LE address cannot be matched to one of several nearby units.
    final plausible = devices
        .where(
          (device) =>
              device.name.trim().toLowerCase() == 'hm-d001' ||
              device.advertisesControlService,
        )
        .toList(growable: false);
    return plausible.length == 1 ? plausible.single : null;
  }
  final hmD001Devices =
      devices
          .where((device) => device.name.trim().toLowerCase() == 'hm-d001')
          .toList(growable: false)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
  if ((savedDeviceName?.toLowerCase().contains('h20') ?? false) &&
      hmD001Devices.isNotEmpty) {
    return hmD001Devices.first;
  }
  final normalizedSavedId = savedDeviceId?.trim().toUpperCase();
  if (normalizedSavedId != null && normalizedSavedId.isNotEmpty) {
    for (final device in devices) {
      if (device.id.trim().toUpperCase() == normalizedSavedId) {
        return device;
      }
    }
  }
  if (hmD001Devices.isNotEmpty) return hmD001Devices.first;

  final serviceMatches =
      devices
          .where((device) => device.advertisesControlService)
          .toList(growable: false)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
  if (serviceMatches.isNotEmpty) return serviceMatches.first;

  final likelyMatches =
      devices.where((device) => device.isLikelyAiv0).toList(growable: false)
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
  return likelyMatches.isEmpty ? null : likelyMatches.first;
}

class Aiv0ButtonEvent {
  const Aiv0ButtonEvent({
    required this.rawBytes,
    required this.receivedAt,
    this.deviceId,
    this.transportSource,
    this.button = Aiv0Button.unknown,
    this.gesture = Aiv0ButtonGesture.unknown,
    this.sequence,
    this.flags,
    this.batteryPercent,
    this.uptimeMilliseconds,
    this.isObservedH20Packet = false,
    this.isObservedHmD001Packet = false,
    this.isDraftPacket = false,
    this.isDuplicate = false,
    this.rawDescription,
  });

  final Uint8List rawBytes;
  final DateTime receivedAt;
  final String? deviceId;
  final String? transportSource;
  final Aiv0Button button;
  final Aiv0ButtonGesture gesture;
  final int? sequence;
  final int? flags;
  final int? batteryPercent;
  final int? uptimeMilliseconds;
  final bool isObservedH20Packet;
  final bool isObservedHmD001Packet;
  final bool isDraftPacket;
  final bool isDuplicate;
  final String? rawDescription;

  /// Whether this notification has enough information to enter the unified
  /// MAIN handler. Observed H20 packets are actionable even while the separate
  /// APP State write packet remains unconfirmed.
  bool get isActionable =>
      isObservedH20Packet || isObservedHmD001Packet || isDraftPacket;

  String get rawHex => rawBytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

/// Temporary codec from the V0.1 draft. Keep [confirmed] false until ODM sends
/// MAIN raw hex and confirms the byte layout implemented by firmware.
class Aiv0DraftProtocolCodec {
  const Aiv0DraftProtocolCodec({required this.confirmed});

  static const buttonPacketLength = 12;
  static const appStatePacketLength = 8;
  static const protocolVersion = 1;

  final bool confirmed;

  Aiv0ButtonEvent decodeButtonEvent(
    Uint8List bytes, {
    String? deviceId,
    DateTime? receivedAt,
  }) {
    // Real H20 firmware 1.0.0 packet observed on 9E3B0002:
    //   01 BB SS 01 FF FF PP 00 UU UU UU UU
    // BB is MAIN (01), SS is a transport sequence, PP is the battery
    // percentage and UU is uptime in milliseconds (LE). The current firmware
    // exposes one MAIN action only; it does not expose long-press or release.
    //
    // Decode this independently from [confirmed]. That flag still protects
    // the unconfirmed 8-byte APP State writer; receiving MAIN must not require
    // sending that draft packet back to the device.
    final isObservedH20Packet =
        bytes.length == buttonPacketLength &&
        bytes[0] == protocolVersion &&
        bytes[1] == 0x01 &&
        bytes[3] == 0x01;
    if (isObservedH20Packet) {
      final data = ByteData.sublistView(bytes);
      return Aiv0ButtonEvent(
        rawBytes: bytes,
        deviceId: deviceId,
        receivedAt: receivedAt ?? DateTime.now(),
        button: Aiv0Button.main,
        gesture: Aiv0ButtonGesture.shortPress,
        sequence: bytes[2],
        flags: data.getUint16(4, Endian.little),
        batteryPercent: data.getUint16(6, Endian.little).clamp(0, 100),
        uptimeMilliseconds: data.getUint32(8, Endian.little),
        isObservedH20Packet: true,
      );
    }

    // HM-D001 uses the same GATT service but the confirmed button/gesture
    // layout below, independently of the unconfirmed APP State writer.
    final isObservedHmD001Packet =
        bytes.length == buttonPacketLength &&
        bytes[0] == protocolVersion &&
        (bytes[1] == 0x01 ||
            (bytes[1] == 0x02 && bytes[2] == 0x01) ||
            bytes[1] == 0x03 ||
            bytes[1] == 0x04) &&
        (bytes[2] == 0x01 || bytes[2] == 0x02) &&
        bytes[3] == 0x00 &&
        bytes[7] == 0x00 &&
        bytes[6] <= 100;
    if (isObservedHmD001Packet) {
      final data = ByteData.sublistView(bytes);
      return Aiv0ButtonEvent(
        rawBytes: bytes,
        deviceId: deviceId,
        receivedAt: receivedAt ?? DateTime.now(),
        button: switch (bytes[1]) {
          0x01 => Aiv0Button.main,
          0x02 => Aiv0Button.power,
          0x03 => Aiv0Button.volumeUp,
          _ => Aiv0Button.volumeDown,
        },
        gesture: bytes[2] == 0x01
            ? Aiv0ButtonGesture.shortPress
            : Aiv0ButtonGesture.longPress,
        sequence: data.getUint16(4, Endian.little),
        batteryPercent: bytes[6],
        uptimeMilliseconds: data.getUint32(8, Endian.little),
        isObservedHmD001Packet: !confirmed,
        isDraftPacket: confirmed,
      );
    }

    if (!confirmed ||
        bytes.length != buttonPacketLength ||
        bytes[0] != protocolVersion) {
      return Aiv0ButtonEvent(
        rawBytes: bytes,
        deviceId: deviceId,
        receivedAt: receivedAt ?? DateTime.now(),
      );
    }

    final data = ByteData.sublistView(bytes);
    return Aiv0ButtonEvent(
      rawBytes: bytes,
      deviceId: deviceId,
      receivedAt: receivedAt ?? DateTime.now(),
      button: switch (bytes[1]) {
        0x01 => Aiv0Button.main,
        _ => Aiv0Button.unknown,
      },
      gesture: switch (bytes[2]) {
        0x01 => Aiv0ButtonGesture.shortPress,
        0x02 => Aiv0ButtonGesture.longPress,
        0x03 => Aiv0ButtonGesture.release,
        _ => Aiv0ButtonGesture.unknown,
      },
      flags: bytes[3],
      sequence: data.getUint16(4, Endian.little),
      batteryPercent: bytes[6].clamp(0, 100),
      uptimeMilliseconds: data.getUint32(8, Endian.little),
      isDraftPacket: true,
    );
  }

  Uint8List encodeAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
    int flags = 0,
  }) {
    if (!confirmed) {
      throw StateError(
        'AIV0 draft protocol is not confirmed by ODM; APP State was not sent.',
      );
    }
    final bytes = Uint8List(appStatePacketLength);
    final data = ByteData.sublistView(bytes);
    bytes[0] = protocolVersion;
    bytes[1] = state.index;
    bytes[2] = result.index;
    bytes[3] = flags & 0xFF;
    data.setUint16(4, sequence & 0xFFFF, Endian.little);
    return bytes;
  }
}

class Aiv0BleDiagnosticEvent {
  Aiv0BleDiagnosticEvent({
    required this.occurredAt,
    required this.stage,
    required this.metadata,
    this.caller,
    this.code,
    this.message,
    this.audioRoute,
    this.turnId,
  });

  factory Aiv0BleDiagnosticEvent.fromMap(Map<Object?, Object?> map) {
    final eventEpochMs = (map['eventEpochMs'] as num?)?.toInt() ?? 0;
    final metadata = <String, Object?>{};
    for (final entry in map.entries) {
      final key = entry.key?.toString();
      if (key == null || _coreKeys.contains(key)) continue;
      metadata[key] = entry.value;
    }
    return Aiv0BleDiagnosticEvent(
      occurredAt: DateTime.fromMillisecondsSinceEpoch(eventEpochMs),
      stage: map['stage']?.toString() ?? '',
      caller: map['caller']?.toString(),
      code: map['code']?.toString(),
      message: map['message']?.toString(),
      audioRoute: map['audioRoute']?.toString(),
      turnId: map['turnId']?.toString(),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  static const _coreKeys = <String>{
    'eventEpochMs',
    'stage',
    'caller',
    'code',
    'message',
    'audioRoute',
    'turnId',
  };

  final DateTime occurredAt;
  final String stage;
  final String? caller;
  final String? code;
  final String? message;
  final String? audioRoute;
  final String? turnId;
  final Map<String, Object?> metadata;
}

class Aiv0BleStatus {
  const Aiv0BleStatus({
    required this.phase,
    required this.protocolConfirmed,
    this.deviceId,
    this.deviceName,
    this.message,
    this.writeMode,
    this.batteryPercent,
    this.firmwareRevision,
    this.lastRawHex,
    this.lastButton,
    this.lastGesture,
    this.packetCount = 0,
    this.invalidPacketCount = 0,
    this.duplicatePacketCount = 0,
    this.remoteMainCount = 0,
    this.remoteMainDuplicateCount = 0,
    this.remoteMainCommandsEnabled = false,
    this.lastMainTransportSource,
    this.reconnectCount = 0,
    this.peripheralState,
    this.mainNotificationState,
    this.lastDisconnectCode,
    this.lastDisconnectMessage,
    this.lastDisconnectAt,
    this.lastNotificationRecovery,
    this.deferredRecoveryRepeatCount = 0,
    this.diagnosticTimeline = const <Aiv0BleDiagnosticEvent>[],
  });

  const Aiv0BleStatus.disabled()
    : this(
        phase: Aiv0BlePhase.disabled,
        protocolConfirmed: false,
        message: 'BLE Control AIV0 chỉ hỗ trợ trên Android/iOS native.',
      );

  factory Aiv0BleStatus.fromMap(
    Map<Object?, Object?> map, {
    required bool protocolConfirmed,
  }) {
    final rawPhase = map['phase']?.toString();
    final reportedPhase = Aiv0BlePhase.values.firstWhere(
      (value) => value.name == rawPhase,
      orElse: () => Aiv0BlePhase.idle,
    );
    final peripheralState = _normalizePeripheralState(
      map['peripheralState']?.toString(),
    );
    final phase =
        reportedPhase == Aiv0BlePhase.connected &&
            peripheralState != null &&
            peripheralState != 'connected'
        ? Aiv0BlePhase.reconnecting
        : reportedPhase;
    final lastDisconnectEpochMs = (map['lastDisconnectEpochMs'] as num?)
        ?.toInt();
    final diagnosticTimeline =
        (map['diagnosticTimeline'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .map(Aiv0BleDiagnosticEvent.fromMap)
            .where(
              (event) =>
                  event.stage.isNotEmpty &&
                  event.occurredAt.millisecondsSinceEpoch > 0,
            )
            .toList(growable: false)
          ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
    return Aiv0BleStatus(
      phase: phase,
      protocolConfirmed: protocolConfirmed,
      deviceId: map['deviceId']?.toString(),
      deviceName: map['deviceName']?.toString(),
      message: map['message']?.toString(),
      writeMode: map['writeMode']?.toString(),
      batteryPercent: (map['batteryPercent'] as num?)?.toInt(),
      firmwareRevision: map['firmwareRevision']?.toString(),
      lastRawHex: map['lastRawHex']?.toString(),
      lastButton: map['lastButton']?.toString(),
      lastGesture: map['lastGesture']?.toString(),
      packetCount: (map['packetCount'] as num?)?.toInt() ?? 0,
      invalidPacketCount: (map['invalidPacketCount'] as num?)?.toInt() ?? 0,
      duplicatePacketCount: (map['duplicatePacketCount'] as num?)?.toInt() ?? 0,
      remoteMainCount: (map['remoteMainCount'] as num?)?.toInt() ?? 0,
      remoteMainDuplicateCount:
          (map['remoteMainDuplicateCount'] as num?)?.toInt() ?? 0,
      remoteMainCommandsEnabled: map['remoteMainCommandsEnabled'] == true,
      lastMainTransportSource: map['lastMainTransportSource']?.toString(),
      reconnectCount: (map['reconnectCount'] as num?)?.toInt() ?? 0,
      peripheralState: peripheralState,
      mainNotificationState: map['mainNotificationState']?.toString(),
      lastDisconnectCode: map['lastDisconnectCode']?.toString(),
      lastDisconnectMessage: map['lastDisconnectMessage']?.toString(),
      lastDisconnectAt:
          lastDisconnectEpochMs == null || lastDisconnectEpochMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastDisconnectEpochMs),
      lastNotificationRecovery: map['lastNotificationRecovery']?.toString(),
      deferredRecoveryRepeatCount:
          (map['deferredRecoveryRepeatCount'] as num?)?.toInt() ?? 0,
      diagnosticTimeline: diagnosticTimeline,
    );
  }

  final Aiv0BlePhase phase;
  final bool protocolConfirmed;
  final String? deviceId;
  final String? deviceName;
  final String? message;
  final String? writeMode;
  final int? batteryPercent;
  final String? firmwareRevision;
  final String? lastRawHex;
  final String? lastButton;
  final String? lastGesture;
  final int packetCount;
  final int invalidPacketCount;
  final int duplicatePacketCount;
  final int remoteMainCount;
  final int remoteMainDuplicateCount;
  final bool remoteMainCommandsEnabled;
  final String? lastMainTransportSource;
  final int reconnectCount;
  final String? peripheralState;
  final String? mainNotificationState;
  final String? lastDisconnectCode;
  final String? lastDisconnectMessage;
  final DateTime? lastDisconnectAt;
  final String? lastNotificationRecovery;
  final int deferredRecoveryRepeatCount;
  final List<Aiv0BleDiagnosticEvent> diagnosticTimeline;

  bool get isConnected => phase == Aiv0BlePhase.connected;

  static String? _normalizePeripheralState(String? value) {
    final state = value?.trim();
    return switch (state) {
      'CBPeripheralState(rawValue: 0)' => 'disconnected',
      'CBPeripheralState(rawValue: 1)' => 'connecting',
      'CBPeripheralState(rawValue: 2)' => 'connected',
      'CBPeripheralState(rawValue: 3)' => 'disconnecting',
      _ => state,
    };
  }
}

abstract interface class Aiv0BleControl {
  Aiv0BleStatus get status;
  Stream<Aiv0BleStatus> get statusStream;
  Stream<Aiv0ButtonEvent> get buttonEvents;

  Future<void> initialize();
  Future<List<Aiv0BleDevice>> scan({Duration timeout});
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> markParentDiagnosticsOpened();
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence,
  });
  Future<void> dispose();
}

enum Aiv0BluetoothAdapterState {
  poweredOn,
  poweredOff,
  unauthorized,
  unsupported,
  resetting,
  unknown;

  factory Aiv0BluetoothAdapterState.fromNative(Object? value) {
    return switch (value?.toString()) {
      'poweredOn' => Aiv0BluetoothAdapterState.poweredOn,
      'poweredOff' => Aiv0BluetoothAdapterState.poweredOff,
      'unauthorized' => Aiv0BluetoothAdapterState.unauthorized,
      'unsupported' => Aiv0BluetoothAdapterState.unsupported,
      'resetting' => Aiv0BluetoothAdapterState.resetting,
      _ => Aiv0BluetoothAdapterState.unknown,
    };
  }
}

class MethodChannelAiv0BleControl implements Aiv0BleControl {
  MethodChannelAiv0BleControl({
    required bool enabled,
    required bool draftProtocolConfirmed,
    bool dualModePairingEnabled = const bool.fromEnvironment(
      'HM_D001_SINGLE_PAIRING',
      defaultValue: true,
    ),
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Duration batteryRefreshInterval = const Duration(minutes: 1),
  }) : _enabled =
           enabled &&
           !kIsWeb &&
           (defaultTargetPlatform == TargetPlatform.android ||
               defaultTargetPlatform == TargetPlatform.iOS),
       _codec = Aiv0DraftProtocolCodec(confirmed: draftProtocolConfirmed),
       _dualModePairingEnabled = dualModePairingEnabled,
       _methodChannel =
           methodChannel ?? const MethodChannel('ailingo_aiv0_ble_control'),
       _eventChannel =
           eventChannel ??
           const EventChannel('ailingo_aiv0_ble_control/events'),
       _batteryRefreshInterval = batteryRefreshInterval,
       _status =
           enabled &&
               !kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS)
           ? Aiv0BleStatus(
               phase: Aiv0BlePhase.idle,
               protocolConfirmed: draftProtocolConfirmed,
             )
           : const Aiv0BleStatus.disabled();

  final bool _enabled;
  final bool _dualModePairingEnabled;
  final Aiv0DraftProtocolCodec _codec;
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Duration _batteryRefreshInterval;
  final _statusController = StreamController<Aiv0BleStatus>.broadcast();
  final _buttonController = StreamController<Aiv0ButtonEvent>.broadcast();
  static const _lastDeviceIdPreference = 'aiv0_ble_last_device_id';
  static const _lastDeviceNamePreference = 'aiv0_ble_last_device_name';
  StreamSubscription<Object?>? _eventSubscription;
  Aiv0BleStatus _status;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _diagnosticWriteQueue = Future<void>.value();
  Future<bool>? _autoConnectFuture;
  Timer? _batteryRefreshTimer;
  bool _batteryRefreshInFlight = false;
  bool _manualDisconnectRequested = false;
  int _connectionGeneration = 0;
  final Set<void Function()> _connectionCancellations = {};

  @override
  Aiv0BleStatus get status => _status;

  @override
  Stream<Aiv0BleStatus> get statusStream => _statusController.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttonController.stream;

  @override
  Future<void> initialize() async {
    if (!_enabled || _eventSubscription != null) return;
    final generation = _connectionGeneration;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) => _setStatus(
        Aiv0BleStatus(
          phase: Aiv0BlePhase.error,
          protocolConfirmed: _codec.confirmed,
          message: error.toString(),
        ),
      ),
    );
    final map = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'initialize',
      <String, Object?>{'enableTransportBridging': _dualModePairingEnabled},
    );
    if (map != null && generation == _connectionGeneration) _updateStatus(map);
  }

  /// Observation only: native adapters must not claim audio focus or infer
  /// accessory buttons from phone volume/power keys.
  Future<void> setControlContext({
    required bool learningActive,
    required bool diagnosticsActive,
  }) async {
    if (!_enabled) return;
    try {
      await _methodChannel.invokeMethod<void>('setControlContext', {
        'learningActive': learningActive,
        'diagnosticsActive': diagnosticsActive,
      });
    } on MissingPluginException {
      // Older native builds have no media-key observation support.
    }
  }

  /// Reads authorization only; never starts a permission request or scan.
  Future<bool> hasPermissions() async {
    if (!_enabled) return true;
    return await _methodChannel.invokeMethod<bool>('hasPermissions') ?? false;
  }

  /// Requests the platform Bluetooth permission used by AIV0 before the child
  /// operates the physical MAIN button.
  Future<bool> requestPermissions() async {
    if (!_enabled) return true;
    final generation = _connectionGeneration;
    await _connectionStep(generation, initialize);
    return await _connectionStep<bool?>(
          generation,
          () => _methodChannel.invokeMethod<bool>('requestPermissions'),
        ) ??
        false;
  }

  /// Returns the radio state separately from the Bluetooth permission state.
  /// A granted permission does not mean the user has turned Bluetooth on.
  Future<Aiv0BluetoothAdapterState> readBluetoothAdapterState() async {
    if (!_enabled) return Aiv0BluetoothAdapterState.unsupported;
    try {
      await initialize();
      final value = await _methodChannel.invokeMethod<Object?>(
        'bluetoothAdapterState',
      );
      return Aiv0BluetoothAdapterState.fromNative(value);
    } on MissingPluginException {
      return Aiv0BluetoothAdapterState.unknown;
    } on PlatformException {
      return Aiv0BluetoothAdapterState.unknown;
    }
  }

  /// Offers Android system pairing for the currently verified MAIN device.
  /// Call only from an explicit user action. This retains the healthy BLE
  /// connection and does not scan, reconnect, or claim that HFP is connected.
  Future<bool> requestSystemPairingForConnectedDevice() async {
    if (!_enabled ||
        !_dualModePairingEnabled ||
        defaultTargetPlatform != TargetPlatform.android ||
        _manualDisconnectRequested) {
      return false;
    }
    final generation = _connectionGeneration;
    try {
      await _connectionStep(generation, initialize);
      final deviceId = _status.deviceId?.trim();
      if (!_status.isConnected || deviceId == null || deviceId.isEmpty) {
        return false;
      }
      final paired = await _requestSystemPairing(
        deviceId,
        generation,
        requireConnected: true,
      );
      _ensureConnectionCurrent(generation);
      return paired && _isConnectedDevice(deviceId);
    } catch (error) {
      debugPrint('H20 system pairing did not complete: $error');
      return false;
    }
  }

  bool _isConnectedDevice(String deviceId) =>
      _status.isConnected && _status.deviceId?.trim() == deviceId;

  Future<bool> _requestSystemPairing(
    String deviceId,
    int generation, {
    bool requireConnected = false,
  }) async {
    if (!await _connectionStep(generation, requestPermissions)) return false;
    if (requireConnected && !_isConnectedDevice(deviceId)) return false;
    return await _connectionStep<bool?>(
          generation,
          () => _methodChannel.invokeMethod<bool>(
            'requestDualModeBond',
            <String, Object?>{
              'deviceId': deviceId,
              ...DeviceConnectionDiagnostics.channelFields,
            },
          ),
        ) ==
        true;
  }

  /// Android displays the system-owned enable-Bluetooth confirmation. iOS
  /// cannot turn the radio on programmatically and therefore returns false.
  Future<bool> requestEnableBluetooth() async {
    if (!_enabled) return false;
    try {
      return await _methodChannel.invokeMethod<bool>(
            'requestEnableBluetooth',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the supported system settings destination for the current OS.
  /// Android opens Bluetooth settings; iOS opens HOMI's Settings page.
  Future<bool> openBluetoothSettings() async {
    if (!_enabled) return false;
    try {
      return await _methodChannel.invokeMethod<bool>('openBluetoothSettings') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Distinguishes a blocked system prompt from an ordinary permission denial.
  Future<bool> bluetoothPermissionRequiresSettings() async {
    if (!_enabled || kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await readBluetoothAdapterState() ==
          Aiv0BluetoothAdapterState.unauthorized;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'bluetoothPermissionRequiresSettings',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens this app's permission page, independently of the radio settings.
  Future<bool> openPermissionSettings() async {
    if (!_enabled) return false;
    try {
      return await _methodChannel.invokeMethod<bool>(
            'openPermissionSettings',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<Aiv0BleDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) => _scan(
    timeout,
    _connectionGeneration,
    foreground: defaultTargetPlatform == TargetPlatform.android,
  );

  Future<List<Aiv0BleDevice>> _scan(
    Duration timeout,
    int generation, {
    bool foreground = false,
  }) async {
    if (!_enabled) return const [];
    await _connectionStep(generation, initialize);
    final permissionGranted = await _connectionStep(
      generation,
      requestPermissions,
    );
    if (!permissionGranted) {
      throw PlatformException(
        code: 'PERMISSION_REQUIRED',
        message: 'Cần cấp quyền Thiết bị ở gần/Bluetooth để tìm HM-D001.',
      );
    }
    final devices = await _connectionStep(
      generation,
      () => _methodChannel.invokeListMethod<Object?>('scan', <String, Object?>{
        'timeoutMs': timeout.inMilliseconds,
        ...DeviceConnectionDiagnostics.channelFields,
        if (foreground) 'foreground': true,
      }),
    );
    return (devices ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(Aiv0BleDevice.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> connect(String deviceId) async {
    if (!_enabled) return;
    _manualDisconnectRequested = false;
    await _connect(deviceId, _connectionGeneration);
  }

  Future<void> _connect(String deviceId, int generation) async {
    await _connectionStep(generation, initialize);
    final permissionGranted = await _connectionStep(
      generation,
      requestPermissions,
    );
    if (!permissionGranted) {
      throw PlatformException(
        code: 'PERMISSION_REQUIRED',
        message: 'Cần cấp quyền Bluetooth để kết nối HM-D001.',
      );
    }
    final connectedStatus = await _connectionStep(
      generation,
      () => _methodChannel.invokeMapMethod<Object?, Object?>(
        'connect',
        <String, Object?>{
          'deviceId': deviceId,
          ...DeviceConnectionDiagnostics.channelFields,
        },
      ),
    );
    // Android returns the verified GATT/MAIN Notify snapshot with the connect
    // result. iOS returns null, so read its current snapshot explicitly.
    final statusSnapshot =
        connectedStatus ??
        await _connectionStep(
          generation,
          () => _methodChannel.invokeMapMethod<Object?, Object?>('status'),
        );
    if (statusSnapshot != null) _updateStatus(statusSnapshot);
    final preferences = await _connectionStep(
      generation,
      SharedPreferences.getInstance,
    );
    await _connectionStep(
      generation,
      () => preferences.setString(_lastDeviceIdPreference, deviceId),
    );
    final connectedName = _status.deviceName?.trim() ?? '';
    // An unnamed new device must not inherit the previous device's name.
    await _connectionStep(
      generation,
      () => preferences.setString(_lastDeviceNamePreference, connectedName),
    );
  }

  /// Reconnects BLE Control without requiring a second user action after H20
  /// has already been paired through the system Bluetooth/HFP settings.
  ///
  /// The previously verified BLE address is preferred. On first use (or when
  /// the saved native identifier changes), advertised 9E3B0001 service is the
  /// strongest signal; the H20/AIV0 device name is only a safe fallback.
  Future<bool> autoConnectKnownOrNearby({
    Duration scanTimeout = const Duration(seconds: 4),
    bool requestBond = false,
    Iterable<String> connectedHfpDeviceIds = const <String>[],
    bool forceScan = false,
    bool userInitiated = false,
    Aiv0PairingVerifier? verifyPairing,
    String? onlyDeviceId,
  }) {
    if (!_enabled || _manualDisconnectRequested) {
      return Future<bool>.value(false);
    }
    final pending = _autoConnectFuture;
    if (pending != null) return pending;
    final future =
        _runAutoConnect(
          scanTimeout,
          generation: _connectionGeneration,
          requestBond: requestBond && _dualModePairingEnabled,
          verifyPairing: verifyPairing,
          connectedHfpDeviceIds: connectedHfpDeviceIds.toList(growable: false),
          forceScan: forceScan,
          foreground:
              defaultTargetPlatform == TargetPlatform.android &&
              (userInitiated || requestBond || forceScan),
          onlyDeviceId: onlyDeviceId,
        ).catchError((Object error) {
          if (error is PlatformException &&
              (error.code == 'CONNECT_CANCELLED' ||
                  error.code == 'BLUETOOTH_DISABLED')) {
            return false;
          }
          throw error;
        });
    _autoConnectFuture = future;
    return future.whenComplete(() {
      if (identical(_autoConnectFuture, future)) {
        _autoConnectFuture = null;
      }
    });
  }

  Future<bool> _runAutoConnect(
    Duration scanTimeout, {
    required int generation,
    required bool requestBond,
    required List<String> connectedHfpDeviceIds,
    required bool forceScan,
    required bool foreground,
    Aiv0PairingVerifier? verifyPairing,
    String? onlyDeviceId,
  }) async {
    await _connectionStep(generation, initialize);
    if (_status.isConnected) return true;
    if (_status.phase == Aiv0BlePhase.scanning ||
        _status.phase == Aiv0BlePhase.connecting ||
        (_status.phase == Aiv0BlePhase.reconnecting &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return false;
    }

    // Audio can keep using HFP while MAIN recovers. In that case restore only
    // its verified control identity: never pair or select another nearby unit.
    if (onlyDeviceId != null) {
      if (onlyDeviceId.trim().isEmpty) return false;
      try {
        await _connectCandidate(
          onlyDeviceId.trim(),
          requestBond: false,
          generation: generation,
        );
        return true;
      } catch (error) {
        _ensureConnectionCurrent(generation);
        if (error is PlatformException && error.code == 'BLUETOOTH_DISABLED') {
          rethrow;
        }
        debugPrint('Known HOMI control link recovery failed: $error');
        return false;
      }
    }

    final preferences = await _connectionStep(
      generation,
      SharedPreferences.getInstance,
    );
    final savedDeviceId = preferences.getString(_lastDeviceIdPreference);
    final savedDeviceName = preferences.getString(_lastDeviceNamePreference);
    final migratingFromH20 =
        savedDeviceName?.toLowerCase().contains('h20') ?? false;
    if (!forceScan &&
        savedDeviceId != null &&
        savedDeviceId.trim().isNotEmpty &&
        !migratingFromH20 &&
        (connectedHfpDeviceIds.isEmpty ||
            connectedHfpDeviceIds.any(
              (id) => id.toUpperCase() == savedDeviceId.trim().toUpperCase(),
            ))) {
      try {
        // This is the fast path for normal daily use: native can reopen the
        // verified GATT identifier directly without waiting for another scan.
        await _connectCandidate(
          savedDeviceId.trim(),
          requestBond: requestBond,
          verifyPairing: verifyPairing,
          generation: generation,
        );
        return true;
      } catch (error) {
        if (error is PlatformException && error.code == 'BLUETOOTH_DISABLED') {
          rethrow;
        }
        debugPrint(
          'Saved H20 BLE address was unavailable; scanning nearby: $error',
        );
      }
    }

    List<Aiv0BleDevice> devices = const [];
    try {
      devices = await _scan(
        foreground && scanTimeout < const Duration(seconds: 8)
            ? const Duration(seconds: 8)
            : scanTimeout,
        generation,
        foreground: foreground,
      );
    } catch (error) {
      // Radio state can change after the caller's readiness check. End this
      // round quietly; do not try another address while Bluetooth is off.
      if (error is PlatformException && error.code == 'BLUETOOTH_DISABLED') {
        rethrow;
      }
      debugPrint('Automatic H20 BLE scan was skipped: $error');
    }
    _ensureConnectionCurrent(generation);

    var candidate = selectAiv0AutoConnectCandidate(
      devices,
      savedDeviceId: savedDeviceId,
      savedDeviceName: savedDeviceName,
      connectedHfpDeviceIds: connectedHfpDeviceIds,
    );
    var pairingAlreadyRequested = false;
    if (candidate == null &&
        requestBond &&
        defaultTargetPlatform == TargetPlatform.android &&
        connectedHfpDeviceIds.isEmpty) {
      // First-use HM-D001 can be discoverable over Classic without a usable
      // BLE name/service. Only a user-requested pairing may run this heavier
      // search. Background retry cadence and known-device recovery stay BLE-only.
      try {
        final classicDevices = await _connectionStep(
          generation,
          () => _methodChannel.invokeListMethod<Object?>(
            'scanClassic',
            <String, Object?>{'timeoutMs': 15000},
          ),
        );
        final audioCandidate = selectAiv0AutoConnectCandidate(
          classicDevices
                  ?.whereType<Map<Object?, Object?>>()
                  .map(Aiv0BleDevice.fromMap)
                  .toList() ??
              const [],
        );
        if (audioCandidate != null) {
          pairingAlreadyRequested = true;
          final bonded = await _requestSystemPairing(
            audioCandidate.id,
            generation,
          );
          if (verifyPairing != null) {
            connectedHfpDeviceIds = await _connectionStep(
              generation,
              () => verifyPairing(
                audioCandidate.id,
                bonded,
                waitForProfile: true,
              ),
            );
          }
          // Classic pairing identifies the audio radio, not the BLE control
          // address. Rescan after bonding; never open GATT on an address that
          // has only been observed through Classic discovery.
          devices = await _scan(
            const Duration(seconds: 8),
            generation,
            foreground: true,
          );
          // Profile state can change while Android is scanning. Refresh it
          // before matching an anonymous BLE advert to the audio identity.
          if (verifyPairing != null) {
            connectedHfpDeviceIds = await _connectionStep(
              generation,
              () => verifyPairing(
                audioCandidate.id,
                bonded,
                waitForProfile: false,
              ),
            );
          }
          candidate = selectAiv0AutoConnectCandidate(
            devices,
            savedDeviceId: savedDeviceId,
            savedDeviceName: savedDeviceName,
            connectedHfpDeviceIds: verifyPairing == null
                ? [audioCandidate.id]
                : connectedHfpDeviceIds,
          );
        }
      } catch (error) {
        _ensureConnectionCurrent(generation);
        if (error is PlatformException && error.code == 'BLUETOOTH_DISABLED') {
          rethrow;
        }
        debugPrint('First-use HOMI Classic discovery did not complete: $error');
      }
    }
    final targetId = candidate?.id;
    if ((const bool.fromEnvironment('HOMI_BLE_DIAGNOSTICS') ||
            DeviceConnectionDiagnostics.channelFields.isNotEmpty) &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _methodChannel.invokeMethod<void>('bleDiagnostic', {
          ...DeviceConnectionDiagnostics.channelFields,
          'savedId': savedDeviceId,
          'savedName': savedDeviceName,
          'connectedHfpIds': connectedHfpDeviceIds,
          'selectedId': targetId,
          'outcome': devices.isEmpty
              ? 'no_scan_results'
              : candidate == null
              ? 'no_unambiguous_candidate'
              : 'candidate_selected',
          'devices': devices
              .map(
                (device) => {
                  'id': device.id,
                  'name': device.name,
                  'rssi': device.rssi,
                  'likely': device.isLikelyAiv0,
                  'controlService': device.advertisesControlService,
                  'matchesHfpAddress': connectedHfpDeviceIds.any(
                    (id) => id.toUpperCase() == device.id.toUpperCase(),
                  ),
                  'exactHmD001Name':
                      device.name.trim().toLowerCase() == 'hm-d001',
                  'selected': device.id == targetId,
                },
              )
              .toList(),
        });
      } catch (_) {
        // Diagnostics must never change the connection outcome.
      }
    }
    if (targetId == null || targetId.isEmpty) {
      if (pairingAlreadyRequested || connectedHfpDeviceIds.isNotEmpty) {
        _updateStatus({
          'phase': 'error',
          'message':
              'Đã tìm thấy phần âm thanh HM-D001 nhưng chưa tìm thấy kết nối MAIN qua BLE.',
        });
      }
      if (!forceScan &&
          migratingFromH20 &&
          savedDeviceId != null &&
          connectedHfpDeviceIds.isEmpty) {
        try {
          await _connectCandidate(
            savedDeviceId.trim(),
            requestBond: requestBond,
            verifyPairing: verifyPairing,
            generation: generation,
          );
          return true;
        } catch (_) {
          return false;
        }
      }
      return false;
    }

    try {
      await _connectCandidate(
        targetId,
        requestBond: requestBond && !pairingAlreadyRequested,
        verifyPairing: verifyPairing,
        generation: generation,
      );
      final candidateName = candidate?.name.trim();
      if (candidateName != null && candidateName.isNotEmpty) {
        await _connectionStep(
          generation,
          () => preferences.setString(_lastDeviceNamePreference, candidateName),
        );
      }
      // Native completes `connect` only after service 9E3B0001 is verified and
      // Indicate 9E3B0002 is enabled. The status EventChannel can arrive one
      // microtask later, so the completed method call itself is authoritative.
      return true;
    } catch (error) {
      debugPrint('Automatic H20 BLE connection failed: $error');
      return false;
    }
  }

  Future<void> _connectCandidate(
    String deviceId, {
    required bool requestBond,
    required int generation,
    Aiv0PairingVerifier? verifyPairing,
  }) async {
    _ensureConnectionCurrent(generation);
    if (requestBond && defaultTargetPlatform == TargetPlatform.android) {
      try {
        // A declined bond may still permit the independent MAIN connection.
        // The caller must verify HFP separately before reporting HOMI ready.
        final bonded = await _requestSystemPairing(deviceId, generation);
        if (verifyPairing != null) {
          await _connectionStep(
            generation,
            () => verifyPairing(deviceId, bonded, waitForProfile: true),
          );
        }
      } catch (error) {
        debugPrint('H20 system pairing was unavailable: $error');
      }
    }
    if (_manualDisconnectRequested) {
      throw StateError('H20 connection was cancelled.');
    }
    _ensureConnectionCurrent(generation);
    await _connect(deviceId, generation);
  }

  /// Cancels this attempt only. A verified BLE link is retained when the app
  /// is still looking for its HFP input; the normal retry scheduler may resume.
  Future<void> cancelConnectionAttempt() async {
    _invalidateConnectionAttempt();
    if (!_enabled) return;
    final generation = _connectionGeneration;
    final map = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'cancelConnectionAttempt',
    );
    if (map != null && generation == _connectionGeneration) _updateStatus(map);
  }

  /// Explicit retry starts a fresh scan, even after a manual disconnect. A
  /// healthy BLE link is reused while the app retries the separate HFP input.
  Future<bool> retryKnownOrNearby({
    Duration scanTimeout = const Duration(seconds: 4),
    bool requestBond = false,
    Iterable<String> connectedHfpDeviceIds = const <String>[],
  }) async {
    final cancellation = cancelConnectionAttempt();
    final generation = _connectionGeneration;
    await cancellation;
    if (generation != _connectionGeneration) return false;
    _manualDisconnectRequested = false;
    return autoConnectKnownOrNearby(
      scanTimeout: scanTimeout,
      requestBond: requestBond,
      connectedHfpDeviceIds: connectedHfpDeviceIds,
      forceScan: true,
    );
  }

  void _invalidateConnectionAttempt() {
    _connectionGeneration += 1;
    for (final cancel in _connectionCancellations.toList()) {
      cancel();
    }
    _connectionCancellations.clear();
    _autoConnectFuture = null;
  }

  void _ensureConnectionCurrent(int generation) {
    if (generation != _connectionGeneration) {
      throw PlatformException(
        code: 'CONNECT_CANCELLED',
        message: 'Đã hủy kết nối HOMI.',
      );
    }
  }

  Future<T> _connectionStep<T>(
    int generation,
    Future<T> Function() action,
  ) async {
    _ensureConnectionCurrent(generation);
    final completion = Completer<T>();
    void cancel() {
      if (!completion.isCompleted) {
        completion.completeError(
          PlatformException(
            code: 'CONNECT_CANCELLED',
            message: 'Đã hủy kết nối HOMI.',
          ),
        );
      }
    }

    _connectionCancellations.add(cancel);
    try {
      action().then(
        (value) {
          if (!completion.isCompleted) completion.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        },
      );
      final result = await completion.future;
      _ensureConnectionCurrent(generation);
      return result;
    } finally {
      _connectionCancellations.remove(cancel);
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_enabled) return;
    _manualDisconnectRequested = true;
    _invalidateConnectionAttempt();
    await _methodChannel.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> markParentDiagnosticsOpened() async {
    if (!_enabled || defaultTargetPlatform != TargetPlatform.iOS) return;
    final map = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'markParentDiagnosticsOpened',
    );
    if (map != null) _updateStatus(map);
  }

  /// Appends one Flutter-side MAIN lifecycle boundary to the native iOS
  /// BLE/HFP timeline. Calls are serialized so their order still reflects the
  /// real dispatcher order when cancellation and assistant activation overlap.
  Future<void> recordMainDiagnostic({
    required String stage,
    String? message,
    Map<String, Object?> values = const <String, Object?>{},
  }) {
    if (!_enabled || defaultTargetPlatform != TargetPlatform.iOS) {
      return Future<void>.value();
    }
    final write = _diagnosticWriteQueue.catchError((Object _) {}).then((
      _,
    ) async {
      await _methodChannel
          .invokeMethod<void>('recordMainDiagnostic', <String, Object?>{
            'stage': stage,
            'message': ?message,
            'dartEventEpochMs': DateTime.now().millisecondsSinceEpoch,
            'values': values,
          });
    });
    _diagnosticWriteQueue = write;
    return write;
  }

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {
    if (!_enabled || !_codec.confirmed) return;
    final packet = _codec.encodeAppState(
      state: state,
      result: result,
      sequence: sequence,
    );
    final write = _writeQueue.catchError((Object _) {}).then((_) async {
      await _methodChannel.invokeMethod<void>('sendAppState', <String, Object?>{
        'bytes': packet.toList(growable: false),
      });
    });
    _writeQueue = write;
    await write;
  }

  void _handleEvent(Object? event) {
    if (event is! Map<Object?, Object?>) return;
    if (event['type'] == 'controlObservation') {
      final source = event['source']?.toString();
      if (source != 'iosRemoteCommand' && source != 'androidMediaKey') return;
      // Never turn an OS command into an accessory MAIN/Power/Volume guess.
      // Export only allowlisted command names/numbers, never arbitrary native
      // diagnostic messages (which may contain speech or credentials).
      final command = event['mediaCommand']?.toString();
      const commands = {
        'play',
        'pause',
        'togglePlayPause',
        'nextTrack',
        'previousTrack',
        'stop',
        'next',
        'previous',
        'playPause',
        'headsetHook',
        'fastForward',
        'rewind',
        'volumeUp',
        'volumeDown',
      };
      final description = <String>[
        if (commands.contains(command)) 'command=$command',
        for (final key in [
          'keyCode',
          'action',
          'repeatCount',
          'holdDurationMs',
        ])
          if (event[key] is num) '$key=${(event[key] as num).toInt()}',
      ].join(' ');
      _buttonController.add(
        Aiv0ButtonEvent(
          rawBytes: Uint8List(0),
          receivedAt:
              _dateTimeFromEpochMilliseconds(event['receivedAtEpochMs']) ??
              DateTime.now(),
          deviceId: event['deviceId']?.toString(),
          transportSource: source,
          gesture: switch (event['gesture']) {
            'longPress' => Aiv0ButtonGesture.longPress,
            'release' => Aiv0ButtonGesture.release,
            _ => Aiv0ButtonGesture.unknown,
          },
          rawDescription: description.isEmpty
              ? 'unknown native command'
              : description,
          isDuplicate: event['duplicate'] == true,
        ),
      );
      return;
    }
    if (event['type'] == 'button') {
      final bytes = (event['bytes'] as List<Object?>? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt() & 0xFF)
          .toList(growable: false);
      final buttonEvent = _codec.decodeButtonEvent(
        Uint8List.fromList(bytes),
        deviceId: event['deviceId']?.toString(),
        receivedAt: _dateTimeFromEpochMilliseconds(event['receivedAtEpochMs']),
      );
      _buttonController.add(
        Aiv0ButtonEvent(
          rawBytes: buttonEvent.rawBytes,
          receivedAt: buttonEvent.receivedAt,
          deviceId: buttonEvent.deviceId,
          transportSource: event['transportSource']?.toString(),
          button: buttonEvent.button,
          gesture: buttonEvent.gesture,
          sequence: buttonEvent.sequence,
          flags: buttonEvent.flags,
          batteryPercent: buttonEvent.batteryPercent,
          uptimeMilliseconds: buttonEvent.uptimeMilliseconds,
          isObservedH20Packet: buttonEvent.isObservedH20Packet,
          isObservedHmD001Packet: buttonEvent.isObservedHmD001Packet,
          isDraftPacket: buttonEvent.isDraftPacket,
          isDuplicate: event['duplicate'] == true,
        ),
      );
      return;
    }
    _updateStatus(event);
  }

  void _updateStatus(Map<Object?, Object?> map) {
    _setStatus(Aiv0BleStatus.fromMap(map, protocolConfirmed: _codec.confirmed));
  }

  DateTime? _dateTimeFromEpochMilliseconds(Object? value) {
    final milliseconds = (value as num?)?.toInt();
    if (milliseconds == null || milliseconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  void _setStatus(Aiv0BleStatus value) {
    _status = value;
    _statusController.add(value);
    _synchronizeBatteryRefresh(value);
  }

  void _synchronizeBatteryRefresh(Aiv0BleStatus value) {
    if (!_enabled || !value.isConnected) {
      _batteryRefreshTimer?.cancel();
      _batteryRefreshTimer = null;
      return;
    }
    if (_batteryRefreshTimer != null) return;
    _batteryRefreshTimer = Timer.periodic(
      _batteryRefreshInterval,
      (_) => unawaited(_refreshBattery()),
    );
  }

  Future<void> _refreshBattery() async {
    if (_batteryRefreshInFlight || !_status.isConnected) return;
    _batteryRefreshInFlight = true;
    try {
      await _methodChannel.invokeMethod<bool>('refreshBattery');
    } on MissingPluginException {
      // Older app binaries keep their one-time battery reading.
    } on PlatformException catch (error) {
      debugPrint('H20 battery refresh skipped: ${error.code}');
    } finally {
      _batteryRefreshInFlight = false;
    }
  }

  @override
  Future<void> dispose() async {
    _invalidateConnectionAttempt();
    _batteryRefreshTimer?.cancel();
    _batteryRefreshTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_enabled) {
      await _methodChannel.invokeMethod<void>('dispose');
    }
    await _statusController.close();
    await _buttonController.close();
  }
}
