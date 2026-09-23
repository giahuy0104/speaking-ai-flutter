import '../../../core/audio/device_audio_cache.dart';
import '../domain/vocabulary_audio_keys.dart';
import '../domain/vocabulary_dictionary.dart';

enum VocabularyAudioSource { minhqndCache, nativeTts }

typedef VocabularyAudioPlayer = Future<void> Function(Uri uri);
typedef VocabularyNativeSpeaker =
    Future<void> Function(String text, String locale);
typedef VocabularyAudioStopper = Future<void> Function();

abstract interface class VocabularyContentAudioService {
  /// Downloads dynamic audio into the local cache without playing it. A
  /// failure is intentionally silent because playback still has native TTS
  /// as its zero-cost fallback.
  Future<void> prefetch(String text, {required String locale});

  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  });

  Future<void> stop();

  void dispose();
}

abstract interface class VocabularyAudioCacheMaintenance {
  Future<void> release(String text, {required String locale});
}

/// Resolves dynamic parent-authored text to free minhqnd audio, stores the MP3
/// in the app support cache, and falls back to the platform TTS voice whenever
/// the network, service, cache, or playback is unavailable.
class VocabularyAudioService
    implements VocabularyContentAudioService, VocabularyAudioCacheMaintenance {
  VocabularyAudioService({
    required this.dictionaryProvider,
    required this.playToCompletion,
    required this.nativeSpeakAndWait,
    required this.stopPlayback,
    DeviceAudioCache? cache,
    this.cloudWait = const Duration(seconds: 3),
  }) : _cache = cache ?? DeviceAudioCache(),
       _ownsCache = cache == null;

  final VocabularyDictionaryProvider dictionaryProvider;
  final VocabularyAudioPlayer playToCompletion;
  final VocabularyNativeSpeaker nativeSpeakAndWait;
  final VocabularyAudioStopper stopPlayback;
  final Duration cloudWait;
  final DeviceAudioCache _cache;
  final bool _ownsCache;
  int _generation = 0;
  bool _disposed = false;

  @override
  Future<void> prefetch(String text, {required String locale}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    try {
      final remote = _dynamicUri(normalized, locale);
      await _cache.cache(remote).timeout(cloudWait, onTimeout: () => null);
    } catch (_) {
      // Prefetch must never block saving parent-authored content. Playback
      // retries the cache and falls back to native TTS if the service is down.
    }
  }

  @override
  Future<VocabularyAudioSource> speakAndWait(
    String text, {
    required String locale,
  }) async {
    final generation = _generation;
    if (_disposed) return VocabularyAudioSource.nativeTts;
    final normalized = text.trim();
    if (normalized.isEmpty) return VocabularyAudioSource.nativeTts;
    try {
      final remote = _dynamicUri(normalized, locale);
      final cached = await _cache
          .cache(remote)
          .timeout(cloudWait, onTimeout: () => null);
      if (_disposed || generation != _generation) {
        return VocabularyAudioSource.nativeTts;
      }
      if (cached != null) {
        await playToCompletion(cached);
        return VocabularyAudioSource.minhqndCache;
      }
    } catch (_) {
      // The native voice is deliberately the last-resort, zero-cost path.
    }
    if (_disposed || generation != _generation) {
      return VocabularyAudioSource.nativeTts;
    }
    await nativeSpeakAndWait(normalized, locale);
    return VocabularyAudioSource.nativeTts;
  }

  @override
  Future<void> stop() {
    _generation++;
    return stopPlayback();
  }

  @override
  Future<void> release(String text, {required String locale}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    await _cache.evict(_dynamicUri(normalized, locale));
  }

  Uri _dynamicUri(String text, String locale) {
    final isEnglish = locale.toLowerCase().startsWith('en');
    final voiceId = isEnglish ? 'Nhs7eitvQWFTQBsf0yiT' : '5CVDNcIPiOYgRUQuxXd7';
    final speed = isEnglish ? '0.75' : '0.9';
    final voiceProfile = '$voiceId@eleven_v3@$speed';
    final audioKey = VocabularyAudioKeys.dynamic(
      text: text,
      locale: locale,
      voiceProfile: voiceProfile,
    );
    final uri = dictionaryProvider.ttsUri(text, locale: locale);
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'audioKey': audioKey,
        'voiceId': voiceId,
        'modelId': 'eleven_v3',
        'speed': speed,
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_ownsCache) _cache.dispose();
  }
}
