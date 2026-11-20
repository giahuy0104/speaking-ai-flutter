import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_speaking_flutter_app/core/audio/streamed_wav_source.dart';

/// A 24 kHz mono 16-bit WAV header with the "unknown length" sizes the backend
/// sends while it is still synthesizing.
Uint8List streamingWavHeader() {
  final header = Uint8List(44);
  final view = ByteData.sublistView(header);
  void ascii(int offset, String text) =>
      header.setRange(offset, offset + 4, text.codeUnits);
  ascii(0, 'RIFF');
  view.setUint32(4, 0xffffffff, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 24000, Endian.little);
  view.setUint32(28, 48000, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, 0xffffffff, Endian.little);
  return header;
}

Future<List<int>> collect(Stream<List<int>> stream) async =>
    (await stream.toList()).expand((chunk) => chunk).toList();

/// A source fed by a controller the test drives chunk by chunk.
({StreamedWavSource source, StreamController<List<int>> upstream})
controlledSource({
  Duration idleTimeout = StreamedWavSource.defaultIdleTimeout,
}) {
  final upstream = StreamController<List<int>>();
  final client = MockClient.streaming(
    (request, _) async => http.StreamedResponse(upstream.stream, 200),
  );
  final source = StreamedWavSource(
    Uri.parse('https://api-dev.example/api/audio/target?lang=ja'),
    client: client,
    idleTimeout: idleTimeout,
  )..start();
  return (source: source, upstream: upstream);
}

void main() {
  final uri = Uri.parse(
    'https://api-dev.example/api/audio/target?lang=zh&sig=x&text=y',
  );

  test('handles the backend routes that stream live speech', () {
    expect(StreamedWavSource.handles(uri), isTrue);
    expect(
      StreamedWavSource.handles(
        Uri.parse('https://api-dev.example/api/audio/stream?text=hi'),
      ),
      isTrue,
    );
    expect(
      StreamedWavSource.handles(
        Uri.parse('https://api-dev.example/api/audio/segments?job=j'),
      ),
      isTrue,
    );
    expect(
      StreamedWavSource.handles(
        Uri.parse('https://api-dev.example/api/audio/cache?key=k'),
      ),
      isFalse,
    );
    expect(
      StreamedWavSource.handles(Uri.parse('https://cdn.example/clip.mp3')),
      isFalse,
    );
    expect(
      StreamedWavSource.handles(Uri.parse('file:///api/audio/target')),
      isFalse,
    );
  });

  test('real duration comes from the byte rate and the bytes received', () {
    final header = streamingWavHeader();
    // 48 000 bytes/s: 84 480 PCM bytes is 1.76 s.
    expect(
      StreamedWavSource.wavDuration(header, 44 + 84480),
      const Duration(milliseconds: 1760),
    );
    expect(StreamedWavSource.wavDuration(header.sublist(0, 20), 100), isNull);
    expect(
      StreamedWavSource.wavDuration(List<int>.filled(44, 0), 1000),
      isNull,
    );
  });

  test(
    'serves bytes while they arrive and learns the length at the end',
    () async {
      final (:source, :upstream) = controlledSource();

      final sliceFuture = source.request();
      upstream.add(streamingWavHeader());
      final slice = await sliceFuture;
      expect(slice.total, isNull, reason: 'still downloading');
      expect(source.realDuration, isNull);

      final body = collect(slice.stream);
      upstream.add(List<int>.filled(48000, 1));
      await upstream.close();

      expect(await body, hasLength(44 + 48000));
      expect(source.isDownloaded, isTrue);
      expect(source.failed, isFalse);
      expect(source.realDuration, const Duration(seconds: 1));
      expect(source.playableDuration, const Duration(seconds: 1));
    },
  );

  test(
    'a ranged request waits for the whole clip so it can state the total',
    () async {
      final (:source, :upstream) = controlledSource();
      upstream.add(streamingWavHeader());

      var answered = false;
      final sliceFuture = source.request(0, 2)..then((_) => answered = true);
      upstream.add(List<int>.filled(1000, 7));
      await pumpEventQueue();
      expect(answered, isFalse, reason: 'total unknown while downloading');

      await upstream.close();
      final slice = await sliceFuture;
      expect(slice.offset, 0);
      expect(slice.length, 2);
      expect(slice.total, 44 + 1000);
      expect(await collect(slice.stream), [0x52, 0x49]); // "RI"

      final tail = await source.request(1040);
      expect(tail.length, 4);
      expect(await collect(tail.stream), [7, 7, 7, 7]);
    },
  );

  test('a range that starts at or past the end is not satisfiable', () async {
    final (:source, :upstream) = controlledSource();
    upstream.add(streamingWavHeader());
    await upstream.close();

    await expectLater(
      source.request(44),
      throwsA(isA<StreamedWavRangeNotSatisfiable>()),
    );
    await expectLater(
      source.request(500, 600),
      throwsA(isA<StreamedWavRangeNotSatisfiable>()),
    );
  });

  test(
    'a reader that pauses while the download finishes still gets every byte',
    () async {
      final (:source, :upstream) = controlledSource();
      upstream.add(streamingWavHeader());
      final slice = await source.request();

      final received = <int>[];
      final done = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      subscription = slice.stream.listen((chunk) {
        received.addAll(chunk);
        if (received.length == 44) subscription.pause();
      }, onDone: done.complete);
      await pumpEventQueue();

      upstream.add(List<int>.filled(3000, 2));
      await upstream.close();
      await pumpEventQueue();
      subscription.resume();

      await done.future.timeout(const Duration(seconds: 2));
      expect(received, hasLength(44 + 3000));
    },
  );

  test(
    'a mid-stream failure is reported, not mistaken for the real end',
    () async {
      final (:source, :upstream) = controlledSource();
      upstream.add(streamingWavHeader());
      final slice = await source.request();
      final body = collect(slice.stream);

      upstream.add(List<int>.filled(24000, 3));
      upstream.addError(http.ClientException('connection reset'));

      // The player still gets what arrived and then an end of stream.
      expect(
        await body.timeout(const Duration(seconds: 2)),
        hasLength(44 + 24000),
      );
      expect(source.failed, isTrue);
      expect(source.isDownloaded, isFalse);
      expect(source.realDuration, isNull);
      expect(source.playableDuration, const Duration(milliseconds: 500));
    },
  );

  test('a stalled download times out instead of waiting forever', () async {
    final (:source, :upstream) = controlledSource(
      idleTimeout: const Duration(milliseconds: 50),
    );
    upstream.add(streamingWavHeader());
    final slice = await source.request();
    final body = collect(slice.stream);

    expect(await body.timeout(const Duration(seconds: 2)), hasLength(44));
    expect(source.failed, isTrue);
    expect(
      upstream.hasListener,
      isFalse,
      reason: 'download subscription cancelled',
    );
  });

  test('cancel stops the download and ends readers', () async {
    final (:source, :upstream) = controlledSource();
    upstream.add(streamingWavHeader());
    final slice = await source.request();
    final body = collect(slice.stream);
    await pumpEventQueue();

    source.cancel();

    expect(await body.timeout(const Duration(seconds: 2)), hasLength(44));
    expect(source.failed, isTrue);
    expect(upstream.hasListener, isFalse);
  });

  test('an HTTP error fails the request instead of playing silence', () async {
    final client = MockClient((_) async => http.Response('nope', 403));
    final source = StreamedWavSource(uri, client: client);
    await expectLater(source.request(), throwsA(isA<http.ClientException>()));
    expect(source.failed, isTrue);
    expect(source.realDuration, isNull);
  });
}
