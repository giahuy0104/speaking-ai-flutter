import 'package:flutter/foundation.dart';

import 'audio_prompt_key.dart';

@immutable
final class AudioPackPrompt {
  AudioPackPrompt({
    required this.key,
    required this.locale,
    required this.sha256,
    required this.durationSeconds,
    this.asset,
    this.remoteUri,
    this.sizeBytes,
    this.textHash,
    this.enabled = true,
  }) {
    if (!_shaPattern.hasMatch(sha256)) {
      throw const FormatException('Invalid audio SHA-256.');
    }
    if (!durationSeconds.isFinite || durationSeconds <= 0) {
      throw const FormatException('Invalid audio duration.');
    }
    if (sizeBytes != null && sizeBytes! <= 0) {
      throw const FormatException('Invalid audio size.');
    }
    if (textHash != null && !_shaPattern.hasMatch(textHash!)) {
      throw const FormatException('Invalid source text SHA-256.');
    }
    if (asset != null &&
        (!asset!.startsWith('assets/audio/') ||
            asset!.contains('..') ||
            !asset!.toLowerCase().endsWith('.mp3'))) {
      throw const FormatException('Invalid bundled audio path.');
    }
    if (remoteUri != null && !remoteUri!.isScheme('https')) {
      throw const FormatException('Remote audio must use HTTPS.');
    }
  }

  factory AudioPackPrompt.fromJson(Map<String, dynamic> json) {
    final remoteValue = json['url'];
    final assetValue = json['asset'];
    return AudioPackPrompt(
      key: AudioPromptKey(json['key'] as String? ?? ''),
      locale: (json['locale'] as String? ?? '').trim(),
      sha256: (json['sha256'] as String? ?? '').trim().toLowerCase(),
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0,
      asset: assetValue is String && assetValue.trim().isNotEmpty
          ? assetValue.trim()
          : null,
      remoteUri: remoteValue is String && remoteValue.trim().isNotEmpty
          ? Uri.tryParse(remoteValue.trim())
          : null,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      textHash: (json['textHash'] as String?)?.trim().toLowerCase(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static final RegExp _shaPattern = RegExp(r'^[a-f0-9]{64}$');

  final AudioPromptKey key;
  final String locale;
  final String sha256;
  final double durationSeconds;
  final String? asset;
  final Uri? remoteUri;
  final int? sizeBytes;
  final String? textHash;
  final bool enabled;
}

@immutable
final class AudioPackManifest {
  AudioPackManifest({
    required this.pack,
    required this.version,
    required List<AudioPackPrompt> prompts,
    this.minimumAppVersion = '0.0.0',
    this.enabled = true,
  }) : prompts = List.unmodifiable(prompts) {
    if (!_identifier.hasMatch(pack) || !_identifier.hasMatch(version)) {
      throw const FormatException('Invalid audio pack identity.');
    }
    if (!_semanticVersion.hasMatch(minimumAppVersion)) {
      throw const FormatException('Invalid minimum app version.');
    }
    final identities = <String>{};
    for (final prompt in prompts) {
      if (!identities.add('${prompt.key.value}\u0000${prompt.locale}')) {
        throw FormatException('Duplicate audio key in $pack: ${prompt.key}');
      }
    }
  }

  factory AudioPackManifest.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported audio manifest schema.');
    }
    return AudioPackManifest(
      pack: (json['pack'] as String? ?? '').trim(),
      version: (json['version'] as String? ?? 'bundled').trim(),
      enabled: json['enabled'] as bool? ?? true,
      minimumAppVersion: (json['minimumAppVersion'] as String? ?? '0.0.0')
          .trim(),
      prompts: (json['prompts'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(AudioPackPrompt.fromJson)
          .toList(growable: false),
    );
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static final RegExp _semanticVersion = RegExp(r'^\d+\.\d+\.\d+$');

  final String pack;
  final String version;
  final bool enabled;
  final String minimumAppVersion;
  final List<AudioPackPrompt> prompts;
}
