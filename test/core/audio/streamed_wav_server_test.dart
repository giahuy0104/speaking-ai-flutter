import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_speaking_flutter_app/core/audio/streamed_wav_server.dart';
import 'package:ai_speaking_flutter_app/core/audio/streamed_wav_source.dart';

import 'streamed_wav_source_test.dart' show streamingWavHeader;

typedef _Reply = ({
  int status,
  HttpHeaders headers,
  List<int> body,
  DateTime endedAt,
});

void main() {
  late HttpClient client;
  setUp(() => client = HttpClient());
  tearDown(() => client.close(force: true));

  ({StreamedWavSource source, StreamController<List<int>> upstream})
  newSource() {
    final upstream = StreamController<List<int>>();
    final source = StreamedWavSource(
      Uri.parse('https://api-dev.example/api/audio/target?lang=ja'),
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(upstream.stream, 200),
      ),
    )..start();
    return (source: source, upstream: upstream);
  }

  Future<_Reply> get(Uri local, {String? range}) async {
    final request = await client.getUrl(local);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return (
      status: response.statusCode,
      headers: response.headers,
      body: body,
      endedAt: DateTime.now(),
    );
  }

  test(
    'streams a clip of unknown length and ends right after the last byte',
    () async {
      final (:source, :upstream) = newSource();
      final local = (await registerStreamedWav(source))!;
      addTearDown(() => unregisterStreamedWav(source));

      final reply = get(local);
      upstream.add(streamingWavHeader());
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        upstream.add(Uint8List(1500)..fillRange(0, 1500, i));
      }
      await upstream.close();
      final upstreamClosedAt = DateTime.now();

      final result = await reply.timeout(const Duration(seconds: 5));
      expect(result.status, HttpStatus.ok);
      expect(result.headers.chunkedTransferEncoding, isTrue);
      expect(result.headers.contentType?.mimeType, 'audio/wav');
      expect(result.body, hasLength(44 + 20 * 1500));
      expect(result.body.sublist(44 + 19 * 1500), everyElement(19));
      expect(
        result.endedAt.difference(upstreamClosedAt),
        lessThan(const Duration(milliseconds: 300)),
      );
    },
  );

  test('answers the AVPlayer probe range once the clip is complete', () async {
    final (:source, :upstream) = newSource();
    final local = (await registerStreamedWav(source))!;
    addTearDown(() => unregisterStreamedWav(source));

    final reply = get(local, range: 'bytes=0-1');
    upstream.add(streamingWavHeader());
    upstream.add(List<int>.filled(1000, 9));
    await upstream.close();

    final result = await reply.timeout(const Duration(seconds: 5));
    expect(result.status, HttpStatus.partialContent);
    expect(
      result.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 0-1/1044',
    );
    expect(result.headers.contentLength, 2);
    expect(result.body, [0x52, 0x49]);
  });

  test('a range past the end gets 416', () async {
    final (:source, :upstream) = newSource();
    final local = (await registerStreamedWav(source))!;
    addTearDown(() => unregisterStreamedWav(source));
    upstream.add(streamingWavHeader());
    await upstream.close();

    final result = await get(local, range: 'bytes=44-');
    expect(result.status, HttpStatus.requestedRangeNotSatisfiable);
    expect(result.headers.value(HttpHeaders.contentRangeHeader), 'bytes */44');
  });

  test(
    'a source that fails before any byte gets 502, an unknown id 404',
    () async {
      final source = StreamedWavSource(
        Uri.parse('https://api-dev.example/api/audio/target?lang=ja'),
        client: MockClient((_) async => http.Response('no', 403)),
      );
      final local = (await registerStreamedWav(source))!;
      addTearDown(() => unregisterStreamedWav(source));

      expect((await get(local)).status, HttpStatus.badGateway);
      expect(
        (await get(local.replace(path: '/wav/999999.wav'))).status,
        HttpStatus.notFound,
      );
    },
  );

  test('HEAD and an unusable Range are answered, not dropped', () async {
    final (:source, :upstream) = newSource();
    final local = (await registerStreamedWav(source))!;
    addTearDown(() => unregisterStreamedWav(source));
    upstream.add(streamingWavHeader());
    upstream.add(List<int>.filled(100, 1));
    await upstream.close();

    final head = await client.headUrl(local).then((r) => r.close());
    await head.drain<void>();
    expect(head.statusCode, HttpStatus.ok);
    expect(head.headers.contentLength, 144);

    for (final range in [
      'bytes=9-3',
      'bytes=99999999999999999999-',
      'items=0-1',
    ]) {
      final result = await get(local, range: range);
      expect(result.status, HttpStatus.ok, reason: range);
      expect(result.body, hasLength(144), reason: range);
    }
  });

  test('a finished MP3 clip keeps its content type', () async {
    final upstream = StreamController<List<int>>();
    final source = StreamedWavSource(
      Uri.parse('https://api-dev.example/api/audio/target?lang=zh'),
      client: MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          upstream.stream,
          200,
          headers: {'content-type': 'audio/mpeg'},
        ),
      ),
    )..start();
    final local = (await registerStreamedWav(source))!;
    addTearDown(() => unregisterStreamedWav(source));

    final reply = get(local);
    upstream.add(List<int>.filled(3000, 0xff));
    await upstream.close();

    final result = await reply.timeout(const Duration(seconds: 5));
    expect(result.status, HttpStatus.ok);
    expect(result.headers.contentType?.mimeType, 'audio/mpeg');
    expect(result.body, hasLength(3000));
    expect(source.contentType, 'audio/mpeg');
    expect(source.isWav, isFalse);
    expect(
      source.playableDuration,
      isNull,
      reason: 'the player ends an MP3 itself',
    );
  });

  test('an unregistered source is no longer served', () async {
    final (:source, :upstream) = newSource();
    final local = (await registerStreamedWav(source))!;
    unregisterStreamedWav(source);
    await upstream.close();
    expect((await get(local)).status, HttpStatus.notFound);
  });
}
