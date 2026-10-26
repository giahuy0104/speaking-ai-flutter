import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bluetooth_power_controller.dart';

enum DeviceConnectionPhase {
  disconnected,
  searching,
  connecting,
  preparingMicrophone,
  ready,
  failed,
}

/// Owns user-requested connection work across Settings and protected actions.
/// Background transport status is observed without opening any UI.
class DeviceConnectionCoordinator extends ChangeNotifier {
  DeviceConnectionCoordinator({
    required Future<bool> Function() onConnect,
    required Future<void> Function() onCancel,
    required Future<void> Function() onOpenBluetoothSettings,
    this.bluetoothPower,
  }) : _onConnect = onConnect,
       _onCancel = onCancel,
       _onOpenBluetoothSettings = onOpenBluetoothSettings;

  final Future<bool> Function() _onConnect;
  final Future<void> Function() _onCancel;
  final Future<void> Function() _onOpenBluetoothSettings;
  final BluetoothPowerController? bluetoothPower;
  DeviceConnectionPhase _phase = DeviceConnectionPhase.disconnected;
  DeviceConnectionPhase _transportPhase = DeviceConnectionPhase.disconnected;
  int _generation = 0;
  int? _owner;
  bool _manual = false;
  bool _disposed = false;
  Completer<void>? _cancelled;
  Future<void>? _cancellation;

  DeviceConnectionPhase get phase => _phase;
  bool get isBusy => _owner != null || _cancellation != null;
  bool get hasManualOperation => _owner != null;

  bool isCurrent(int token) => !_disposed && _owner == token;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void updateStatus(DeviceConnectionPhase phase) {
    _transportPhase = phase;
    // An unrelated idle status (for example a battery refresh) must not erase
    // the failed round's retry guidance. A fresh attempt or recovery clears it.
    if (_owner == null &&
        _phase == DeviceConnectionPhase.failed &&
        phase == DeviceConnectionPhase.disconnected) {
      return;
    }
    if (_manual ||
        (_owner != null && phase == DeviceConnectionPhase.disconnected)) {
      return;
    }
    if (_phase == phase) return;
    _phase = phase;
    _notify();
  }

  Future<void> _cancelTransport() {
    final pending = _cancellation;
    if (pending != null) return pending;
    final operation = Future<void>.sync(_onCancel);
    _cancellation = operation;
    return operation.whenComplete(() {
      if (identical(_cancellation, operation)) _cancellation = null;
      _notify();
    });
  }

  Future<int?> beginManualOperation() async {
    if (_disposed || isBusy) return null;
    final token = ++_generation;
    _owner = token;
    _manual = true;
    _phase = DeviceConnectionPhase.searching;
    _notify();
    try {
      await _cancelTransport();
      return isCurrent(token) ? token : null;
    } catch (_) {
      endManualOperation(token);
      rethrow;
    }
  }

  void setManualPhase(int token, DeviceConnectionPhase phase) {
    if (!isCurrent(token)) return;
    _phase = phase;
    _notify();
  }

  void endManualOperation(int token) {
    if (!isCurrent(token)) return;
    _owner = null;
    _manual = false;
    _phase = _transportPhase;
    _notify();
  }

  Future<bool> connect() async {
    if (_disposed || isBusy) return false;
    final token = ++_generation;
    final cancelled = Completer<void>();
    _owner = token;
    _cancelled = cancelled;
    _phase = DeviceConnectionPhase.searching;
    _notify();
    try {
      final connected = await Future.any<bool>(<Future<bool>>[
        Future<bool>.sync(_onConnect),
        cancelled.future.then((_) => false),
      ]);
      if (!isCurrent(token)) return false;
      _phase = connected
          ? DeviceConnectionPhase.ready
          : DeviceConnectionPhase.failed;
      return connected;
    } catch (_) {
      if (isCurrent(token)) _phase = DeviceConnectionPhase.failed;
      return false;
    } finally {
      if (isCurrent(token)) {
        _owner = null;
        _cancelled = null;
        _notify();
      }
    }
  }

  Future<void> cancel() {
    if (_disposed) return Future<void>.value();
    _generation++;
    _owner = null;
    _manual = false;
    _cancelled?.complete();
    _cancelled = null;
    _phase = DeviceConnectionPhase.disconnected;
    final operation = _cancelTransport();
    _notify();
    return operation;
  }

  Future<void> openBluetoothSettings() => _onOpenBluetoothSettings();

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _cancelled?.complete();
    _cancelled = null;
    super.dispose();
  }
}
