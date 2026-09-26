import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../audio_diagnostics.dart';
import 'audio_pack_manifest.dart';
import 'audio_pack_repository.dart';
import 'audio_prompt_request.dart';

enum AudioPromptSource { deviceCache, bundledAsset, remote, tts, unavailable }

final class AudioPromptResolution {
  const AudioPromptResolution({required this.source, this.bytes, this.prompt});

  final AudioPromptSource source;
  final Uint8List? bytes;
  final AudioPackPrompt? prompt;
}

final class AudioPromptResolver {
  AudioPromptResolver({required this.repository});

  final AudioPackRepository repository;

  Future<AudioPromptResolution> resolve(AudioPromptRequest request) async {
    var indexed = await repository.find(request.key, request.locale);
    if (indexed == null && _isUnkeyed(request)) {
      indexed = await repository.findByText(
        request.fallbackText,
        request.locale,
      );
      if (indexed != null) {
        AudioDiagnostics.event('registry.resolve.text_match', {
          'key': indexed.prompt.key.value,
          'locale': request.locale,
        });
      }
    }
    if (indexed == null) {
      return _fallback(request, reason: 'key_or_locale_missing');
    }
    if (!_isUnkeyed(request) && !_matchesRuntimeText(indexed.prompt, request)) {
      return _fallback(
        request,
        prompt: indexed.prompt,
        reason: 'text_hash_mismatch',
      );
    }
    if (!_withinLimits(indexed.prompt)) {
      return _fallback(
        request,
        prompt: indexed.prompt,
        reason: 'manifest_limits',
      );
    }
    final prompt = indexed.prompt;
    try {
      final cached = await repository.cache.readVerified(
        pack: indexed.pack.pack,
        sha256: prompt.sha256,
        maximumBytes: repository.maximumAudioBytes,
      );
      if (cached != null) {
        return AudioPromptResolution(
          source: AudioPromptSource.deviceCache,
          bytes: cached,
          prompt: prompt,
        );
      }
    } catch (error) {
      _diagnoseFailure(request, 'cache', error);
    }

    if (prompt.asset != null) {
      try {
        final data = await repository.bundle.load(prompt.asset!);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (_verified(bytes, prompt)) {
          return AudioPromptResolution(
            source: AudioPromptSource.bundledAsset,
            bytes: bytes,
            prompt: prompt,
          );
        }
      } catch (error) {
        _diagnoseFailure(request, 'bundle', error);
      }
    }

    if (prompt.remoteUri != null) {
      try {
        final bytes = await repository.downloadPrompt(prompt);
        await repository.cache.putVerified(
          pack: indexed.pack.pack,
          sha256: prompt.sha256,
          bytes: bytes,
          maximumBytes: repository.maximumAudioBytes,
        );
        return AudioPromptResolution(
          source: AudioPromptSource.remote,
          bytes: bytes,
          prompt: prompt,
        );
      } catch (error) {
        _diagnoseFailure(request, 'remote', error);
      }
    }
    return _fallback(request, prompt: prompt, reason: 'audio_unavailable');
  }

  Future<Duration?> budget(AudioPromptRequest request) async {
    if (_isUnkeyed(request)) {
      return repository.budgetByText(request.fallbackText, request.locale);
    }
    final indexed = await repository.find(request.key, request.locale);
    if (indexed == null || !_matchesRuntimeText(indexed.prompt, request)) {
      return null;
    }
    return repository.budget(request.key, request.locale);
  }

  static bool _isUnkeyed(AudioPromptRequest request) =>
      request.key.value == 'runtime.tts.unkeyed';

  bool _withinLimits(AudioPackPrompt prompt) =>
      prompt.durationSeconds <= 45 &&
      (prompt.sizeBytes == null ||
          prompt.sizeBytes! <= repository.maximumAudioBytes);

  bool _matchesRuntimeText(AudioPackPrompt prompt, AudioPromptRequest request) {
    final sourceText = prompt.sourceText;
    if (sourceText == null || sourceText.isEmpty) return true;
    final normalized = request.fallbackText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sha256.convert(utf8.encode(normalized)).toString() ==
        prompt.textHash;
  }

  bool _verified(Uint8List bytes, AudioPackPrompt prompt) =>
      bytes.isNotEmpty &&
      bytes.length <= repository.maximumAudioBytes &&
      (prompt.sizeBytes == null || bytes.length == prompt.sizeBytes) &&
      sha256.convert(bytes).toString() == prompt.sha256;

  AudioPromptResolution _fallback(
    AudioPromptRequest request, {
    AudioPackPrompt? prompt,
    required String reason,
  }) {
    final source = request.allowTtsFallback
        ? AudioPromptSource.tts
        : AudioPromptSource.unavailable;
    AudioDiagnostics.event('registry.resolve.fallback', {
      'key': request.key.value,
      'locale': request.locale,
      'reason': reason,
      'source': source.name,
    });
    return AudioPromptResolution(source: source, prompt: prompt);
  }

  void _diagnoseFailure(
    AudioPromptRequest request,
    String stage,
    Object error,
  ) {
    AudioDiagnostics.event('registry.resolve.failure', {
      'key': request.key.value,
      'locale': request.locale,
      'stage': stage,
      'reason': error.runtimeType.toString(),
    });
  }
}
