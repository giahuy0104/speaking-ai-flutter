import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final result in <Uri?>[null, Uri.file('/cache/late.mp3')]) {
    test(
      'Back cancels delayed cache result $result without late playback or TTS',
      () async {
        final cache = _DelayedAudioCache();
        final played = <Uri>[];
        final spoken = <String>[];
        final service = VocabularyAudioService(
          dictionaryProvider: _FakeDictionaryProvider(),
          cache: cache,
          playToCompletion: (uri) async => played.add(uri),
          nativeSpeakAndWait: (text, locale) async => spoken.add(text),
          stopPlayback: () async {},
        );
        final pending = service.speakAndWait('Apple', locale: 'en-US');
        await service.stop();
        cache.pending.complete(result);
        await pending;
        expect(played, isEmpty);
        expect(spoken, isEmpty);
      },
    );
  }
  test('prefetch caches dynamic audio without playing or speaking', () async {
    final cache = _FakeAudioCache(Uri.file('/cache/mad.mp3'));
    final played = <Uri>[];
    final native = <String>[];
    final service = VocabularyAudioService(
      dictionaryProvider: _FakeDictionaryProvider(),
      cache: cache,
      playToCompletion: (uri) async => played.add(uri),
      nativeSpeakAndWait: (text, locale) async => native.add('$locale:$text'),
      stopPlayback: () async {},
    );

    await service.prefetch('Mad', locale: 'en-US');

    expect(cache.requested.single.queryParameters, <String, String>{
      'word': 'Mad',
      'lang': 'en-US',
      'audioKey': VocabularyAudioKeys.dynamic(
        text: 'Mad',
        locale: 'en-US',
        voiceProfile: 'Nhs7eitvQWFTQBsf0yiT@eleven_v3@0.75',
      ),
      'voiceId': 'Nhs7eitvQWFTQBsf0yiT',
      'modelId': 'eleven_v3',
      'speed': '0.75',
    });
    expect(played, isEmpty);
    expect(native, isEmpty);
  });

  test('plays cached minhqnd audio without invoking native TTS', () async {
    final played = <Uri>[];
    final native = <String>[];
    final service = VocabularyAudioService(
      dictionaryProvider: _FakeDictionaryProvider(),
      cache: _FakeAudioCache(Uri.file('/cache/dog.mp3')),
      playToCompletion: (uri) async => played.add(uri),
      nativeSpeakAndWait: (text, locale) async => native.add('$locale:$text'),
      stopPlayback: () async {},
    );

    final source = await service.speakAndWait('Dog', locale: 'en-US');

    expect(source, VocabularyAudioSource.minhqndCache);
    expect(played.single.path, endsWith('dog.mp3'));
    expect(native, isEmpty);
  });

  test('falls back to native TTS when cloud audio cannot be cached', () async {
    final native = <String>[];
    final service = VocabularyAudioService(
      dictionaryProvider: _FakeDictionaryProvider(),
      cache: _FakeAudioCache(null),
      playToCompletion: (_) async {},
      nativeSpeakAndWait: (text, locale) async => native.add('$locale:$text'),
      stopPlayback: () async {},
    );

    final source = await service.speakAndWait(
      'Con thích táo đỏ.',
      locale: 'vi-VN',
    );

    expect(source, VocabularyAudioSource.nativeTts);
    expect(native, <String>['vi-VN:Con thích táo đỏ.']);
  });

  test(
    'dynamic key is normalized and deleted entries can evict cache',
    () async {
      final cache = _FakeAudioCache(Uri.file('/cache/apple.mp3'));
      final service = VocabularyAudioService(
        dictionaryProvider: _FakeDictionaryProvider(),
        cache: cache,
        playToCompletion: (_) async {},
        nativeSpeakAndWait: (_, _) async {},
        stopPlayback: () async {},
      );

      await service.prefetch('  Apple   pie ', locale: 'en-US');
      await service.prefetch('apple pie', locale: 'en-US');
      expect(
        cache.requested[0].queryParameters['audioKey'],
        cache.requested[1].queryParameters['audioKey'],
      );

      await service.release('Apple pie', locale: 'en-US');
      expect(cache.evicted.single.queryParameters['audioKey'], isNotEmpty);
    },
  );
}

class _FakeDictionaryProvider implements VocabularyDictionaryProvider {
  @override
  Future<VocabularyDictionaryResult?> lookupEnglish(String text) async => null;

  @override
  Uri ttsUri(String text, {required String locale}) => Uri.https(
    'dict.minhqnd.com',
    '/api/v1/tts',
    <String, String>{'word': text, 'lang': locale},
  );

  @override
  void dispose() {}
}

class _FakeAudioCache implements DeviceAudioCache {
  _FakeAudioCache(this.result);

  final Uri? result;
  final List<Uri> requested = <Uri>[];
  final List<Uri> evicted = <Uri>[];

  @override
  int get maxFiles => 256;

  @override
  int get maxBytes => 64 * 1024 * 1024;

  @override
  Future<Uri?> cache(Uri remoteUri) async {
    requested.add(remoteUri);
    return result;
  }

  @override
  Future<Uri?> cacheVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    int maximumFileBytes = 2 * 1024 * 1024,
  }) => cache(remoteUri);

  @override
  void dispose() {}

  @override
  Future<Uri> resolve(Uri remoteUri) async => result ?? remoteUri;

  @override
  Future<Uri> resolveVerified(
    Uri remoteUri, {
    required String sha256Checksum,
  }) => resolve(remoteUri);

  @override
  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async => result ?? remoteUri;

  @override
  Future<Uri> resolveAfterPreloadVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    Duration maxWait = const Duration(milliseconds: 500),
  }) => resolveAfterPreload(remoteUri, maxWait: maxWait);

  @override
  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {}

  @override
  Future<void> evict(Uri remoteUri) async => evicted.add(remoteUri);
}

class _DelayedAudioCache extends _FakeAudioCache {
  _DelayedAudioCache() : super(null);
  final pending = Completer<Uri?>();
  @override
  Future<Uri?> cache(Uri remoteUri) => pending.future;
}
