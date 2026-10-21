import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ConnectionDeviceTransport { ble, hfp }

/// The most recent successful connection on one transport. Names are the raw
/// names supplied by the device/OS, never a translated UI fallback.
class ConnectionDeviceRecord {
  const ConnectionDeviceRecord({
    required this.id,
    required this.name,
    required this.transport,
    required this.connectedAt,
    this.platform,
    this.bleDeviceId,
  });

  factory ConnectionDeviceRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final timestamp = json['connectedAt'];
    final platform = json['platform'];
    final bleDeviceId = json['bleDeviceId'];
    final transport = switch (json['transport']) {
      'ble' => ConnectionDeviceTransport.ble,
      'hfp' => ConnectionDeviceTransport.hfp,
      _ => null,
    };
    final connectedAt = timestamp is String
        ? DateTime.tryParse(timestamp)?.toUtc()
        : null;
    if (json['version'] != 1 ||
        id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        transport == null ||
        connectedAt == null ||
        (platform != null && platform is! String) ||
        (bleDeviceId != null && bleDeviceId is! String)) {
      throw const FormatException('Invalid device connection history record.');
    }
    return ConnectionDeviceRecord(
      id: id.trim(),
      name: name.trim(),
      transport: transport,
      connectedAt: connectedAt,
      platform: platform as String?,
      bleDeviceId: bleDeviceId as String?,
    );
  }

  final String id;
  final String name;
  final ConnectionDeviceTransport transport;
  final DateTime connectedAt;
  final String? platform;

  /// An explicitly validated BLE association for this microphone. This is not
  /// inferred from a display name, and is absent for unassociated microphones.
  final String? bleDeviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'id': id.trim(),
    'name': name.trim(),
    'transport': transport.name,
    'connectedAt': connectedAt.toUtc().toIso8601String(),
    if (platform != null) 'platform': platform,
    if (bleDeviceId != null) 'bleDeviceId': bleDeviceId,
  };
}

/// Stores BLE and microphone history independently. Callers save only after
/// native/controller state confirms success; disconnect never clears history.
class DeviceConnectionHistoryStore {
  DeviceConnectionHistoryStore({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _bleKey = 'homi.device-connection-history.ble.v1';
  static const _microphoneKey = 'homi.device-connection-history.microphone.v1';

  final Future<SharedPreferences> Function() _preferences;
  Future<void> _pendingWrite = Future<void>.value();

  Future<ConnectionDeviceRecord?> readBle() =>
      _read(_bleKey, ConnectionDeviceTransport.ble);

  Future<ConnectionDeviceRecord?> readMicrophone() =>
      _read(_microphoneKey, ConnectionDeviceTransport.hfp);

  Future<void> saveBle(ConnectionDeviceRecord record) =>
      _save(_bleKey, ConnectionDeviceTransport.ble, record);

  Future<void> saveMicrophone(ConnectionDeviceRecord record) =>
      _save(_microphoneKey, ConnectionDeviceTransport.hfp, record);

  Future<ConnectionDeviceRecord?> _read(
    String key,
    ConnectionDeviceTransport transport,
  ) async {
    await _pendingWrite;
    try {
      final encoded = (await _preferences()).getString(key);
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) return null;
      final record = ConnectionDeviceRecord.fromJson(decoded);
      return record.transport == transport ? record : null;
    } catch (_) {
      // Keep corrupt/unsupported data intact for recovery or future migration.
      return null;
    }
  }

  Future<void> _save(
    String key,
    ConnectionDeviceTransport transport,
    ConnectionDeviceRecord record,
  ) {
    if (record.transport != transport || record.id.trim().isEmpty) {
      return Future<void>.error(
        ArgumentError.value(record, 'record', 'Wrong transport or empty ID.'),
      );
    }
    final operation = _pendingWrite.then((_) async {
      final preferences = await _preferences();
      final saved = await preferences.setString(
        key,
        jsonEncode(record.toJson()),
      );
      if (!saved) throw StateError('Unable to save device connection history.');
    });
    // A failed write must not block later connections from saving their record.
    _pendingWrite = operation.catchError((Object _) {});
    return operation;
  }
}
