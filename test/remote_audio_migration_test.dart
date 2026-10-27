import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_loudness_manifest.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_request.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_resolver.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/remote_audio_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/controlled_audio_playback.dart';
import 'support/local_cloudinary_audio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every original audio file has an exact verified public URL', () async {
    final catalog = await RemoteAudioCatalog.load();
    final originals = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        .toList();
    expect(catalog.entries, hasLength(originals.length));
    for (final file in originals) {
      final asset = file.path.replaceAll(r'\', '/');
      final entry = catalog.entries[asset];
      expect(entry, isNotNull, reason: asset);
      expect(entry!.verifies(await file.readAsBytes()), isTrue, reason: asset);
      expect(catalog.entryFor(Uri.parse('asset:///$asset')), same(entry));
      expect(
        RemoteAudioCatalog.resolveLoadedUri(Uri.parse('asset:///$asset')),
        entry.uri,
      );
    }
    // This clip is used directly by the song screen rather than a prompt key.
    expect(
      catalog.entries,
      contains(
        'assets/audio/assistant-core/assistant.main.song_skipped.vi.mp3',
      ),
    );
  });

  test('every manifest prompt points at its verified catalog URL', () async {
    final catalog = await RemoteAudioCatalog.load();
    final index =
        jsonDecode(File('assets/data/audio_pack_index.json').readAsStringSync())
            as Map;
    final expectedManifests = <String>{
      for (final pack in index['packs'] as List) pack['manifest'] as String,
      'assets/data/homi_gap66_audio.json',
    };
    final manifests = <String>{};
    for (final file in Directory('assets/data').listSync().whereType<File>()) {
      if (!file.path.endsWith('.json') || !file.path.contains('audio')) {
        continue;
      }
      final data = jsonDecode(file.readAsStringSync()) as Map;
      if (data['prompts'] is! List) continue;
      manifests.add(file.path.replaceAll(r'\', '/'));
      for (final p in data['prompts'] as List) {
        final entry = catalog.entries[p['asset']];
        expect(entry, isNotNull, reason: '${p['key'] ?? p['id']}');
        expect(p['url'], entry!.uri.toString());
        expect(p['sha256'], entry.sha256Checksum);
        expect(p['sizeBytes'], entry.sizeBytes);
      }
    }
    expect(manifests, expectedManifests);
  });

  test('built Flutter bundle contains metadata and zero audio files', () async {
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets();
    expect(assets, contains(RemoteAudioCatalog.assetKey));
    expect(
      assets.where(
        (p) => RegExp(
          r'\.(mp3|wav|m4a|aac|ogg|flac|opus)$',
          caseSensitive: false,
        ).hasMatch(p),
      ),
      isEmpty,
    );
    expect(assets.where((p) => p.startsWith('assets/audio/')), isEmpty);
  });

  test(
    'every enabled static registry prompt resolves remotely without TTS',
    () async {
      final paths = Directory('assets/data')
          .listSync()
          .whereType<File>()
          .where(
            (f) => RegExp(
              r'(assistant_core|listening_.*|challenge_.*|vocabulary_.*)_audio\.json$',
            ).hasMatch(f.path),
          )
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();
      final client = createLocalCloudinaryAudioClient();
      final repository = AudioPackRepository(
        bundledManifestAssets: paths,
        cache: MemoryAudioPackCache(),
        httpClient: client,
      );
      addTearDown(() {
        repository.dispose();
        client.close();
      });
      final resolver = AudioPromptResolver(repository: repository);
      final expectedPromptCount = paths.fold<int>(0, (count, path) {
        final data = jsonDecode(File(path).readAsStringSync()) as Map;
        return count +
            (data['prompts'] as List)
                .where((prompt) => prompt['enabled'] == true)
                .length;
      });
      expect(expectedPromptCount, greaterThan(0));
      var checked = 0;
      for (final manifest in await repository.activeManifests()) {
        for (final prompt in manifest.prompts.where((p) => p.enabled)) {
          final result = await resolver.resolve(
            AudioPromptRequest(
              key: prompt.key,
              fallbackText: prompt.sourceText ?? '',
              locale: prompt.locale,
              allowTtsFallback: false,
            ),
          );
          expect(
            result.source,
            anyOf(AudioPromptSource.remote, AudioPromptSource.deviceCache),
            reason: prompt.key.value,
          );
          checked++;
        }
      }
      expect(checked, expectedPromptCount);
    },
    // This exhaustively resolves the full curriculum, including repeated clips.
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('remote prompt is cached and remains available offline', () async {
    final catalog = await RemoteAudioCatalog.load();
    final entry = catalog.entries.values.first;
    final client = createLocalCloudinaryAudioClient();
    final offline = MockClient(
      (_) async => throw const SocketException('offline'),
    );
    addTearDown(client.close);
    addTearDown(offline.close);
    final store = RemoteAudioStore(cache: MemoryAudioPackCache());
    final first = await store.read(entry, client);
    expect(entry.verifies(first), isTrue);
    expect(await store.read(entry, offline), orderedEquals(first));
  });

  test('remote store rejects corrupted or failed HTTP responses', () async {
    final entry = (await RemoteAudioCatalog.load()).entries.values.first;
    for (final response in [
      http.Response('bad audio', 200),
      http.Response('offline', 503),
    ]) {
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      await expectLater(
        RemoteAudioStore(cache: MemoryAudioPackCache()).read(entry, client),
        throwsFormatException,
      );
    }
  });

  test(
    'verified audio still plays when persistent storage is unavailable',
    () async {
      final entry = (await RemoteAudioCatalog.load()).entries.values.first;
      final client = createLocalCloudinaryAudioClient();
      addTearDown(client.close);
      final bytes = await RemoteAudioStore(
        cache: _UnavailableCache(),
      ).read(entry, client);
      expect(entry.verifies(bytes), isTrue);
    },
  );

  test('concurrent requests for one clip share a download', () async {
    final entry = (await RemoteAudioCatalog.load()).entries.values.first;
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes(await File(entry.asset).readAsBytes(), 200);
    });
    addTearDown(client.close);
    final store = RemoteAudioStore(cache: MemoryAudioPackCache());
    await Future.wait(List.generate(5, (_) => store.read(entry, client)));
    expect(calls, 1);
  });

  test(
    'invalid hosts and mutable URLs cannot enter the delivery catalog',
    () async {
      final entry = (await RemoteAudioCatalog.load()).entries.values.first;
      for (final url in [
        'http://res.cloudinary.com/file.mp3',
        'https://evil.example/${entry.sha256Checksum}.mp3',
        'https://res.cloudinary.com/cloud/video/upload/mutable.mp3',
      ]) {
        expect(
          () => RemoteAudioEntry(
            asset: entry.asset,
            uri: Uri.parse(url),
            sha256Checksum: entry.sha256Checksum,
            sizeBytes: entry.sizeBytes,
          ),
          throwsFormatException,
        );
      }
    },
  );

  group('legacy media playback', () {
    const session = MethodChannel('com.ryanheise.audio_session');
    const level = MethodChannel('ailingo_voice_prompt');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(session, (_) async => null);
      messenger.setMockMethodCallHandler(level, (_) async => null);
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(session, null);
      messenger.setMockMethodCallHandler(level, null);
    });
    for (final asset in [
      'assets/audio/MAIN/SFX_STAR_TING.mp3',
      'assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3',
      'assets/audio/A-6-7/SONGS/A067_T05_SONG01_FULL_EN.mp3',
      'assets/audio/A-8-10/SONGS/A0810_T03_SONG01_FULL_EN.mp3',
      'assets/audio/assistant-core/assistant.main.song_skipped.vi.mp3',
    ]) {
      test('$asset uses Cloudinary and verified device cache', () async {
        final entry = (await RemoteAudioCatalog.load()).entries[asset]!;
        final player = ControlledPlayer();
        final cache = _MappedCache();
        final service = JustAudioPlaybackService(player: player, cache: cache);
        addTearDown(() async {
          await service.dispose();
          cache.dispose();
        });
        await service.play(Uri.parse('asset:///$asset'));
        expect(cache.requested, entry.uri);
        expect(cache.checksum, entry.sha256Checksum);
        expect(cache.maximumBytes, entry.sizeBytes);
        expect(player.playedPaths, [cache.cachedUri.toFilePath()]);
      });
    }

    test('stop cancels playback while remote cache is still loading', () async {
      final entry = (await RemoteAudioCatalog.load()).entries.values.first;
      final player = ControlledPlayer();
      final cache = _MappedCache()..pending = Completer<Uri?>();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });
      final playing = service.play(Uri.parse('asset:///${entry.asset}'));
      final cancelled = expectLater(playing, throwsA(isA<PlaybackException>()));
      await cache.entered.future;
      await service.stop();
      await cancelled;
      cache.pending!.complete(cache.cachedUri);
      await flushMicrotasks();
      expect(player.playedPaths, isEmpty);
    });

    test(
      'download failure never sends an unverified URL to the native player',
      () async {
        final entry = (await RemoteAudioCatalog.load()).entries.values.first;
        final player = ControlledPlayer();
        final cache = _MappedCache()..unavailable = true;
        final service = JustAudioPlaybackService(player: player, cache: cache);
        addTearDown(() async {
          await service.dispose();
          cache.dispose();
        });
        await expectLater(
          service.play(Uri.parse('asset:///${entry.asset}')),
          throwsA(isA<PlaybackException>()),
        );
        expect(player.playedPaths, isEmpty);
      },
    );

    test('downloaded media retains the original loudness metadata', () async {
      const asset = 'assets/audio/MAIN/SFX_STAR_TING.mp3';
      final gain = (await AudioLoudnessManifest.load()).gainDbForAsset(asset);
      expect(gain, isNotNull);
      final player = ControlledPlayer();
      final cache = _MappedCache();
      final service = JustAudioPlaybackService(player: player, cache: cache);
      addTearDown(() async {
        await service.dispose();
        cache.dispose();
      });
      await service.play(Uri.parse('asset:///$asset'));
      expect(
        player.volumesAtPlay.single,
        closeTo(math.pow(10.0, math.min(gain!, 0) / 20).toDouble(), 1e-9),
      );
    });
  });
}

class _UnavailableCache implements AudioPackCache {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw FileSystemException('cache unavailable');
}

class _MappedCache extends ControlledCache {
  final cachedUri = Uri.parse('file:///downloaded.mp3');
  final entered = Completer<void>();
  Uri? requested;
  String? checksum;
  int? maximumBytes;
  Completer<Uri?>? pending;
  bool unavailable = false;

  @override
  Future<Uri?> cacheVerified(
    Uri uri, {
    required String sha256Checksum,
    int maximumFileBytes = 2 * 1024 * 1024,
  }) async {
    requested = uri;
    checksum = sha256Checksum;
    maximumBytes = maximumFileBytes;
    if (!entered.isCompleted) entered.complete();
    if (unavailable) return null;
    return pending?.future ?? cachedUri;
  }
}
