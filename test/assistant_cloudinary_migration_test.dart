import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_key.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_request.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_resolver.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/local_cloudinary_audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const path = 'assets/data/assistant_core_audio.json';
  final manifest =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final prompts = (manifest['prompts'] as List).cast<Map<String, dynamic>>();
  AudioPromptRequest request(Map<String, dynamic> p) => AudioPromptRequest(
    key: AudioPromptKey(p['key'] as String),
    fallbackText: p['text'] as String? ?? '',
    locale: p['locale'] as String,
  );

  test('every assistant URL maps to the original file and manifest index', () {
    final keys = prompts.map((prompt) => prompt['key']).toSet();
    expect(keys, hasLength(prompts.length));
    expect(
      keys,
      containsAll(<String>[
        'assistant.main.song_skipped.vi',
        'assistant.topic.choose_10.vi',
        'assistant.topic.invalid_10.vi',
        'assistant.topic.choose_course_relearn.vi',
      ]),
    );
    for (final p in prompts) {
      final uri = Uri.parse(p['url'] as String);
      expect(uri.scheme, 'https');
      expect(uri.host, 'res.cloudinary.com');
      expect(uri.path, contains('/video/upload/'));
      expect(uri.path, contains('/homi/audio/assistant-core/'));
      expect(uri.path, contains(p['sha256']));
      final bytes = File(p['asset'] as String).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), p['sha256']);
      expect(bytes.length, p['sizeBytes']);
    }
    final index = jsonDecode(
      File('assets/data/audio_pack_index.json').readAsStringSync(),
    );
    final pack = (index['packs'] as List).singleWhere(
      (p) => p['pack'] == 'assistant-core',
    );
    expect(
      pack['manifestSha256'],
      sha256.convert(File(path).readAsBytesSync()).toString(),
    );
    expect(pack['version'], manifest['version']);
  });

  test(
    'release bundle plays verified assistant prompts without a CDN request',
    () async {
      final bundle = await AssetManifest.loadFromAssetBundle(rootBundle);
      final bundledPaths = bundle.listAssets().toSet();
      final repository = AudioPackRepository(
        bundledManifestAssets: const [path],
        cache: MemoryAudioPackCache(),
        httpClient: MockClient((_) => throw StateError('CDN was requested')),
      );
      addTearDown(repository.dispose);
      final resolver = AudioPromptResolver(repository: repository);
      for (final p in prompts.where((p) => p['enabled'] == true)) {
        expect(bundledPaths, contains(p['asset']), reason: p['key'] as String);
        final first = await resolver.resolve(request(p));
        expect(
          first.source,
          AudioPromptSource.bundledAsset,
          reason: p['key'] as String,
        );
        expect(sha256.convert(first.bytes!).toString(), p['sha256']);
      }
    },
  );

  test(
    'CDN timeout uses TTS and does not prevent cached lesson playback',
    () async {
      final pending = Completer<http.Response>();
      final client = MockClient((_) => pending.future);
      final repository = AudioPackRepository(
        bundledManifestAssets: const [
          'assets/data/listening_8_10_audio.json',
          'assets/data/listening_common_audio.json',
        ],
        cache: MemoryAudioPackCache(),
        httpClient: client,
        remoteAudioTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(repository.dispose);
      final resolver = AudioPromptResolver(repository: repository);
      final agePack = (await repository.activeManifests()).singleWhere(
        (p) => p.pack == 'listening-8-10',
      );
      final uncached = agePack.prompts.firstWhere((p) => p.enabled);
      expect(
        (await resolver.resolve(
          AudioPromptRequest(
            key: uncached.key,
            fallbackText: uncached.sourceText ?? '',
            locale: uncached.locale,
          ),
        )).source,
        AudioPromptSource.tts,
      );
      final lessonPack = (await repository.activeManifests()).singleWhere(
        (p) => p.pack == 'listening-common',
      );
      final lesson = lessonPack.prompts.firstWhere((p) => p.enabled);
      await repository.cache.putVerified(
        pack: lessonPack.pack,
        sha256: lesson.sha256,
        bytes: File(lesson.asset!).readAsBytesSync(),
        maximumBytes: repository.maximumAudioBytes,
      );
      expect(
        (await resolver.resolve(
          AudioPromptRequest(
            key: lesson.key,
            fallbackText: lesson.sourceText ?? '',
            locale: lesson.locale,
          ),
        )).source,
        AudioPromptSource.deviceCache,
      );
      pending.complete(http.Response('offline', 503));
    },
  );

  test(
    'verified remote recording still plays when cache storage fails',
    () async {
      const agePath = 'assets/data/listening_8_10_audio.json';
      final repository = AudioPackRepository(
        bundledManifestAssets: const [agePath],
        cache: _UnavailableCache(),
        httpClient: createLocalCloudinaryAudioClient(),
      );
      addTearDown(repository.dispose);
      final prompt = (await repository.activeManifests()).single.prompts
          .firstWhere((p) => p.enabled);
      final result = await AudioPromptResolver(repository: repository).resolve(
        AudioPromptRequest(
          key: prompt.key,
          fallbackText: prompt.sourceText ?? '',
          locale: prompt.locale,
        ),
      );
      expect(result.source, AudioPromptSource.remote);
      expect(sha256.convert(result.bytes!).toString(), prompt.sha256);
    },
  );
}

class _UnavailableCache implements AudioPackCache {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw FileSystemException('Cache storage unavailable');
}
