import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Bytes of a [StreamedWavSource] from [offset]. [length] and [total] are null
/// while the clip is still downloading (its real size is not known yet).
class StreamedWavSlice {
  const StreamedWavSlice({
    required this.offset,
    required this.stream,
    required this.contentType,
    this.length,
    this.total,
  });

  final int offset;
  final int? length;
  final int? total;

  /// As the backend sent it: `audio/wav` for a stream, `audio/mpeg` for a
  /// finished clip of a short sentence.
  final String contentType;
  final Stream<List<int>> stream;
}

/// A byte range that starts at or past the end of a finished clip (HTTP 416).
class StreamedWavRangeNotSatisfiable implements Exception {
  const StreamedWavRangeNotSatisfiable(this.total);

  final int total;

  @override
  String toString() => 'StreamedWavRangeNotSatisfiable(total: $total)';
}

class _StreamedWavCancelled implements Exception {
  const _StreamedWavCancelled();

  @override
  String toString() => 'StreamedWavSource cancelled';
}

/// Downloads a WAV that the backend streams while it is still being synthesized
/// (`/api/audio/target`) and serves it, from memory, to the native player
/// through [StreamedWavServer] while it arrives.
///
/// Its header carries an unknown length (0xFFFFFFFF), so the native player
/// believes the clip lasts ~24.8 hours and never reports `completed`. This
/// class knows the real length once the download ends ([realDuration]), so the
/// caller can stop playback exactly when the sound does.
class StreamedWavSource {
  StreamedWavSource(
    this.uri, {
    http.Client? client,
    this.connectTimeout = defaultConnectTimeout,
    this.idleTimeout = defaultIdleTimeout,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// Time allowed for the response headers.
  static const defaultConnectTimeout = Duration(seconds: 10);

  /// Longest gap allowed between two chunks (and before the first one, which
  /// waits for the TTS provider). The backend gives up after 20 s itself.
  static const defaultIdleTimeout = Duration(seconds: 20);

  static const _headerBytes = 44;

  final Uri uri;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final http.Client _client;
  final bool _ownsClient;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _length = 0;
  Completer<void> _changed = Completer<void>();
  StreamSubscription<List<int>>? _download;
  bool _started = false;
  bool _done = false;
  Object? _error;
  String _contentType = 'audio/wav';

  /// The backend's content type; `audio/wav` until the response arrives.
  /// Short sentences come as a finished `audio/mpeg` clip (backend cách B).
  String get contentType => _contentType;

  /// A WAV stream, whose header carries no length; an MP3 ends by itself.
  bool get isWav => _contentType.toLowerCase().contains('wav');

  /// The whole clip arrived.
  bool get isDownloaded => _done && _error == null;

  /// The download ended early (HTTP error, disconnect, stall or [cancel]).
  bool get failed => _done && _error != null;

  int get receivedBytes => _length;

  /// The real length of the sound; null until the whole clip has arrived.
  Duration? get realDuration => isDownloaded ? playableDuration : null;

  /// Length of the sound that can be played once the download has ended,
  /// whether it completed or failed part way; null while still downloading.
  /// Null for an MP3 clip: the player knows its length and completes on its own.
  Duration? get playableDuration => !isWav
      ? null
      : _done
      ? wavDuration(_slice(0, math.min(_headerBytes, _length)), _length)
      : null;

  /// Starts the download if it has not started yet.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  /// Stops the download; readers end with the bytes received so far.
  void cancel() {
    if (_done) return;
    _finish(const _StreamedWavCancelled());
  }

  Future<void> _run() async {
    try {
      final response = await _client
          .send(http.Request('GET', uri))
          .timeout(connectTimeout);
      if (_done) {
        // Cancelled while connecting.
        unawaited(response.stream.listen(null).cancel());
        return;
      }
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Audio request failed with HTTP ${response.statusCode}',
          uri.replace(query: ''),
        );
      }
      _contentType = response.headers['content-type'] ?? _contentType;
      _download = response.stream
          .timeout(idleTimeout)
          .listen(
            _append,
            onError: (Object error) => _finish(error),
            onDone: () => _finish(null),
            cancelOnError: true,
          );
    } catch (error) {
      _finish(error);
    }
  }

  void _append(List<int> chunk) {
    if (_done || chunk.isEmpty) return;
    _chunks.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    _length += chunk.length;
    _notify();
  }

  void _finish(Object? error) {
    if (_done) return;
    _done = true;
    _error = error;
    final download = _download;
    _download = null;
    if (download != null) unawaited(download.cancel());
    if (_ownsClient) _client.close();
    _notify();
  }

  void _notify() {
    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  /// Bytes from [start]; [end] is exclusive.
  ///
  /// A plain request (no [start]/[end]) is answered as soon as a byte exists and
  /// streams the rest as it arrives. A ranged request waits for the whole clip:
  /// a range answer must state the total size, which is unknown until then.
  Future<StreamedWavSlice> request([int? start, int? end]) async {
    this.start();
    final ranged = start != null || end != null;
    final from = start ?? 0;
    while (!_done && (ranged || _length <= from)) {
      await _changed.future;
    }
    final error = _error;
    if (error != null && (ranged || _length <= from)) throw error;
    final total = _done ? _length : null;
    if (total != null && from >= total) {
      throw StreamedWavRangeNotSatisfiable(total);
    }
    final limit = total == null ? null : math.min(end ?? total, total);
    return StreamedWavSlice(
      contentType: contentType,
      offset: from,
      length: limit == null ? null : limit - from,
      total: total,
      stream: _read(from, limit ?? end),
    );
  }

  Stream<List<int>> _read(int from, int? end) async* {
    var position = from;
    while (true) {
      // Taken before the checks: a chunk arriving afterwards completes it.
      final changed = _changed.future;
      final limit = end == null ? _length : math.min(end, _length);
      if (position < limit) {
        yield _slice(position, limit);
        position = limit;
        // Re-check: more bytes or the end may have arrived while suspended.
        continue;
      }
      if (end != null && position >= end) return;
      // A failed download ends here too: the player plays what arrived and
      // the caller stops at [playableDuration].
      if (_done) return;
      await changed;
    }
  }

  Uint8List _slice(int start, int end) {
    final out = Uint8List(math.max(0, end - start));
    var offset = 0;
    for (final chunk in _chunks) {
      final chunkEnd = offset + chunk.length;
      if (chunkEnd > start && offset < end) {
        final from = math.max(start, offset) - offset;
        final to = math.min(end, chunkEnd) - offset;
        out.setRange(
          math.max(start, offset) - start,
          math.max(start, offset) - start + (to - from),
          chunk,
          from,
        );
      }
      if (chunkEnd >= end) break;
      offset = chunkEnd;
    }
    return out;
  }

  /// Backend routes that stream speech while it is being synthesized: English
  /// (`/api/audio/stream`), the other target languages (`/api/audio/target`)
  /// and the dev-only segmented speech (`/api/audio/segments`). Each one can
  /// also answer with a finished MP3 or a redirect to the cache; those play
  /// through this source too and complete on their own.
  static bool handles(Uri uri) =>
      (uri.isScheme('https') || uri.isScheme('http')) &&
      _streamingRoutes.any(uri.path.endsWith);

  static const _streamingRoutes = <String>[
    '/api/audio/stream',
    '/api/audio/target',
    '/api/audio/segments',
  ];

  /// Duration of a PCM WAV with a 44-byte header, from its byte rate and the
  /// number of bytes actually received; null when the header is not PCM WAV.
  static Duration? wavDuration(List<int> bytes, int totalBytes) {
    if (bytes.length < _headerBytes || totalBytes < _headerBytes) return null;
    String ascii(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (ascii(0) != 'RIFF' || ascii(8) != 'WAVE' || ascii(36) != 'data') {
      return null;
    }
    final byteRate =
        bytes[28] | (bytes[29] << 8) | (bytes[30] << 16) | (bytes[31] << 24);
    if (byteRate <= 0) return null;
    return Duration(
      microseconds: ((totalBytes - _headerBytes) * 1000000 / byteRate).round(),
    );
  }
}
