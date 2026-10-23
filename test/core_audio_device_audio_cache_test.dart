import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('downloads an audio rule once and reuses the local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ailingo-audio-cache-test-',
    );
    var requests = 0;
    final cache = DeviceAudioCache(
      client: MockClient((request) async {
        requests += 1;
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }),
      directoryProvider: () async => directory,
    );
    final remote = Uri.parse(
      'https://api.example.com/api/audio/stream?text=hello',
    );

    final first = await cache.cache(remote);
    final second = await cache.cache(remote);
    final resolved = await cache.resolve(remote);

    expect(requests, 1);
    expect(first, isNotNull);
    expect(second, first);
    expect(resolved, first);
    expect(await File.fromUri(resolved).readAsBytes(), <int>[1, 2, 3, 4]);

    cache.dispose();
    await directory.delete(recursive: true);
  });

  test('verified download rejects a backend checksum mismatch', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ailingo-audio-cache-sha-test-',
    );
    final cache = DeviceAudioCache(
      client: MockClient(
        (_) async => http.Response.bytes(<int>[1, 2, 3, 4], 200),
      ),
      directoryProvider: () async => directory,
    );

    final result = await cache.cacheVerified(
      Uri.parse('https://api.example.com/audio.mp3'),
      sha256Checksum: List<String>.filled(64, '0').join(),
    );

    expect(result, isNull);
    cache.dispose();
    await directory.delete(recursive: true);
  });

  test('LRU prunes dynamic cache by total bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ailingo-audio-cache-lru-test-',
    );
    final bytes = <int>[1, 2, 3, 4];
    final cache = DeviceAudioCache(
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      directoryProvider: () async => directory,
      maxFiles: 256,
      maxBytes: 5,
    );
    final checksum = sha256.convert(bytes).toString();

    await cache.cacheVerified(
      Uri.parse('https://api.example.com/one.mp3'),
      sha256Checksum: checksum,
    );
    await cache.cacheVerified(
      Uri.parse('https://api.example.com/two.mp3'),
      sha256Checksum: checksum,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final cacheDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}rule_audio_cache',
    );
    final files = await cacheDirectory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.mp3'))
        .toList();
    expect(files, hasLength(1));
    cache.dispose();
    await directory.delete(recursive: true);
  });
}
