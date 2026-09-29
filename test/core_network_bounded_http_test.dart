import 'dart:async';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/network/bounded_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('reads a body that arrives within the budget', () async {
    final client = _FakeClient(
      body: Stream<List<int>>.value(utf8.encode('{"ok":true}')),
    );

    final response = await sendBounded(
      client,
      http.Request('POST', Uri.parse('https://api.example.com/score')),
      budget: const Duration(seconds: 5),
    );

    expect(response.statusCode, 200);
    expect(response.body, '{"ok":true}');
  });

  test('gives up on a body that stalls and releases the connection', () async {
    // The failure this guards: the server answers 200, then stops sending. The
    // old code had no deadline here at all, so a child watched the spinner
    // until the app was killed.
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    addTearDown(body.close);
    body.add(utf8.encode('{"transcript":'));
    final client = _FakeClient(body: body.stream);

    await expectLater(
      sendBounded(
        client,
        http.Request('POST', Uri.parse('https://api.example.com/score')),
        budget: const Duration(milliseconds: 100),
      ),
      throwsA(isA<TimeoutException>()),
    );

    // Abandoning the read without cancelling would leave the socket open and
    // keep buffering whatever the server sent next.
    expect(cancelled, isTrue);
  });

  test('the body only gets what the headers left of the budget', () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final client = _FakeClient(
      body: body.stream,
      headerDelay: const Duration(milliseconds: 220),
    );

    final elapsed = Stopwatch()..start();
    await expectLater(
      sendBounded(
        client,
        http.Request('POST', Uri.parse('https://api.example.com/score')),
        budget: const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
    );
    elapsed.stop();

    // A fresh budget for the body would take at least 520ms and would double
    // the worst case of every retry ladder built on top of this.
    expect(elapsed.elapsed, lessThan(const Duration(milliseconds: 450)));
  });

  test('a stream error is reported rather than waiting for the deadline', () {
    final client = _FakeClient(
      body: Stream<List<int>>.error(
        http.ClientException('Connection reset by peer'),
      ),
    );

    expect(
      sendBounded(
        client,
        http.Request('POST', Uri.parse('https://api.example.com/score')),
        budget: const Duration(seconds: 30),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient({required this.body, this.headerDelay = Duration.zero});

  final Stream<List<int>> body;
  final Duration headerDelay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (headerDelay > Duration.zero) await Future<void>.delayed(headerDelay);
    return http.StreamedResponse(body, 200, request: request);
  }
}
