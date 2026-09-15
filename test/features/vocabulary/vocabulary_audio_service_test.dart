import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_audio_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_dictionary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  @override
  int get maxFiles => 256;

  @override
  Future<Uri?> cache(Uri remoteUri) async {
    requested.add(remoteUri);
    return result;
  }

  @override
  void dispose() {}

  @override
  Future<Uri> resolve(Uri remoteUri) async => result ?? remoteUri;

  @override
  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async => result ?? remoteUri;

  @override
  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {}
}
