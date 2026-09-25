import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

typedef AudioDiagnosticObserver = void Function(Map<String, Object?> payload);

/// Opt-in timing only; never records transcripts, credentials or audio bytes.
class AudioDiagnostics {
  static const enabled = bool.fromEnvironment('HOMI_AUDIO_DIAGNOSTICS');
  static int _sequence = 0;
  static final Stopwatch _clock = Stopwatch()..start();
  static AudioDiagnosticObserver? _testObserver;

  static const Set<String> _reservedFields = <String>{
    'event',
    'utcMs',
    'elapsedUs',
    'platform',
    'lifecycle',
  };

  static const Set<String> _sensitiveFields = <String>{
    'text',
    'prompttext',
    'transcript',
    'recognizedtext',
    'recordingpath',
    'filepath',
    'path',
    'uri',
    'url',
    'deviceid',
    'rawhex',
    'rawpayload',
    'bytes',
    'credential',
    'credentials',
    'secret',
    'authorization',
  };

  static int nextId() => ++_sequence;

  static bool get isActive => enabled || _testObserver != null;

  static String stableId(Iterable<Object?> parts) {
    final source = parts.map((part) => part?.toString() ?? '').join('\u001f');
    return sha256.convert(utf8.encode(source)).toString().substring(0, 12);
  }

  static void event(String event, [Map<String, Object?> fields = const {}]) {
    final observer = _testObserver;
    if (!enabled && observer == null) return;
    final payload = buildPayload(
      event,
      fields,
      utcMs: DateTime.now().millisecondsSinceEpoch,
      elapsedUs: _clock.elapsedMicroseconds,
    );
    observer?.call(Map<String, Object?>.unmodifiable(payload));
    if (enabled) {
      debugPrintSynchronously('HOMI_DIAG ${jsonEncode(payload)}');
    }
  }

  @visibleForTesting
  static Map<String, Object?> buildPayload(
    String event,
    Map<String, Object?> fields, {
    required int utcMs,
    required int elapsedUs,
  }) {
    final payload = <String, Object?>{
      for (final entry in fields.entries)
        if (!_reservedFields.contains(entry.key))
          entry.key: _sanitizeField(entry.key, entry.value),
      'event': event,
      'utcMs': utcMs,
      'elapsedUs': elapsedUs,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'lifecycle': _lifecycleName(),
    };
    return payload;
  }

  @visibleForTesting
  static void setObserverForTesting(AudioDiagnosticObserver? observer) {
    _testObserver = observer;
  }

  static Object? _sanitizeField(String key, Object? value) {
    final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (_sensitiveFields.contains(normalized) ||
        normalized.endsWith('transcript') ||
        normalized.endsWith('recordingpath') ||
        normalized.endsWith('filepath')) {
      return '<redacted>';
    }
    return _sanitizeValue(value);
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Iterable<Object?>) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeField(
            entry.key.toString(),
            entry.value,
          ),
      };
    }
    return value.runtimeType.toString();
  }

  static String _lifecycleName() {
    try {
      return WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';
    } catch (_) {
      return 'uninitialized';
    }
  }
}
