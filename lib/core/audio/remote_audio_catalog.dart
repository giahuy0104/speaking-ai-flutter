import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'catalog/audio_pack_cache.dart';

/// Asset paths remain stable logical IDs (including loudness metadata), but
/// their original bytes live on Cloudinary rather than in the install bundle.
final class RemoteAudioEntry {
  RemoteAudioEntry({
    required this.asset,
    required this.uri,
    required this.sha256Checksum,
    required this.sizeBytes,
  }) {
    if (!asset.startsWith('assets/audio/') ||
        asset.contains('..') ||
        !uri.isScheme('https') ||
        uri.host != 'res.cloudinary.com' ||
        uri.userInfo.isNotEmpty ||
        !uri.path.contains('/video/upload/') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Checksum) ||
        !uri.path.contains(sha256Checksum) ||
        sizeBytes <= 0 ||
        sizeBytes > maximumAudioBytes) {
      throw const FormatException('Invalid remote audio catalog entry.');
    }
  }

  static const maximumAudioBytes = 16 * 1024 * 1024;
  final String asset;
  final Uri uri;
  final String sha256Checksum;
  final int sizeBytes;

  bool verifies(Uint8List bytes) =>
      bytes.length == sizeBytes &&
      sha256.convert(bytes).toString() == sha256Checksum;
}

final class RemoteAudioCatalog {
  RemoteAudioCatalog._(this.entries);

  factory RemoteAudioCatalog.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 || json['assets'] is! Map) {
      throw const FormatException('Invalid remote audio catalog.');
    }
    final entries = <String, RemoteAudioEntry>{};
    for (final entry in (json['assets'] as Map).entries) {
      final data = entry.value as Map;
      final key = entry.key as String;
      entries[key] = RemoteAudioEntry(
        asset: key,
        uri: Uri.parse(data['url'] as String),
        sha256Checksum: data['sha256'] as String,
        sizeBytes: data['sizeBytes'] as int,
      );
    }
    return RemoteAudioCatalog._(Map.unmodifiable(entries));
  }

  static const assetKey = 'assets/data/remote_audio_catalog.json';
  static RemoteAudioCatalog? _shared;
  static Future<RemoteAudioCatalog>? _loading;
  final Map<String, RemoteAudioEntry> entries;

  static Future<RemoteAudioCatalog> load() {
    final loaded = _shared;
    if (loaded != null) return Future.value(loaded);
    return _loading ??= () async {
      try {
        final data = jsonDecode(await rootBundle.loadString(assetKey));
        return _shared = RemoteAudioCatalog.fromJson(
          data as Map<String, dynamic>,
        );
      } finally {
        _loading = null;
      }
    }();
  }

  RemoteAudioEntry? entryFor(Uri uri) {
    if (!uri.isScheme('asset')) return null;
    return entries[uri.path.replaceFirst(RegExp(r'^/'), '')];
  }

  static Future<RemoteAudioEntry?> entryForUri(Uri uri) async {
    if (!uri.isScheme('asset') ||
        !uri.path.replaceFirst(RegExp(r'^/'), '').startsWith('assets/audio/')) {
      return null;
    }
    return (await load()).entryFor(uri);
  }

  // main() loads the small JSON before runApp. Synchronous resolution preserves
  // Safari's user-gesture activation when HTMLMediaElement.play() is invoked.
  static Uri resolveLoadedUri(Uri uri) => _shared?.entryFor(uri)?.uri ?? uri;
}

/// Persistent checksum cache for legacy fixed prompts such as GAP66. Registry
/// prompts use the same content-addressed on-disk cache through their repository.
final class RemoteAudioStore {
  RemoteAudioStore({AudioPackCache? cache})
    : cache = cache ?? createAudioPackCache();

  static final shared = RemoteAudioStore();
  static const maximumCacheBytes = 128 * 1024 * 1024;
  final AudioPackCache cache;
  final Map<String, Future<Uint8List>> _pending = {};
  Future<void> _writes = Future.value();

  Future<Uint8List> read(RemoteAudioEntry entry, http.Client client) {
    final key = entry.uri.toString();
    return _pending.putIfAbsent(key, () async {
      try {
        return await _read(entry, client);
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<Uint8List> _read(RemoteAudioEntry entry, http.Client client) async {
    try {
      final bytes = await cache.readVerified(
        pack: 'remote-audio',
        sha256: entry.sha256Checksum,
        maximumBytes: RemoteAudioEntry.maximumAudioBytes,
      );
      if (bytes != null && entry.verifies(bytes)) return bytes;
    } catch (_) {
      // Cache storage can be unavailable; verified network playback still works.
    }
    final response = await client
        .get(entry.uri)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200 || !entry.verifies(response.bodyBytes)) {
      throw const FormatException('Remote audio delivery integrity failed.');
    }
    final bytes = response.bodyBytes;
    final write = _writes.catchError((_) {}).then((_) async {
      await cache.putVerified(
        pack: 'remote-audio',
        sha256: entry.sha256Checksum,
        bytes: bytes,
        maximumBytes: RemoteAudioEntry.maximumAudioBytes,
      );
      await cache.pruneObjects(
        protectedChecksums: const {},
        maximumBytes: maximumCacheBytes,
      );
    });
    _writes = write;
    try {
      await write;
    } catch (_) {
      // A full disk must not discard already verified audio.
    }
    return bytes;
  }
}
