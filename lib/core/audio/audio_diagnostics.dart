import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Opt-in timing only; never records transcripts, credentials or audio bytes.
class AudioDiagnostics {
  static const enabled = bool.fromEnvironment('HOMI_AUDIO_DIAGNOSTICS');
  static int _sequence = 0;
  static final Stopwatch _clock = Stopwatch()..start();

  static int nextId() => ++_sequence;

  static void event(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    debugPrintSynchronously(
      'HOMI_DIAG ${jsonEncode({'event': event, 'utcMs': DateTime.now().millisecondsSinceEpoch, 'elapsedUs': _clock.elapsedMicroseconds, ...fields})}',
    );
  }
}
