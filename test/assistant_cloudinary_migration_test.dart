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
    expect(prompts, hasLength(81));
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
    'release bundle excludes assistant files; enabled prompts download then cache',
    () async {
      final bundle = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        bundle.listAssets().where(
          (p) => p.startsWith('assets/audio/assistant-core/'),
        ),
        isEmpty,
      );
      final repository = AudioPackRepository(
        bundledManifestAssets: const [path],
        cache: MemoryAudioPackCache(),
        httpClient: createLocalCloudinaryAudioClient(),
      );
      addTearDown(repository.dispose);
      final resolver = AudioPromptResolver(repository: repository);
      for (final p in prompts.where((p) => p['enabled'] == true)) {
        final first = await resolver.resolve(request(p));
        expect(
          first.source,
          anyOf(AudioPromptSource.remote, AudioPromptSource.deviceCache),
          reason: p['key'] as String,
        );
        expect(sha256.convert(first.bytes!).toString(), p['sha256']);
        expect(
          (await resolver.resolve(request(p))).source,
          AudioPromptSource.deviceCache,
        );
      }
    },
  );

  test(
    'CDN timeout uses TTS and does not prevent bundled lesson playback',
    () async {
      final pending = Completer<http.Response>();
      final client = MockClient((_) => pending.future);
      final repository = AudioPackRepository(
        bundledManifestAssets: const [
          path,
          'assets/data/listening_common_audio.json',
        ],
        cache: MemoryAudioPackCache(),
        httpClient: client,
        remoteAudioTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(repository.dispose);
      final resolver = AudioPromptResolver(repository: repository);
      expect(
        (await resolver.resolve(request(prompts.first))).source,
        AudioPromptSource.tts,
      );
      final lessonPack = (await repository.activeManifests()).singleWhere(
        (p) => p.pack == 'listening-common',
      );
      final lesson = lessonPack.prompts.firstWhere((p) => p.enabled);
      expect(
        (await resolver.resolve(
          AudioPromptRequest(
            key: lesson.key,
            fallbackText: lesson.sourceText ?? '',
            locale: lesson.locale,
          ),
        )).source,
        AudioPromptSource.bundledAsset,
      );
      pending.complete(http.Response('offline', 503));
    },
  );

  test(
    'verified remote recording still plays when cache storage fails',
    () async {
      final repository = AudioPackRepository(
        bundledManifestAssets: const [path],
        cache: _UnavailableCache(),
        httpClient: createLocalCloudinaryAudioClient(),
      );
      addTearDown(repository.dispose);
      final result = await AudioPromptResolver(
        repository: repository,
      ).resolve(request(prompts.first));
      expect(result.source, AudioPromptSource.remote);
      expect(sha256.convert(result.bytes!).toString(), prompts.first['sha256']);
    },
  );
}

class _UnavailableCache implements AudioPackCache {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw FileSystemException('Cache storage unavailable');
}
