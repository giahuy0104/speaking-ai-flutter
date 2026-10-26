import 'dart:async';

import 'package:flutter/foundation.dart';

import 'aiv0_ble_control.dart';

/// Radio availability, independent of permissions, pairing and HOMI readiness.
/// Only a fresh platform state can reveal connection actions; accepting an OS
/// dialog alone never means that Bluetooth or the headset is connected.
class BluetoothPowerController extends ChangeNotifier {
  BluetoothPowerController({
    required Future<Aiv0BluetoothAdapterState> Function() readState,
    required Future<bool> Function() requestEnable,
    required Future<bool> Function() requestPermission,
    required this.canRequestEnable,
    Future<bool> Function()? openPermissionSettings,
    Future<bool> Function()? permissionRequiresSettings,
  }) : _readState = readState,
       _requestEnable = requestEnable,
       _requestPermission = requestPermission,
       _openPermissionSettings = openPermissionSettings,
       _permissionRequiresSettings = permissionRequiresSettings;

  final Future<Aiv0BluetoothAdapterState> Function() _readState;
  final Future<bool> Function() _requestEnable;
  final Future<bool> Function() _requestPermission;
  final Future<bool> Function()? _openPermissionSettings;
  final Future<bool> Function()? _permissionRequiresSettings;
  final bool canRequestEnable;
  Aiv0BluetoothAdapterState _state = Aiv0BluetoothAdapterState.unknown;
  bool _hasChecked = false;
  bool _actionFailed = false;
  bool _needsPermissionSettings = false;
  bool _disposed = false;
  Future<void>? _refresh;
  Future<bool>? _action;

  Aiv0BluetoothAdapterState get state => _state;
  bool get hasChecked => _hasChecked;
  bool get isBusy => _refresh != null || _action != null;
  bool get actionFailed => _actionFailed;
  bool get canOpenPermissionSettings => _openPermissionSettings != null;
  bool get needsPermissionSettings => _needsPermissionSettings;
  bool get canConnect =>
      _hasChecked && !isBusy && _state == Aiv0BluetoothAdapterState.poweredOn;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final pending = _refresh;
    if (pending != null) return pending;
    final operation = _loadState();
    _refresh = operation;
    _notify();
    return operation.whenComplete(() {
      if (identical(_refresh, operation)) _refresh = null;
      _notify();
    });
  }

  Future<void> _loadState() async {
    Aiv0BluetoothAdapterState value;
    try {
      value = await _readState();
    } catch (_) {
      value = Aiv0BluetoothAdapterState.unknown;
    }
    if (_disposed) return;
    _state = value;
    _hasChecked = true;
    _needsPermissionSettings = false;
    if (value == Aiv0BluetoothAdapterState.unauthorized) {
      try {
        final needsSettings =
            await _permissionRequiresSettings?.call() ?? false;
        if (_disposed) return;
        _needsPermissionSettings = needsSettings;
      } catch (_) {
        // An unavailable query is not evidence of a permanent denial.
      }
    }
    if (value == Aiv0BluetoothAdapterState.poweredOn) _actionFailed = false;
  }

  Future<bool> enable() => _performAction(enableRadio: true);
  Future<bool> authorize() => _performAction(enableRadio: false);

  Future<bool> openPermissionSettings() async {
    if (_disposed) return false;
    try {
      return await _openPermissionSettings?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _performAction({required bool enableRadio}) {
    if (_disposed) return Future<bool>.value(false);
    final pending = _action;
    if (pending != null) return pending;
    final operation = _runAction(enableRadio: enableRadio);
    _action = operation;
    _notify();
    return operation.whenComplete(() {
      if (identical(_action, operation)) _action = null;
      _notify();
    });
  }

  Future<bool> _runAction({required bool enableRadio}) async {
    _actionFailed = false;
    await refresh();
    if (_disposed) return false;
    try {
      if (_state == Aiv0BluetoothAdapterState.unauthorized) {
        final granted = await _requestPermission();
        if (_disposed) return false;
        await refresh();
        if (!granted) {
          _actionFailed = true;
          return false;
        }
      }
      if (enableRadio &&
          canRequestEnable &&
          _state == Aiv0BluetoothAdapterState.poweredOff) {
        await _requestEnable();
        if (_disposed) return false;
        await refresh();
        // Some Android versions return from the dialog while the adapter is
        // still turning on. Check radio settling only; never scan/retry HOMI.
        for (
          var i = 0;
          !_disposed && _state == Aiv0BluetoothAdapterState.resetting && i < 4;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (_disposed) return false;
          await refresh();
        }
      }
    } catch (error) {
      debugPrint('Bluetooth power action failed: $error');
      if (_disposed) return false;
      await refresh();
      if (!_disposed && _state == Aiv0BluetoothAdapterState.poweredOn) {
        _actionFailed = false;
        return true;
      }
      _actionFailed = true;
      return false;
    }
    if (_disposed) return false;
    final succeeded = enableRadio
        ? _state == Aiv0BluetoothAdapterState.poweredOn
        : _state == Aiv0BluetoothAdapterState.poweredOn ||
              _state == Aiv0BluetoothAdapterState.poweredOff;
    _actionFailed = !succeeded;
    return succeeded;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
