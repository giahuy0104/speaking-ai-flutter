import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'installation_auth_session.dart';

class InstallationAuthenticatedClient extends http.BaseClient {
  InstallationAuthenticatedClient({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    Future<void> Function()? clientIdResetter,
    http.Client? inner,
    InstallationAuthSession? session,
  }) : _config = config,
       _inner = inner ?? http.Client(),
       _session =
           session ??
           InstallationAuthRegistry.session(
             config: config,
             clientIdProvider: clientIdProvider,
             clientIdResetter: clientIdResetter,
           );

  final AppConfig _config;
  final http.Client _inner;
  final InstallationAuthSession _session;

  /// Ensures an installation credential is valid before a caller serializes
  /// a request body containing its client id. A registration conflict can
  /// rotate the native id, so this must happen before that id is read.
  Future<void> ensureAuthenticated() => _session.accessToken();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_isBackendRequest(request.url) ||
        request.headers.containsKey('authorization')) {
      return _inner.send(request);
    }
    // Buffered so the request can be sent again after a 401. Streamed
    // requests cannot be replayed and are sent once.
    final replay = await _ReplayableRequest.capture(request);
    final token = await _session.accessToken();
    final response = await _inner.send(
      replay?.build(token) ??
          (request..headers['authorization'] = 'Bearer $token'),
    );
    if (response.statusCode != 401) return response;

    await _session.invalidateAccessToken();
    if (replay == null) return response;
    final String retryToken;
    try {
      retryToken = await _session.accessToken();
    } on Object {
      // No new credential (e.g. the installation was revoked): keep the 401.
      return response;
    }
    if (retryToken == token) return response;
    await response.stream.drain<void>();
    return _inner.send(replay.build(retryToken));
  }

  bool _isBackendRequest(Uri uri) =>
      uri.scheme == _config.backendBaseUri.scheme &&
      uri.host == _config.backendBaseUri.host &&
      uri.port == _config.backendBaseUri.port;

  @override
  void close() {
    _inner.close();
  }
}

/// A finalized copy of a [http.Request] or [http.MultipartRequest] that can be
/// sent more than once. Audio uploads are small enough to keep in memory.
class _ReplayableRequest {
  _ReplayableRequest._(this._source, this._headers, this._body);

  final http.BaseRequest _source;
  final Map<String, String> _headers;
  final List<int> _body;

  static Future<_ReplayableRequest?> capture(http.BaseRequest request) async {
    if (request is! http.Request && request is! http.MultipartRequest) {
      return null;
    }
    // finalize() also sets the multipart content-type with its boundary.
    final body = await request.finalize().toBytes();
    return _ReplayableRequest._(
      request,
      Map<String, String>.of(request.headers),
      body,
    );
  }

  http.Request build(String accessToken) {
    final copy = http.Request(_source.method, _source.url)
      ..followRedirects = _source.followRedirects
      ..maxRedirects = _source.maxRedirects
      ..persistentConnection = _source.persistentConnection
      ..headers.addAll(_headers)
      ..headers['authorization'] = 'Bearer $accessToken'
      ..bodyBytes = _body;
    return copy;
  }
}
