import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

enum LessonGuideCue {
  record('GUIDE_RECORD'),
  praise('GUIDE_PRAISE'),
  next('GUIDE_NEXT'),
  idleFirst('GUIDE_IDLE1'),
  idleSecond('GUIDE_IDLE2'),
  skip('GUIDE_SKIP'),
  ending('GUIDE_ENDING');

  const LessonGuideCue(this.directoryName);

  final String directoryName;
}

class LessonGuideAudioLibrary {
  LessonGuideAudioLibrary({
    AssetBundle? bundle,
    Random? random,
    List<String>? assetPaths,
  }) : _bundle = bundle ?? rootBundle,
       _random = random ?? Random(),
       _providedAssetPaths = assetPaths == null
           ? null
           : List<String>.unmodifiable(assetPaths);

  static const Set<String> _supportedExtensions = <String>{
    '.aac',
    '.m4a',
    '.mp3',
    '.ogg',
    '.wav',
  };

  final AssetBundle _bundle;
  final Random _random;
  final List<String>? _providedAssetPaths;
  Future<List<String>>? _assetPathsFuture;
  Future<Map<String, Uri>>? _remoteUrisFuture;

  Future<Uri?> randomUri(
    LessonGuideCue cue, {
    required int startAge,
    required int endAge,
  }) async {
    final assets = await (_assetPathsFuture ??= _loadAssetPaths());
    final assetPrefix =
        'assets/audio/A-$startAge-$endAge/${cue.directoryName}/';
    final candidates = assets
        .where((asset) => asset.startsWith(assetPrefix))
        .where(_isSupportedAudio)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    final selected = candidates[_random.nextInt(candidates.length)];
    return _uriForAssetPath(selected);
  }

  /// Resolves a V2 guide by its stable audio code, regardless of the folder in
  /// which the generated audio pack is mounted. This lets IT add the 410-file
  /// pack without changing the lesson state machine or renaming legacy guides.
  Future<Uri?> uriForAudioCode(String audioCode) async {
    final normalizedCode = audioCode.trim().toLowerCase();
    if (normalizedCode.isEmpty) {
      return null;
    }
    final assets = await (_assetPathsFuture ??= _loadAssetPaths());
    for (final asset in assets) {
      if (!_isSupportedAudio(asset)) {
        continue;
      }
      final filename = asset.split('/').last;
      final extensionIndex = filename.lastIndexOf('.');
      final basename =
          (extensionIndex < 0
                  ? filename
                  : filename.substring(0, extensionIndex))
              .toLowerCase();
      if (basename == normalizedCode) {
        return _uriForAssetPath(asset);
      }
    }
    return null;
  }

  Future<List<String>> _loadAssetPaths() async {
    final provided = _providedAssetPaths;
    if (provided != null) {
      return provided.map(_normalizePath).toList(growable: false)..sort();
    }
    final remoteUris = await (_remoteUrisFuture ??= _loadRemoteUris());
    return remoteUris.keys.toList(growable: false)..sort();
  }

  Future<Uri?> _uriForAssetPath(String assetPath) async {
    if (_providedAssetPaths != null) {
      return Uri(scheme: 'asset', path: '/$assetPath');
    }
    final remoteUris = await (_remoteUrisFuture ??= _loadRemoteUris());
    return remoteUris[assetPath];
  }

  Future<Map<String, Uri>> _loadRemoteUris() async {
    final decoded = jsonDecode(
      await _bundle.loadString('assets/data/cloudinary_audio_manifest.json'),
    );
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported Cloudinary audio manifest.');
    }
    final rawAssets = decoded['assets'];
    if (rawAssets is! Map) {
      throw const FormatException('Cloudinary audio manifest has no assets.');
    }
    final result = <String, Uri>{};
    for (final entry in rawAssets.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! Map) continue;
      final secureUrl = value['secureUrl'];
      final uri = secureUrl is String ? Uri.tryParse(secureUrl) : null;
      if (uri == null ||
          !uri.isScheme('https') ||
          uri.host != 'res.cloudinary.com') {
        continue;
      }
      result[_normalizePath(entry.key as String)] = uri;
    }
    return result;
  }

  static bool _isSupportedAudio(String assetPath) {
    final normalized = assetPath.toLowerCase();
    return _supportedExtensions.any(normalized.endsWith);
  }

  static String _normalizePath(String value) => value.replaceAll(r'\', '/');
}
