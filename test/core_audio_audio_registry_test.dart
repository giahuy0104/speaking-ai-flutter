import 'dart:async';
import 'dart:convert';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_manifest.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_key.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_request.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_resolver.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/voice_prompt_audio_registry_adapter.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'assistant.test.prompt.vi';
  const locale = 'vi-VN';
  final authored = Uint8List.fromList(utf8.encode('valid authored audio'));

  AudioPromptRequest request({bool tts = true}) => AudioPromptRequest(
    key: AudioPromptKey(key),
    fallbackText: 'Xin chào',
    locale: locale,
    allowTtsFallback: tts,
  );

  test('resolves a checksum-verified bundled asset', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);
    final resolution = await fixture.resolver.resolve(request());

    expect(resolution.source, AudioPromptSource.bundledAsset);
    expect(resolution.bytes, authored);
  });

  test(
    'unkeyed fixed text prefers the unique matching authored asset',
    () async {
      final fixture = _Fixture.bundle(
        key: key,
        locale: locale,
        bytes: authored,
        text: 'Xin   chào',
      );
      final resolution = await fixture.resolver.resolve(
        AudioPromptRequest(
          key: AudioPromptKey('runtime.tts.unkeyed'),
          fallbackText: '  Xin chào  ',
          locale: locale,
        ),
      );

      expect(resolution.source, AudioPromptSource.bundledAsset);
      expect(resolution.bytes, authored);
    },
  );

  test('unknown unkeyed text still falls back to TTS', () async {
    final fixture = _Fixture.bundle(
      key: key,
      locale: locale,
      bytes: authored,
      text: 'Xin chào',
    );
    final resolution = await fixture.resolver.resolve(
      AudioPromptRequest(
        key: AudioPromptKey('runtime.tts.unkeyed'),
        fallbackText: 'Nội dung động không có audio',
        locale: locale,
      ),
    );

    expect(resolution.source, AudioPromptSource.tts);
  });

  test('device cache has priority over the bundled asset', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);
    await fixture.cache.putVerified(
      pack: 'test-pack',
      sha256: _checksum(authored),
      bytes: authored,
      maximumBytes: fixture.repository.maximumAudioBytes,
    );

    final resolution = await fixture.resolver.resolve(request());

    expect(resolution.source, AudioPromptSource.deviceCache);
  });

  test('deduplicates simultaneous remote downloads and then caches', () async {
    var downloadCount = 0;
    final fixture = _Fixture.remote(
      key: key,
      locale: locale,
      expectedBytes: authored,
      client: MockClient((_) async {
        downloadCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response.bytes(authored, 200);
      }),
    );

    final results = await Future.wait([
      fixture.resolver.resolve(request()),
      fixture.resolver.resolve(request()),
    ]);
    final cached = await fixture.resolver.resolve(request());

    expect(downloadCount, 1);
    expect(
      results.map((item) => item.source),
      everyElement(AudioPromptSource.remote),
    );
    expect(cached.source, AudioPromptSource.deviceCache);
  });

  test('bad remote checksum falls back to TTS', () async {
    final fixture = _Fixture.remote(
      key: key,
      locale: locale,
      expectedBytes: authored,
      client: MockClient(
        (_) async => http.Response.bytes(utf8.encode('tampered'), 200),
      ),
    );

    expect(
      (await fixture.resolver.resolve(request())).source,
      AudioPromptSource.tts,
    );
  });

  test('missing manifest and missing key both fall back to TTS', () async {
    final repository = AudioPackRepository(
      bundledManifestAssets: const ['missing.json'],
      bundle: _MemoryAssetBundle(const {}),
      cache: MemoryAudioPackCache(),
    );
    final resolver = AudioPromptResolver(repository: repository);

    expect((await resolver.resolve(request())).source, AudioPromptSource.tts);
    expect(
      (await resolver.resolve(request(tts: false))).source,
      AudioPromptSource.unavailable,
    );
  });

  test('authored decode/autoplay failure uses TTS fallback', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);
    var ttsCount = 0;
    final service = AudioPromptService(
      resolver: fixture.resolver,
      playAuthored: (_, _) async => throw StateError('autoplay denied'),
      playTts: (_) async => ttsCount += 1,
      stopPlayback: () async {},
    );

    expect(await service.play(request()), AudioPromptSource.tts);
    expect(ttsCount, 1);
  });

  test('HFP route loss is fail-closed and never falls back to TTS', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);
    var ttsCount = 0;
    final service = AudioPromptService(
      resolver: fixture.resolver,
      playAuthored: (_, _) async => throw const HfpAudioException('route lost'),
      playTts: (_) async => ttsCount += 1,
      stopPlayback: () async {},
      isRouteLoss: (error) => error is HfpAudioException,
    );

    await expectLater(
      service.play(request()),
      throwsA(isA<HfpAudioException>()),
    );
    expect(ttsCount, 0);
  });

  test('stop invalidates an in-flight resolution before playback', () async {
    final response = Completer<http.Response>();
    final fixture = _Fixture.remote(
      key: key,
      locale: locale,
      expectedBytes: authored,
      client: MockClient((_) => response.future),
    );
    var authoredCount = 0;
    var ttsCount = 0;
    var stopCount = 0;
    final service = AudioPromptService(
      resolver: fixture.resolver,
      playAuthored: (_, _) async => authoredCount += 1,
      playTts: (_) async => ttsCount += 1,
      stopPlayback: () async => stopCount += 1,
    );

    final play = service.play(request());
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    response.complete(http.Response.bytes(authored, 200));

    expect(await play, AudioPromptSource.unavailable);
    expect(authoredCount, 0);
    expect(ttsCount, 0);
    expect(stopCount, 1);
  });

  test(
    'concurrent authored prompts are played serially to completion',
    () async {
      final fixture = _Fixture.bundle(
        key: key,
        locale: locale,
        bytes: authored,
      );
      final firstStarted = Completer<void>();
      final finishFirst = Completer<void>();
      var activePlayers = 0;
      var maximumActivePlayers = 0;
      var playCount = 0;
      final service = AudioPromptService(
        resolver: fixture.resolver,
        playAuthored: (_, _) async {
          playCount += 1;
          activePlayers += 1;
          maximumActivePlayers = activePlayers > maximumActivePlayers
              ? activePlayers
              : maximumActivePlayers;
          if (playCount == 1) {
            firstStarted.complete();
            await finishFirst.future;
          }
          activePlayers -= 1;
        },
        playTts: (_) async {},
        stopPlayback: () async {},
      );

      final first = service.play(request());
      await firstStarted.future;
      final second = service.play(request());
      await Future<void>.delayed(Duration.zero);

      expect(playCount, 1);
      finishFirst.complete();
      expect(await first, AudioPromptSource.bundledAsset);
      expect(await second, AudioPromptSource.bundledAsset);
      expect(playCount, 2);
      expect(maximumActivePlayers, 1);
    },
  );

  test('authored failure stops native playback before starting TTS', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);
    final events = <String>[];
    final service = AudioPromptService(
      resolver: fixture.resolver,
      playAuthored: (_, _) async {
        events.add('authored');
        throw StateError('decoder failed');
      },
      playTts: (_) async => events.add('tts'),
      stopPlayback: () async => events.add('stop'),
    );

    expect(await service.play(request()), AudioPromptSource.tts);
    expect(events, <String>['authored', 'stop', 'tts']);
  });

  test('authored budget includes startup and decoder tail allowance', () async {
    final fixture = _Fixture.bundle(key: key, locale: locale, bytes: authored);

    expect(
      await fixture.repository.budget(AudioPromptKey(key), locale),
      const Duration(milliseconds: 11200),
    );
  });

  test(
    'registry accepts canonical locale aliases without TTS fallback',
    () async {
      final fixture = _Fixture.bundle(
        key: key,
        locale: locale,
        bytes: authored,
      );
      final resolution = await fixture.resolver.resolve(
        AudioPromptRequest(
          key: AudioPromptKey(key),
          fallbackText: 'Xin chào',
          locale: 'vi_VN',
        ),
      );

      expect(resolution.source, AudioPromptSource.bundledAsset);
    },
  );

  test(
    'pack update is atomic and can roll back to the last stable pack',
    () async {
      final v1 = Uint8List.fromList(utf8.encode('pack version one'));
      final v2 = Uint8List.fromList(utf8.encode('pack version two'));
      var corruptV2 = false;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('v1.mp3')) {
          return http.Response.bytes(v1, 200);
        }
        return http.Response.bytes(
          corruptV2 ? utf8.encode('corrupt') : v2,
          200,
        );
      });
      final repository = AudioPackRepository(
        bundledManifestAssets: const [],
        bundle: _MemoryAssetBundle(const {}),
        cache: MemoryAudioPackCache(),
        httpClient: client,
        allowedCdnHosts: const {'cdn.example.com'},
      );

      await repository.installManifest(
        _remoteManifest(key, locale, 'v1', v1, 'v1.mp3'),
      );
      expect(
        (await repository.find(AudioPromptKey(key), locale))!.prompt.sha256,
        _checksum(v1),
      );

      corruptV2 = true;
      await expectLater(
        repository.installManifest(
          _remoteManifest(key, locale, 'v2-bad', v2, 'v2.mp3'),
        ),
        throwsFormatException,
      );
      expect(
        (await repository.find(AudioPromptKey(key), locale))!.prompt.sha256,
        _checksum(v1),
      );

      corruptV2 = false;
      await repository.installManifest(
        _remoteManifest(key, locale, 'v2', v2, 'v2.mp3'),
      );
      expect(
        (await repository.find(AudioPromptKey(key), locale))!.prompt.sha256,
        _checksum(v2),
      );
      expect(await repository.rollback('test-pack'), isTrue);
      expect(
        (await repository.find(AudioPromptKey(key), locale))!.prompt.sha256,
        _checksum(v1),
      );
    },
  );

  test('rejects HTTP and non-allowlisted CDN URLs', () {
    expect(
      () => AudioPackPrompt(
        key: AudioPromptKey(key),
        locale: locale,
        sha256: _checksum(authored),
        durationSeconds: 1,
        remoteUri: Uri.parse('http://cdn.example.com/audio.mp3'),
      ),
      throwsFormatException,
    );
    final repository = AudioPackRepository(
      bundledManifestAssets: const [],
      bundle: _MemoryAssetBundle(const {}),
      cache: MemoryAudioPackCache(),
      allowedCdnHosts: const {'cdn.example.com'},
    );
    expect(
      repository.isAllowedRemote(Uri.parse('https://evil.example/audio.mp3')),
      isFalse,
    );
  });

  test('rejects mutable URLs and packs requiring a newer app', () async {
    final repository = AudioPackRepository(
      bundledManifestAssets: const [],
      bundle: _MemoryAssetBundle(const {}),
      cache: MemoryAudioPackCache(),
      allowedCdnHosts: const {'cdn.example.com'},
      currentAppVersion: '1.0.8',
    );
    final mutable = AudioPackManifest(
      pack: 'test-pack',
      version: 'v1',
      prompts: <AudioPackPrompt>[
        AudioPackPrompt(
          key: AudioPromptKey(key),
          locale: locale,
          sha256: _checksum(authored),
          durationSeconds: 1,
          remoteUri: Uri.parse('https://cdn.example.com/latest.mp3'),
        ),
      ],
    );
    await expectLater(
      repository.installManifest(mutable),
      throwsFormatException,
    );

    final incompatible = AudioPackManifest(
      pack: 'test-pack',
      version: 'v2',
      minimumAppVersion: '2.0.0',
      prompts: <AudioPackPrompt>[],
    );
    await expectLater(
      repository.installManifest(incompatible),
      throwsStateError,
    );
  });

  test('pack object LRU preserves protected active checksums', () async {
    final cache = MemoryAudioPackCache();
    final oldBytes = Uint8List.fromList(utf8.encode('old cached object'));
    final activeBytes = Uint8List.fromList(utf8.encode('active pack object'));
    final oldChecksum = _checksum(oldBytes);
    final activeChecksum = _checksum(activeBytes);
    await cache.putVerified(
      pack: 'old-pack',
      sha256: oldChecksum,
      bytes: oldBytes,
      maximumBytes: 1024,
    );
    await cache.putVerified(
      pack: 'active-pack',
      sha256: activeChecksum,
      bytes: activeBytes,
      maximumBytes: 1024,
    );

    expect(
      await cache.pruneObjects(
        protectedChecksums: <String>{activeChecksum},
        maximumBytes: activeBytes.length,
      ),
      1,
    );
    expect(
      await cache.readVerified(
        pack: 'old-pack',
        sha256: oldChecksum,
        maximumBytes: 1024,
      ),
      isNull,
    );
    expect(
      await cache.readVerified(
        pack: 'active-pack',
        sha256: activeChecksum,
        maximumBytes: 1024,
      ),
      isNotNull,
    );
  });

  test(
    'legacy VoicePromptService adapter preserves keyed authored playback',
    () async {
      const manifestAsset = 'assets/data/test_audio.json';
      const audioAsset = 'assets/audio/test/prompt.mp3';
      final manifest = _manifestJson(
        key: key,
        locale: locale,
        checksum: _checksum(authored),
        asset: audioAsset,
        sizeBytes: authored.length,
      );
      final delegate = _RecordingVoicePromptService();
      final adapter = VoicePromptAudioRegistryAdapter(
        delegate: delegate,
        manifestAssets: const [manifestAsset],
        bundle: _MemoryAssetBundle({
          manifestAsset: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
          audioAsset: authored,
        }),
        cache: MemoryAudioPackCache(),
      );

      await adapter.speakAndWaitWithAudioKey(key, 'fallback', locale: locale);

      expect(delegate.authoredPlays, 1);
      expect(delegate.ttsPlays, 0);
      await adapter.dispose();
    },
  );

  test('production factory loads generated packs into the registry', () async {
    final main = createVoicePromptService(owner: AudioTurnOwner.mainAssistant);
    final listening = createVoicePromptService(
      owner: AudioTurnOwner.listeningLesson,
    );
    final vocabulary = createVoicePromptService(
      owner: AudioTurnOwner.vocabulary,
    );
    addTearDown(main.dispose);
    addTearDown(listening.dispose);
    addTearDown(vocabulary.dispose);

    expect(main, isA<VoicePromptAudioRegistryAdapter>());
    expect(listening, isA<VoicePromptAudioRegistryAdapter>());
    expect(vocabulary, isA<VoicePromptAudioRegistryAdapter>());
    final mainRegistry = main as VoicePromptAudioRegistryAdapter;
    final listeningRegistry = listening as VoicePromptAudioRegistryAdapter;
    final vocabularyRegistry = vocabulary as VoicePromptAudioRegistryAdapter;

    expect(await mainRegistry.repository.activeManifests(), hasLength(1));
    expect(await listeningRegistry.repository.activeManifests(), hasLength(12));
    expect(await vocabularyRegistry.repository.activeManifests(), hasLength(2));

    expect(
      await mainRegistry.repository.find(
        AudioPromptKey('assistant.main.open_menu.vi'),
        'vi-VN',
      ),
      isNotNull,
    );
    expect(
      await listeningRegistry.repository.find(
        AudioPromptKey('listening.navigation.choose_topic.vi'),
        'vi-VN',
      ),
      isNotNull,
    );
    expect(
      await listeningRegistry.repository.find(
        AudioPromptKey('listening.sentence.C35-L1-T01-B01-T01.en'),
        'en-US',
      ),
      isNotNull,
    );
    expect(
      await listeningRegistry.repository.find(
        AudioPromptKey('listening.challenge.C35-L1-T01-B01-Q01.prompt.vi'),
        'vi-VN',
      ),
      isNotNull,
    );
    expect(
      await vocabularyRegistry.repository.find(
        AudioPromptKey('vocabulary.guide.listen.vi'),
        'vi-VN',
      ),
      isNotNull,
    );
    expect(
      await vocabularyRegistry.repository.find(
        AudioPromptKey('vocabulary.entry.C35-L1-T01-B01-T01.word.en'),
        'en-US',
      ),
      isNotNull,
    );
    expect(
      await vocabularyRegistry.repository.find(
        AudioPromptKey('vocabulary.entry.C35-L1-T01-B01-T01.meaning.vi'),
        'vi-VN',
      ),
      isNotNull,
    );
  });
}

final class _Fixture {
  _Fixture._(this.repository, this.cache)
    : resolver = AudioPromptResolver(repository: repository);

  factory _Fixture.bundle({
    required String key,
    required String locale,
    required Uint8List bytes,
    String? text,
  }) {
    const manifestAsset = 'assets/data/test_audio.json';
    const audioAsset = 'assets/audio/test/prompt.mp3';
    final manifest = _manifestJson(
      key: key,
      locale: locale,
      checksum: _checksum(bytes),
      asset: audioAsset,
      sizeBytes: bytes.length,
      textHash: text == null ? null : _textHash(text),
    );
    final cache = MemoryAudioPackCache();
    return _Fixture._(
      AudioPackRepository(
        bundledManifestAssets: const [manifestAsset],
        bundle: _MemoryAssetBundle({
          manifestAsset: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
          audioAsset: bytes,
        }),
        cache: cache,
      ),
      cache,
    );
  }

  factory _Fixture.remote({
    required String key,
    required String locale,
    required Uint8List expectedBytes,
    required http.Client client,
  }) {
    const manifestAsset = 'assets/data/test_audio.json';
    final manifest = _manifestJson(
      key: key,
      locale: locale,
      checksum: _checksum(expectedBytes),
      url:
          'https://cdn.example.com/prompt.mp3?sha256=${_checksum(expectedBytes)}',
      sizeBytes: expectedBytes.length,
    );
    final cache = MemoryAudioPackCache();
    return _Fixture._(
      AudioPackRepository(
        bundledManifestAssets: const [manifestAsset],
        bundle: _MemoryAssetBundle({
          manifestAsset: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
        }),
        cache: cache,
        httpClient: client,
        allowedCdnHosts: const {'cdn.example.com'},
      ),
      cache,
    );
  }

  final AudioPackRepository repository;
  final MemoryAudioPackCache cache;
  final AudioPromptResolver resolver;
}

final class _MemoryAssetBundle extends CachingAssetBundle {
  _MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) throw StateError('Missing test asset: $key');
    return ByteData.sublistView(bytes);
  }
}

final class _RecordingVoicePromptService
    implements VoicePromptService, AuthoredAudioVoicePromptService {
  int authoredPlays = 0;
  int ttsPlays = 0;

  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    authoredPlays += 1;
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    ttsPlays += 1;
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    ttsPlays += 1;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Map<String, dynamic> _manifestJson({
  required String key,
  required String locale,
  required String checksum,
  String? asset,
  String? url,
  int? sizeBytes,
  String? textHash,
}) => <String, dynamic>{
  'schemaVersion': 1,
  'pack': 'test-pack',
  'version': 'bundled',
  'enabled': true,
  'prompts': [
    <String, dynamic>{
      'key': key,
      'locale': locale,
      'sha256': checksum,
      'durationSeconds': 1.2,
      'asset': ?asset,
      'url': ?url,
      'sizeBytes': ?sizeBytes,
      'textHash': ?textHash,
    },
  ],
};

AudioPackManifest _remoteManifest(
  String key,
  String locale,
  String version,
  Uint8List bytes,
  String file,
) => AudioPackManifest(
  pack: 'test-pack',
  version: version,
  prompts: [
    AudioPackPrompt(
      key: AudioPromptKey(key),
      locale: locale,
      sha256: _checksum(bytes),
      durationSeconds: 1,
      sizeBytes: bytes.length,
      remoteUri: Uri.parse(
        'https://cdn.example.com/$file?sha256=${_checksum(bytes)}',
      ),
    ),
  ],
);

String _checksum(Uint8List bytes) => sha256.convert(bytes).toString();

String _textHash(String text) => sha256
    .convert(utf8.encode(text.replaceAll(RegExp(r'\s+'), ' ').trim()))
    .toString();
