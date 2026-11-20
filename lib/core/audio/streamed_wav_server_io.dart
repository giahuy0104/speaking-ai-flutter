import 'dart:async';
import 'dart:io';

import 'streamed_wav_source.dart';

/// Serves [StreamedWavSource]s to the native player (ExoPlayer, AVPlayer) from
/// a loopback HTTP server.
///
/// just_audio's own StreamAudioSource proxy (0.10.6) cannot do this: it clears
/// the response headers, which turns off chunked encoding, then sends a body of
/// unknown length with neither Content-Length nor chunking on a keep-alive
/// connection. The player never sees the end of the clip and only gives up
/// after its read timeout (~8 s on ExoPlayer). It also throws on any Range
/// request while the length is unknown, which AVPlayer always sends first.
///
/// Here a body of unknown length is chunked, so it ends right after the last
/// byte; a Range request is answered once the total is known (206), or with 416
/// when it starts past the end.

final Map<String, StreamedWavSource> _sources = <String, StreamedWavSource>{};
Future<HttpServer>? _server;
int _nextId = 0;

final RegExp _pathPattern = RegExp(r'^/wav/(\d+)\.wav$');
final RegExp _rangePattern = RegExp(r'^bytes=(\d+)-(\d*)$');

/// A loopback URL that plays [source]; valid until [unregisterStreamedWav].
Future<Uri?> registerStreamedWav(StreamedWavSource source) async {
  final HttpServer server;
  try {
    server = await (_server ??= _bind());
  } catch (_) {
    _server = null; // Let the next clip try again.
    rethrow;
  }
  final id = '${++_nextId}';
  _sources[id] = source;
  return Uri(
    scheme: 'http',
    host: server.address.address,
    port: server.port,
    path: '/wav/$id.wav',
  );
}

void unregisterStreamedWav(StreamedWavSource source) {
  _sources.removeWhere((_, registered) => identical(registered, source));
}

Future<HttpServer> _bind() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(
    (request) => unawaited(_handle(request)),
    onError: (Object _) {},
  );
  return server;
}

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  try {
    final id = _pathPattern.firstMatch(request.uri.path)?.group(1);
    final source = id == null ? null : _sources[id];
    if (source == null) {
      return await _reply(response, HttpStatus.notFound);
    }
    final head = request.method == 'HEAD';
    if (!head && request.method != 'GET') {
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      return await _reply(response, HttpStatus.methodNotAllowed);
    }

    // An unparsable or reversed range is ignored (RFC 9110): whole clip.
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final match = rangeHeader == null
        ? null
        : _rangePattern.firstMatch(rangeHeader.trim());
    var start = match == null ? null : int.tryParse(match.group(1)!);
    var last = match == null || match.group(2)!.isEmpty
        ? null
        : int.tryParse(match.group(2)!);
    if (start == null ||
        (match!.group(2)!.isNotEmpty && last == null) ||
        (last != null && last < start)) {
      start = null;
      last = null;
    }
    final range = start;

    final StreamedWavSlice slice;
    try {
      slice = await source.request(start, last == null ? null : last + 1);
    } on StreamedWavRangeNotSatisfiable catch (error) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${error.total}',
      );
      return await _reply(response, HttpStatus.requestedRangeNotSatisfiable);
    } catch (_) {
      return await _reply(response, HttpStatus.badGateway);
    }

    response.headers.contentType = ContentType.parse(slice.contentType);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final length = slice.length;
    if (range != null && length != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${slice.offset}-${slice.offset + length - 1}/${slice.total}',
      );
      response.contentLength = length;
    } else if (length != null) {
      response.statusCode = HttpStatus.ok;
      response.contentLength = length;
    } else {
      // Still downloading: chunked, so the end of the body is the end of the
      // clip and the player sees it at once.
      response.statusCode = HttpStatus.ok;
      response.headers.chunkedTransferEncoding = true;
    }
    if (head) {
      await response.close();
      return;
    }
    // Hand each chunk to the player as soon as it arrives.
    response.bufferOutput = false;
    await response.addStream(slice.stream);
    await response.close();
  } catch (_) {
    // The player went away (seek, stop, new clip): nothing to answer.
    try {
      await response.close();
    } catch (_) {}
  }
}

Future<void> _reply(HttpResponse response, int status) async {
  response.statusCode = status;
  response.contentLength = 0;
  await response.close();
}
