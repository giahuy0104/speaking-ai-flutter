import 'dart:async';
import 'package:ai_speaking_flutter_app/core/audio/sentence_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uri = Uri.parse('https://example.test/audio.mp3');
  for (final failure in <Object>[
    TimeoutException('download'),
    http.ClientException('download'),
  ]) {
    test('download ${failure.runtimeType} stays an audio error', () async {
      final cache = SentenceAudioCache(
        clientFactory: () => MockClient((_) async => throw failure),
      );
      await expectLater(
        cache.fetch(uri),
        throwsA(
          isA<SentenceAudioDownloadException>().having(
            (error) => error.code,
            'code',
            failure is TimeoutException ? 'timeout' : 'network',
          ),
        ),
      );
      await cache.close();
    });
  }
  test('rejects HTTP errors with status', () async {
    final cache = SentenceAudioCache(
      clientFactory: () => MockClient((_) async => http.Response('', 503)),
    );
    await expectLater(
      cache.fetch(uri),
      throwsA(
        isA<SentenceAudioDownloadException>().having(
          (e) => e.status,
          'status',
          503,
        ),
      ),
    );
    await cache.close();
  });
  test('stops streamed audio at the size bound', () async {
    final cache = SentenceAudioCache(
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(List.filled(2 * 1024 * 1024 + 1, 0)),
          200,
        ),
      ),
    );
    await expectLater(
      cache.fetch(uri),
      throwsA(
        isA<SentenceAudioDownloadException>().having(
          (e) => e.code,
          'code',
          'audio_too_large',
        ),
      ),
    );
    await cache.close();
  });
  test('rejects invalid checksum before storing', () async {
    final cache = SentenceAudioCache(
      clientFactory: () => MockClient((_) async => http.Response('audio', 200)),
    );
    await expectLater(
      cache.fetch(uri, checksum: 'invalid'),
      throwsA(isA<SentenceAudioDownloadException>()),
    );
    await cache.close();
  });
  test('closing invalidates an in-flight download', () async {
    final response = Completer<http.Response>();
    final cache = SentenceAudioCache(
      clientFactory: () => MockClient((_) => response.future),
    );
    final pending = cache.fetch(uri);
    final assertion = expectLater(
      pending,
      throwsA(isA<SentenceAudioDownloadException>()),
    );
    await cache.close();
    response.complete(http.Response('audio', 200));
    await assertion;
  });
}
