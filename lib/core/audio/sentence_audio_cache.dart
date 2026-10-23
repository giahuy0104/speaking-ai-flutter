import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'sentence_audio_storage.dart';

class SentenceAudioDownloadException implements Exception {
  const SentenceAudioDownloadException(this.code, [this.status]);
  final String code;
  final int? status;
}

/// Bounded, turn-owned cache. It never calls preload/setSource on a player.
class SentenceAudioCache {
  SentenceAudioCache({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final _clients = <http.Client>{};
  final _uris = <Uri>{};
  bool _closed = false;

  Future<Uri> fetch(Uri uri, {String? checksum}) async {
    if (_closed) throw const SentenceAudioDownloadException('cancelled');
    if (!uri.isScheme('https') && !uri.isScheme('http')) return uri;
    final client = _clientFactory();
    _clients.add(client);
    try {
      final bytes = await (() async {
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw SentenceAudioDownloadException('http', response.statusCode);
        }
        const maximumBytes = 2 * 1024 * 1024;
        if ((response.contentLength ?? 0) > maximumBytes) {
          throw const SentenceAudioDownloadException('audio_too_large');
        }
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (_closed) throw const SentenceAudioDownloadException('cancelled');
          if (buffer.length + chunk.length > maximumBytes) {
            throw const SentenceAudioDownloadException('audio_too_large');
          }
          buffer.add(chunk);
        }
        final bytes = buffer.takeBytes();
        if (bytes.isEmpty) {
          throw const SentenceAudioDownloadException('empty_audio');
        }
        if (checksum != null &&
            sha256.convert(bytes).toString() != checksum.toLowerCase()) {
          throw const SentenceAudioDownloadException('checksum');
        }
        return bytes;
      })().timeout(const Duration(seconds: 8));
      if (_closed) throw const SentenceAudioDownloadException('cancelled');
      final cached = await storeSentenceAudio(bytes, 'audio/mpeg');
      if (_closed) {
        await releaseSentenceAudio(cached);
        throw const SentenceAudioDownloadException('cancelled');
      }
      _uris.add(cached);
      return cached;
    } on SentenceAudioDownloadException {
      rethrow;
    } on TimeoutException {
      throw const SentenceAudioDownloadException('timeout');
    } on http.ClientException {
      throw const SentenceAudioDownloadException('network');
    } catch (_) {
      throw const SentenceAudioDownloadException('audio_cache');
    } finally {
      _clients.remove(client);
      client.close();
    }
  }

  Future<void> release(Uri uri) async {
    if (_uris.remove(uri)) await releaseSentenceAudio(uri);
  }

  Future<void> close() async {
    _closed = true;
    for (final client in _clients.toList()) {
      client.close();
    }
    for (final uri in _uris.toList()) {
      await release(uri);
    }
  }
}
