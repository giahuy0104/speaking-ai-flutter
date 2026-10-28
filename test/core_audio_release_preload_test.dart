import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/listening_audio_prefetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ageManifestPath = 'assets/data/listening_8_10_audio.json';
  final ageManifest =
      jsonDecode(File(ageManifestPath).readAsStringSync())
          as Map<String, dynamic>;
  final prompts = (ageManifest['prompts'] as List).cast<Map<String, dynamic>>();
  final assetsByUrl = <String, String>{
    for (final prompt in prompts.where((item) => item['enabled'] == true))
      prompt['url'] as String: prompt['asset'] as String,
  };

  test(
    'age preload resumes from verified cache without loading other ages',
    () async {
      final requestedUrls = <String>[];
      final repository = AudioPackRepository(
        bundledManifestAssets: const [
          ageManifestPath,
          'assets/data/listening_6_7_audio.json',
        ],
        cache: MemoryAudioPackCache(),
        httpClient: MockClient((request) async {
          requestedUrls.add(request.url.toString());
          final asset = assetsByUrl[request.url.toString()];
          if (asset == null) return http.Response('Wrong age group', 404);
          return http.Response.bytes(File(asset).readAsBytesSync(), 200);
        }),
      );
      addTearDown(repository.dispose);

      var continuePreload = true;
      final first = await repository.preloadAgeGroup(
        '8-10',
        shouldContinue: () => continuePreload,
        onProgress: (progress) {
          if (progress.downloaded >= 2) continuePreload = false;
        },
      );
      expect(first.interrupted, isTrue);
      expect(first.downloaded, greaterThanOrEqualTo(2));
      expect(first.failed, 0);
      expect(first.total, greaterThan(first.downloaded));

      continuePreload = true;
      final second = await repository.preloadAgeGroup(
        '8-10',
        shouldContinue: () => continuePreload,
        onProgress: (progress) {
          if (progress.downloaded >= 1) continuePreload = false;
        },
      );
      expect(second.cached, first.downloaded);
      expect(second.downloaded, greaterThanOrEqualTo(1));
      expect(requestedUrls, everyElement(isIn(assetsByUrl.keys)));
    },
  );

  test('preload stops after repeated network failures', () async {
    var attempts = 0;
    final repository = AudioPackRepository(
      bundledManifestAssets: const [ageManifestPath],
      cache: MemoryAudioPackCache(),
      httpClient: MockClient((_) async {
        attempts += 1;
        throw const SocketException('offline');
      }),
    );
    addTearDown(repository.dispose);

    final result = await repository.preloadAgeGroup('8-10');
    expect(result.isComplete, isFalse);
    expect(result.interrupted, isTrue);
    expect(result.failed, inInclusiveRange(3, 4));
    expect(attempts, result.failed);
  });

  test('background preload waits for Wi-Fi', () async {
    final wifiChanges = StreamController<bool>.broadcast();
    addTearDown(wifiChanges.close);
    var wifiAvailable = false;
    final firstRequest = Completer<void>();
    final response = Completer<http.Response>();
    var repositoriesCreated = 0;
    var requested = 0;
    final prefetcher = ListeningAudioPrefetcher(
      wifiAvailable: () async => wifiAvailable,
      wifiChanges: () => wifiChanges.stream,
      repositoryFactory: (assets) {
        repositoriesCreated += 1;
        return AudioPackRepository(
          bundledManifestAssets: assets,
          cache: MemoryAudioPackCache(),
          httpClient: MockClient((_) {
            requested += 1;
            if (!firstRequest.isCompleted) firstRequest.complete();
            return response.future;
          }),
        );
      },
    );
    addTearDown(prefetcher.dispose);

    prefetcher.selectAgeGroup('8-10');
    prefetcher.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repositoriesCreated, 0);

    wifiAvailable = true;
    wifiChanges.add(true);
    await firstRequest.future.timeout(const Duration(seconds: 3));
    expect(repositoriesCreated, 1);
    wifiChanges.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    response.complete(http.Response('offline', 503));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(requested, lessThanOrEqualTo(2));
    prefetcher.dispose();
  });
}
