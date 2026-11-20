import 'package:http/http.dart' as http;

import 'streamed_wav_server.dart';
import 'streamed_wav_source.dart';

/// One live backend speech stream played on Android through the loopback
/// [StreamedWavSource] server instead of handing ExoPlayer the backend URL.
///
/// The backend streams long sentences as WAV whose header says 0xFFFFFFFF
/// data bytes. ExoPlayer turns that into a ~24.8 hour duration and only
/// reports `ended` once its position reaches that duration, so a sentence that
/// has finished sounding never completes. [source] counts the bytes that really
/// arrive; the playback service pauses the player at
/// [StreamedWavSource.playableDuration] itself (see [StreamedWavEndDetector])
/// and, with [ended] set, reports that pause as the clip's completion.
class StreamedWavPlayback {
  StreamedWavPlayback._(this.originalUri, this.source, this.playerUri);

  /// The backend URL the caller asked to play.
  final Uri originalUri;
  final StreamedWavSource source;

  /// The loopback URL handed to the native player.
  final Uri playerUri;

  /// Set once the sound reached its real end, so a replay rewinds first.
  bool ended = false;
  bool _closed = false;

  /// Starts downloading [uri] at once and registers it with the loopback
  /// server. Null when no server is available (web), so the caller plays the
  /// original URL.
  static Future<StreamedWavPlayback?> open(
    Uri uri, {
    http.Client? client,
  }) async {
    final source = StreamedWavSource(uri, client: client);
    final Uri? playerUri;
    try {
      playerUri = await registerStreamedWav(source);
    } catch (_) {
      source.cancel();
      rethrow;
    }
    if (playerUri == null) {
      source.cancel();
      return null;
    }
    // Download while the player prepares: the first bytes are already in
    // memory when ExoPlayer asks the loopback server for them.
    source.start();
    return StreamedWavPlayback._(uri, source, playerUri);
  }

  /// Stops the download and frees the loopback URL.
  void close() {
    if (_closed) return;
    _closed = true;
    source.cancel();
    unregisterStreamedWav(source);
  }
}

/// Decides when a [StreamedWavPlayback] has played all of its sound.
///
/// Fed with the player's state on every tick. Nothing ends while the clip is
/// still downloading: the player may simply be waiting for synthesis. Once the
/// download is over, the clip ends when the position reaches the real
/// duration, or when the playing position stops moving for [stallTimeout]
/// (the player ran out of bytes slightly before that duration).
class StreamedWavEndDetector {
  StreamedWavEndDetector({
    this.tolerance = const Duration(milliseconds: 120),
    this.stallTimeout = const Duration(milliseconds: 1500),
  });

  /// How early, before the real duration, the clip counts as finished.
  final Duration tolerance;

  /// How long a playing position may stay still after the download ended.
  final Duration stallTimeout;

  static const _stillThreshold = Duration(milliseconds: 10);

  Duration? _lastPosition;
  DateTime? _stillSince;

  bool observe({
    required Duration? playableDuration,
    required Duration position,
    required bool playing,
    required DateTime now,
  }) {
    if (!playing || playableDuration == null) {
      _lastPosition = null;
      _stillSince = null;
      return false;
    }
    if (position >= playableDuration - tolerance) return true;
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null || (position - last).abs() > _stillThreshold) {
      _stillSince = null;
      return false;
    }
    final stillSince = _stillSince ??= now;
    return now.difference(stillSince) >= stallTimeout;
  }
}
