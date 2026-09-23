import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../audio_diagnostics.dart';
import 'audio_pack_cache.dart';
import 'audio_pack_index.dart';
import 'audio_pack_manifest.dart';
import 'audio_prompt_key.dart';

typedef AudioPackTelemetry =
    void Function(String event, Map<String, Object?> metadata);

final class AudioPackRepository {
  AudioPackRepository({
    required List<String> bundledManifestAssets,
    AssetBundle? bundle,
    AudioPackCache? cache,
    http.Client? httpClient,
    Set<String> allowedCdnHosts = const {'res.cloudinary.com'},
    this.maximumAudioBytes = 2 * 1024 * 1024,
    this.maximumManifestBytes = 1024 * 1024,
    this.maximumCacheBytes = 128 * 1024 * 1024,
    this.currentAppVersion = '1.0.8',
    this.telemetry,
  }) : bundledManifestAssets = List.unmodifiable(bundledManifestAssets),
       bundle = bundle ?? rootBundle,
       cache = cache ?? createAudioPackCache(),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       allowedCdnHosts = Set.unmodifiable(
         allowedCdnHosts.map((host) => host.trim().toLowerCase()),
       );

  final List<String> bundledManifestAssets;
  final AssetBundle bundle;
  final AudioPackCache cache;
  final Set<String> allowedCdnHosts;
  final int maximumAudioBytes;
  final int maximumManifestBytes;
  final int maximumCacheBytes;
  final String currentAppVersion;
  final AudioPackTelemetry? telemetry;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  AudioPackIndex _index = AudioPackIndex();
  Future<void>? _loading;
  final Map<String, AudioPackManifest?> _rollbackManifests = {};
  final Map<String, Future<Uint8List>> _downloads = {};

  Future<void> ensureLoaded() => _loading ??= _loadBundledManifests();

  Future<List<AudioPackManifest>> activeManifests() async {
    await ensureLoaded();
    return List.unmodifiable(_index.manifests);
  }

  Future<IndexedAudioPrompt?> find(AudioPromptKey key, String locale) async {
    await ensureLoaded();
    return _index.find(key, locale);
  }

  Future<IndexedAudioPrompt?> findByText(String text, String locale) async {
    await ensureLoaded();
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    final textHash = sha256.convert(utf8.encode(normalized)).toString();
    return _index.findByTextHash(textHash, locale);
  }

  Future<Duration?> budget(AudioPromptKey key, String locale) async {
    final indexed = await find(key, locale);
    return _budgetFor(indexed);
  }

  Future<Duration?> budgetByText(String text, String locale) async {
    final indexed = await findByText(text, locale);
    return _budgetFor(indexed);
  }

  Duration? _budgetFor(IndexedAudioPrompt? indexed) {
    if (indexed == null) return null;
    // Challenge watchdogs start before route acquisition, asset verification,
    // MediaPlayer preparation and the first decoded frame. A raw file duration
    // therefore expires before the tail of a valid clip on real phones.
    return Duration(
      milliseconds:
          (indexed.prompt.durationSeconds * 1000).ceil() +
          const Duration(seconds: 10).inMilliseconds,
    );
  }

  bool isAllowedRemote(Uri uri) {
    if (!uri.isScheme('https') || uri.userInfo.isNotEmpty) return false;
    return allowedCdnHosts.contains(uri.host.toLowerCase());
  }

  Future<Uint8List> downloadPrompt(AudioPackPrompt prompt) {
    final existing = _downloads[prompt.sha256];
    if (existing != null) return existing;
    final future = _downloadPrompt(prompt);
    _downloads[prompt.sha256] = future;
    return future.whenComplete(() => _downloads.remove(prompt.sha256));
  }

  Future<void> installRemoteManifest(Uri uri) async {
    if (!isAllowedRemote(uri)) {
      throw const FormatException('Audio manifest URL is not allowed.');
    }
    final response = await _httpClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Audio manifest download failed (${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length > maximumManifestBytes) {
      throw const FormatException('Audio manifest is too large.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Audio manifest root must be an object.');
    }
    await installManifest(AudioPackManifest.fromJson(decoded));
  }

  Future<void> installManifest(AudioPackManifest manifest) async {
    await ensureLoaded();
    if (_compareVersions(currentAppVersion, manifest.minimumAppVersion) < 0) {
      throw StateError('Audio pack requires a newer app version.');
    }
    final activePrompts = manifest.prompts.where((prompt) => prompt.enabled);
    for (final prompt in activePrompts) {
      if (prompt.remoteUri == null || !isAllowedRemote(prompt.remoteUri!)) {
        throw const FormatException('Audio pack contains a disallowed URL.');
      }
      if (!_isImmutableRemote(prompt)) {
        throw const FormatException('Audio URL is not content-addressed.');
      }
      if (prompt.durationSeconds > 45) {
        throw const FormatException('Audio prompt exceeds duration limit.');
      }
      if (prompt.sizeBytes != null && prompt.sizeBytes! > maximumAudioBytes) {
        throw const FormatException('Audio prompt exceeds size limit.');
      }
    }

    final nextIndex = AudioPackIndex.copy(_index)..replaceManifest(manifest);
    await cache.beginStaging(manifest.pack, manifest.version);
    try {
      final bytesByChecksum = <String, Future<Uint8List>>{};
      for (final prompt in activePrompts) {
        final bytes = await bytesByChecksum.putIfAbsent(
          prompt.sha256,
          () => downloadPrompt(prompt),
        );
        await cache.stageVerified(
          pack: manifest.pack,
          version: manifest.version,
          sha256: prompt.sha256,
          bytes: bytes,
          maximumBytes: maximumAudioBytes,
        );
      }
      await cache.activateStaged(
        pack: manifest.pack,
        version: manifest.version,
        requiredChecksums: activePrompts.map((item) => item.sha256).toSet(),
      );
      _rollbackManifests[manifest.pack] = _index.manifest(manifest.pack);
      _index = nextIndex;
      final removed = await cache.pruneObjects(
        protectedChecksums: _index.manifests
            .where((item) => item.enabled)
            .expand((item) => item.prompts)
            .where((item) => item.enabled)
            .map((item) => item.sha256)
            .toSet(),
        maximumBytes: maximumCacheBytes,
      );
      telemetry?.call('audio_pack_activated', <String, Object?>{
        'pack': manifest.pack,
        'version': manifest.version,
        'audioCount': activePrompts.length,
        'evictedObjectCount': removed,
      });
    } catch (_) {
      await cache.discardStaging(manifest.pack, manifest.version);
      rethrow;
    }
  }

  Future<int> preloadAgeGroup(String ageGroup) async {
    await ensureLoaded();
    final normalized = ageGroup.trim();
    final manifests = _index.manifests.where(
      (manifest) =>
          manifest.enabled &&
          (manifest.pack.endsWith('-$normalized') ||
              manifest.pack == 'assistant-core' ||
              manifest.pack.endsWith('-common')),
    );
    var downloaded = 0;
    for (final manifest in manifests) {
      for (final prompt in manifest.prompts.where((item) => item.enabled)) {
        if (prompt.remoteUri == null) continue;
        final cached = await cache.readVerified(
          pack: manifest.pack,
          sha256: prompt.sha256,
          maximumBytes: maximumAudioBytes,
        );
        if (cached != null) continue;
        final bytes = await downloadPrompt(prompt);
        await cache.putVerified(
          pack: manifest.pack,
          sha256: prompt.sha256,
          bytes: bytes,
          maximumBytes: maximumAudioBytes,
        );
        downloaded += 1;
      }
    }
    telemetry?.call('audio_pack_preload_completed', <String, Object?>{
      'ageGroup': normalized,
      'downloadedCount': downloaded,
    });
    return downloaded;
  }

  Future<bool> rollback(String pack) async {
    await ensureLoaded();
    if (!_rollbackManifests.containsKey(pack)) return false;
    final previous = _rollbackManifests[pack];
    final cacheRolledBack = await cache.rollback(pack);
    final previousIsBundled =
        previous != null &&
        previous.prompts
            .where((prompt) => prompt.enabled)
            .every((prompt) => prompt.asset != null);
    if (!cacheRolledBack && !previousIsBundled) return false;
    _rollbackManifests.remove(pack);
    final next = AudioPackIndex.copy(_index);
    if (previous == null) {
      next.removeManifest(pack);
    } else {
      next.replaceManifest(previous);
    }
    _index = next;
    return true;
  }

  Future<void> _loadBundledManifests() async {
    final next = AudioPackIndex();
    for (final asset in bundledManifestAssets) {
      try {
        final json = jsonDecode(await bundle.loadString(asset));
        if (json is Map<String, dynamic>) {
          final manifest = AudioPackManifest.fromJson(json);
          if (_compareVersions(currentAppVersion, manifest.minimumAppVersion) >=
              0) {
            next.replaceManifest(manifest);
          }
        }
      } catch (error) {
        // A missing/corrupt optional pack must not disable TTS fallback.
        AudioDiagnostics.event('registry.manifest.failure', {
          'asset': asset,
          'reason': error.runtimeType.toString(),
        });
      }
    }
    _index = next;
  }

  bool _isImmutableRemote(AudioPackPrompt prompt) {
    final uri = prompt.remoteUri!;
    final checksumQuery = uri.queryParameters['sha256'];
    if (checksumQuery?.toLowerCase() == prompt.sha256) return true;
    return uri.path.toLowerCase().contains(prompt.sha256.substring(0, 16));
  }

  static int _compareVersions(String left, String right) {
    List<int> parts(String value) => value
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    final a = parts(left);
    final b = parts(right);
    for (var index = 0; index < 3; index += 1) {
      final result = (index < a.length ? a[index] : 0).compareTo(
        index < b.length ? b[index] : 0,
      );
      if (result != 0) return result;
    }
    return 0;
  }

  Future<Uint8List> _downloadPrompt(AudioPackPrompt prompt) async {
    final uri = prompt.remoteUri;
    if (uri == null || !isAllowedRemote(uri)) {
      throw const FormatException('Audio URL is not allowed.');
    }
    final response = await _httpClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Audio download failed (${response.statusCode}).');
    }
    final bytes = Uint8List.fromList(response.bodyBytes);
    if (bytes.isEmpty || bytes.length > maximumAudioBytes) {
      throw const FormatException('Audio download has an invalid size.');
    }
    if (prompt.sizeBytes != null && bytes.length != prompt.sizeBytes) {
      throw const FormatException(
        'Audio download size does not match manifest.',
      );
    }
    if (sha256.convert(bytes).toString() != prompt.sha256) {
      throw const FormatException('Audio checksum does not match manifest.');
    }
    return bytes;
  }

  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
