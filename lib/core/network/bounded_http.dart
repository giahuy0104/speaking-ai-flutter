import 'dart:async';

import 'package:http/http.dart' as http;

/// Sends [request] and reads its body, both within a single [budget].
///
/// `client.send(...).timeout(budget)` covers only the connection and the
/// response headers. Reading the body afterwards with
/// `http.Response.fromStream` has no deadline of its own, so a server that
/// answers 200 and then stalls mid-body leaves the caller waiting forever —
/// for a child, a spinner that never stops.
///
/// Passing the remaining budget to the body read is not enough on its own:
/// `Future.timeout` abandons a read without cancelling it, leaving the socket
/// open and every further byte the server sends buffered in memory. This owns
/// the subscription so the connection is released when the deadline passes.
///
/// Throws [TimeoutException] when the budget runs out, exactly as the plain
/// `.timeout(...)` it replaces did, so existing error handling still applies.
Future<http.Response> sendBounded(
  http.Client client,
  http.BaseRequest request, {
  required Duration budget,
}) async {
  final elapsed = Stopwatch()..start();
  final streamed = await client.send(request).timeout(budget);
  final remaining = budget - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    // Nothing ever listens to this body, so hand the connection back instead
    // of leaving it open for the rest of the process.
    await streamed.stream.listen(null).cancel();
    throw TimeoutException('Response body exceeded its deadline.', budget);
  }
  return readBounded(streamed, budget: remaining);
}

/// Collects [streamed]'s body, giving up after [budget] and releasing the
/// connection. See [sendBounded] for why the subscription is owned here.
Future<http.Response> readBounded(
  http.StreamedResponse streamed, {
  required Duration budget,
}) async {
  final chunks = <List<int>>[];
  final body = Completer<void>();
  final subscription = streamed.stream.listen(
    chunks.add,
    onError: (Object error, StackTrace stackTrace) {
      if (!body.isCompleted) body.completeError(error, stackTrace);
    },
    onDone: () {
      if (!body.isCompleted) body.complete();
    },
    cancelOnError: true,
  );
  final deadline = Timer(budget, () {
    if (!body.isCompleted) {
      body.completeError(
        TimeoutException('Response body exceeded its deadline.', budget),
      );
    }
  });
  try {
    await body.future;
  } finally {
    deadline.cancel();
    await subscription.cancel();
  }
  return http.Response.bytes(
    chunks.expand((chunk) => chunk).toList(growable: false),
    streamed.statusCode,
    request: streamed.request,
    headers: streamed.headers,
    isRedirect: streamed.isRedirect,
    persistentConnection: streamed.persistentConnection,
    reasonPhrase: streamed.reasonPhrase,
  );
}
