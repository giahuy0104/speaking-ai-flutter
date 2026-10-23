import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DeviceAudioCache {
  DeviceAudioCache({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    this.maxFiles = 256,
    this.maxBytes = 64 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _directoryProvider;
  final int maxFiles;
  final int maxBytes;
  final Map<String, Future<Uri?>> _downloads = <String, Future<Uri?>>{};
  Future<Directory>? _cacheDirectory;

  Future<Uri> resolve(Uri remoteUri) async {
    if (!remoteUri.isScheme('http') && !remoteUri.isScheme('https')) {
      return remoteUri;
    }
    final file = await _fileFor(remoteUri);
    if (await file.exists() && await file.length() > 0) {
      unawaited(file.setLastModified(DateTime.now()));
      return file.uri;
    }
    return remoteUri;
  }

  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async {
    final inFlight = _downloads['${remoteUri.toString()}\u0000'];
    if (inFlight != null) {
      final cached = await inFlight.timeout(maxWait, onTimeout: () => null);
      if (cached != null) {
        return cached;
      }
    }
    return resolve(remoteUri);
  }

  Future<Uri?> cache(Uri remoteUri) {
    // General lesson audio can legitimately be much larger than a short
    // generated assistant response. Keep the strict 2 MB limit scoped to
    // checksum-verified dynamic speech.
    return _cache(remoteUri, maximumFileBytes: maxBytes);
  }

  Future<Uri?> cacheVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    int maximumFileBytes = 2 * 1024 * 1024,
  }) => _cache(
    remoteUri,
    sha256Checksum: sha256Checksum.toLowerCase(),
    maximumFileBytes: maximumFileBytes,
  );

  Future<Uri?> _cache(
    Uri remoteUri, {
    String? sha256Checksum,
    int maximumFileBytes = 2 * 1024 * 1024,
  }) {
    if (!remoteUri.isScheme('http') && !remoteUri.isScheme('https')) {
      return Future<Uri?>.value(remoteUri);
    }
    final key = '${remoteUri.toString()}\u0000${sha256Checksum ?? ''}';
    return _downloads.putIfAbsent(key, () async {
      try {
        final target = await _fileFor(remoteUri);
        if (await target.exists() && await target.length() > 0) {
          if (sha256Checksum == null ||
              await _matchesChecksum(target, sha256Checksum)) {
            unawaited(target.setLastModified(DateTime.now()));
            return target.uri;
          }
          await target.delete();
        }
        final response = await _client
            .get(remoteUri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            response.bodyBytes.isEmpty ||
            response.bodyBytes.length > maximumFileBytes ||
            (sha256Checksum != null &&
                sha256.convert(response.bodyBytes).toString() !=
                    sha256Checksum)) {
          return null;
        }

        final temporary = File('${target.path}.part');
        await temporary.writeAsBytes(response.bodyBytes, flush: true);
        if (await target.exists()) {
          await target.delete();
        }
        await temporary.rename(target.path);
        unawaited(_prune());
        return target.uri;
      } catch (_) {
        return null;
      } finally {
        _downloads.remove(key);
      }
    });
  }

  Future<Uri> resolveVerified(
    Uri remoteUri, {
    required String sha256Checksum,
  }) async {
    if (!remoteUri.isScheme('http') && !remoteUri.isScheme('https')) {
      return remoteUri;
    }
    final file = await _fileFor(remoteUri);
    if (await file.exists() &&
        await _matchesChecksum(file, sha256Checksum.toLowerCase())) {
      unawaited(file.setLastModified(DateTime.now()));
      return file.uri;
    }
    if (await file.exists()) await file.delete();
    return remoteUri;
  }

  Future<Uri> resolveAfterPreloadVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    Duration maxWait = const Duration(milliseconds: 500),
  }) async {
    final key = '${remoteUri.toString()}\u0000${sha256Checksum.toLowerCase()}';
    final inFlight = _downloads[key];
    if (inFlight != null) {
      final cached = await inFlight.timeout(maxWait, onTimeout: () => null);
      if (cached != null) return cached;
    }
    return resolveVerified(remoteUri, sha256Checksum: sha256Checksum);
  }

  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {
    var pending = remoteUris
        .where((uri) => uri.isScheme('http') || uri.isScheme('https'))
        .map((uri) => uri.toString())
        .toSet()
        .take(limit)
        .map(Uri.parse)
        .toList(growable: false);
    const concurrency = 3;
    for (var attempt = 0; attempt < 2 && pending.isNotEmpty; attempt += 1) {
      final failed = <Uri>[];
      for (var index = 0; index < pending.length; index += concurrency) {
        final batch = pending.skip(index).take(concurrency).toList();
        final results = await Future.wait(
          batch.map(cache).map((future) => future.catchError((_) => null)),
        );
        for (var item = 0; item < batch.length; item += 1) {
          if (results[item] == null) {
            failed.add(batch[item]);
          }
        }
      }
      pending = failed;
    }
  }

  Future<void> evict(Uri remoteUri) async {
    _downloads.remove(remoteUri.toString());
    final file = await _fileFor(remoteUri);
    if (await file.exists()) await file.delete();
  }

  Future<File> _fileFor(Uri uri) async {
    final directory = await (_cacheDirectory ??= _createCacheDirectory());
    return File(
      '${directory.path}${Platform.pathSeparator}${_fnv1a(uri.toString())}.mp3',
    );
  }

  Future<Directory> _createCacheDirectory() async {
    final support = await _directoryProvider();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}rule_audio_cache',
    );
    return directory.create(recursive: true);
  }

  Future<void> _prune() async {
    final directory = await (_cacheDirectory ??= _createCacheDirectory());
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.mp3'))
        .cast<File>()
        .toList();
    final dated = await Future.wait(
      files.map(
        (file) async => (
          file: file,
          modified: await file.lastModified(),
          bytes: await file.length(),
        ),
      ),
    );
    dated.sort((a, b) => a.modified.compareTo(b.modified));
    var totalBytes = dated.fold<int>(0, (sum, item) => sum + item.bytes);
    var remainingFiles = dated.length;
    for (final item in dated) {
      if (remainingFiles <= maxFiles && totalBytes <= maxBytes) break;
      await item.file.delete().catchError((_) => item.file);
      remainingFiles -= 1;
      totalBytes -= item.bytes;
    }
  }

  Future<bool> _matchesChecksum(File file, String checksum) async =>
      sha256.convert(await file.readAsBytes()).toString() == checksum;

  String _fnv1a(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
