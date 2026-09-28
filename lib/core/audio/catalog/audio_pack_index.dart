import 'audio_pack_manifest.dart';
import 'audio_prompt_key.dart';

final class IndexedAudioPrompt {
  const IndexedAudioPrompt({required this.pack, required this.prompt});

  final AudioPackManifest pack;
  final AudioPackPrompt prompt;
}

final class AudioPackIndex {
  AudioPackIndex([Iterable<AudioPackManifest> manifests = const []]) {
    for (final manifest in manifests) {
      replaceManifest(manifest);
    }
  }

  AudioPackIndex.copy(AudioPackIndex other)
    : _manifests = Map<String, AudioPackManifest>.of(other._manifests) {
    _rebuild();
  }

  Map<String, AudioPackManifest> _manifests = {};
  final Map<String, IndexedAudioPrompt> _prompts = {};

  Iterable<AudioPackManifest> get manifests => _manifests.values;

  AudioPackManifest? manifest(String pack) => _manifests[pack];

  IndexedAudioPrompt? find(AudioPromptKey key, String locale) =>
      _prompts[_identity(key, _canonicalLocale(locale))];

  /// Returns an authored prompt only when text and locale identify exactly one
  /// manifest entry. Ambiguous text must never select an arbitrary recording.
  IndexedAudioPrompt? findByTextHash(String textHash, String locale) {
    final canonicalLocale = _canonicalLocale(locale);
    IndexedAudioPrompt? match;
    for (final candidate in _prompts.values) {
      final prompt = candidate.prompt;
      if (prompt.textHash != textHash ||
          _canonicalLocale(prompt.locale) != canonicalLocale) {
        continue;
      }
      if (match != null) return null;
      match = candidate;
    }
    return match;
  }

  void replaceManifest(AudioPackManifest manifest) {
    final next = Map<String, AudioPackManifest>.of(_manifests)
      ..[manifest.pack] = manifest;
    final identities = <String>{};
    for (final candidate in next.values.where((item) => item.enabled)) {
      for (final prompt in candidate.prompts.where((item) => item.enabled)) {
        final identity = _identity(prompt.key, prompt.locale);
        if (!identities.add(identity)) {
          throw FormatException(
            'Ambiguous audio key ${prompt.key} (${prompt.locale}).',
          );
        }
      }
    }
    _manifests = next;
    _rebuild();
  }

  void removeManifest(String pack) {
    _manifests.remove(pack);
    _rebuild();
  }

  void _rebuild() {
    _prompts.clear();
    for (final manifest in _manifests.values.where((item) => item.enabled)) {
      for (final prompt in manifest.prompts.where((item) => item.enabled)) {
        _prompts[_identity(prompt.key, prompt.locale)] = IndexedAudioPrompt(
          pack: manifest,
          prompt: prompt,
        );
      }
    }
  }

  static String _identity(AudioPromptKey key, String locale) =>
      '${key.value}\u0000${_canonicalLocale(locale)}';

  static String _canonicalLocale(String locale) {
    final normalized = locale.trim().replaceAll('_', '-').toLowerCase();
    return switch (normalized) {
      'vi' || 'vi-vn' => 'vi-VN',
      'en' || 'en-us' => 'en-US',
      _ => locale.trim().replaceAll('_', '-'),
    };
  }
}
