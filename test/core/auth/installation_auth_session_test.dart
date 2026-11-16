import 'dart:async';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/auth/installation_auth_session.dart';
import 'package:ai_speaking_flutter_app/core/auth/installation_authenticated_client.dart';
import 'package:ai_speaking_flutter_app/core/auth/installation_credential_store.dart';
import 'package:ai_speaking_flutter_app/core/auth/installation_credentials.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final config = AppConfig(
    backendBaseUri: Uri.parse('https://backend.example'),
    useDemoBackend: false,
    childAge: 6,
  );

  test('registers once and attaches the installation access token', () async {
    final store = _MemoryCredentialStore();
    var registrationCount = 0;
    final authTransport = MockClient((request) async {
      expect(request.url.path, '/api/installations/register');
      registrationCount += 1;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['clientId'], 'android_test-installation');
      expect(body['platform'], 'android');
      expect((body['installationSecret'] as String).length, greaterThan(32));
      return http.Response(
        jsonEncode(_sessionResponse('access-1', 'refresh-1')),
        201,
      );
    });
    final session = InstallationAuthSession(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      store: store,
      transport: authTransport,
    );
    final apiClient = InstallationAuthenticatedClient(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      session: session,
      inner: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer access-1');
        return http.Response('{}', 200);
      }),
    );

    await apiClient.ensureAuthenticated();
    await apiClient.get(config.resolve('/api/history'));
    await apiClient.get(config.resolve('/api/history'));

    expect(registrationCount, 1);
    expect(store.value?.refreshToken, 'refresh-1');
  });

  test('does not overwrite a scoped audio upload token', () async {
    final session = InstallationAuthSession(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      store: _MemoryCredentialStore(),
      transport: MockClient((_) async {
        fail('installation registration must not run for scoped requests');
      }),
    );
    final client = InstallationAuthenticatedClient(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      session: session,
      inner: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer scoped-audio-token');
        return http.Response('{}', 200);
      }),
    );
    final request = http.Request(
      'POST',
      config.resolve('/api/audio-sessions/audio_v2-test/chunks'),
    )..headers['authorization'] = 'Bearer scoped-audio-token';

    await client.send(request);
  });

  test(
    'rotates the public client id after a stale registration conflict',
    () async {
      var clientId = 'android_legacy-installation';
      var attempts = 0;
      final session = InstallationAuthSession(
        config: config,
        clientIdProvider: () async => clientId,
        clientIdResetter: () async {
          clientId = 'android_rotated-installation';
        },
        store: _MemoryCredentialStore(),
        transport: MockClient((request) async {
          attempts += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['clientId'] == 'android_legacy-installation') {
            return http.Response(
              jsonEncode(<String, Object>{
                'error': <String, Object>{
                  'code': 'INSTALLATION_ALREADY_REGISTERED',
                  'message': 'Installation đã thuộc credential khác.',
                },
              }),
              409,
              headers: const <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          expect(body['clientId'], 'android_rotated-installation');
          return http.Response(
            jsonEncode(_sessionResponse('access-rotated', 'refresh-rotated')),
            201,
          );
        }),
      );

      expect(await session.accessToken(), 'access-rotated');
      expect(attempts, 3);
    },
  );

  test(
    'uses a token close to expiry at once and refreshes it in the background',
    () async {
      final store = _MemoryCredentialStore()
        ..value = _storedCredentials(
          accessToken: 'access-old',
          accessExpiresIn: const Duration(minutes: 2),
        );
      final refreshCompleter = Completer<http.Response>();
      var refreshCount = 0;
      final session = InstallationAuthSession(
        config: config,
        clientIdProvider: () async => 'android_test-installation',
        store: store,
        transport: MockClient((request) {
          expect(request.url.path, '/api/installations/refresh');
          expect(jsonDecode(request.body)['refreshToken'], 'refresh-old');
          refreshCount += 1;
          return refreshCompleter.future;
        }),
      );

      // The request does not wait for the refresh it started.
      expect(await session.accessToken(), 'access-old');
      expect(await session.accessToken(), 'access-old');
      refreshCompleter.complete(
        http.Response(
          jsonEncode(_sessionResponse('access-new', 'refresh-new')),
          200,
        ),
      );
      await session.backgroundRefreshDone;

      expect(await session.accessToken(), 'access-new');
      expect(refreshCount, 1);
      expect(store.value?.refreshToken, 'refresh-new');
    },
  );

  test('does not refresh a token far from expiry', () async {
    final session = InstallationAuthSession(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      store: _MemoryCredentialStore()
        ..value = _storedCredentials(
          accessToken: 'access-fresh',
          accessExpiresIn: const Duration(minutes: 10),
        ),
      transport: MockClient((_) async => fail('no refresh expected')),
    );

    expect(await session.accessToken(), 'access-fresh');
    await session.backgroundRefreshDone;
  });

  test(
    'resends a multipart upload once with a new token after a 401',
    () async {
      final session = InstallationAuthSession(
        config: config,
        clientIdProvider: () async => 'android_test-installation',
        store: _MemoryCredentialStore()
          ..value = _storedCredentials(
            accessToken: 'access-revoked',
            accessExpiresIn: const Duration(minutes: 10),
          ),
        transport: MockClient((request) async {
          expect(request.url.path, '/api/installations/refresh');
          return http.Response(
            jsonEncode(_sessionResponse('access-new', 'refresh-new')),
            200,
          );
        }),
      );
      final authorizations = <String?>[];
      final bodies = <String>[];
      final client = InstallationAuthenticatedClient(
        config: config,
        clientIdProvider: () async => 'android_test-installation',
        session: session,
        inner: MockClient((request) async {
          authorizations.add(request.headers['authorization']);
          bodies.add(request.body);
          return request.headers['authorization'] == 'Bearer access-new'
              ? http.Response('{"ok":true}', 200)
              : http.Response('{}', 401);
        }),
      );
      final upload =
          http.MultipartRequest('POST', config.resolve('/api/audio/translate'))
            ..fields['sourceLanguage'] = 'vi'
            ..files.add(
              http.MultipartFile.fromBytes('audio', [
                1,
                2,
                3,
              ], filename: 'a.m4a'),
            );

      final response = await http.Response.fromStream(
        await client.send(upload),
      );

      expect(response.statusCode, 200);
      expect(authorizations, ['Bearer access-revoked', 'Bearer access-new']);
      expect(bodies[1], bodies[0]);
      expect(bodies[0], contains('name="sourceLanguage"'));
    },
  );

  test('returns the 401 when the resend is still unauthorized', () async {
    final session = InstallationAuthSession(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      store: _MemoryCredentialStore()
        ..value = _storedCredentials(
          accessToken: 'access-old',
          accessExpiresIn: const Duration(minutes: 10),
        ),
      transport: MockClient(
        (_) async => http.Response(
          jsonEncode(_sessionResponse('access-new', 'refresh-new')),
          200,
        ),
      ),
    );
    var calls = 0;
    final client = InstallationAuthenticatedClient(
      config: config,
      clientIdProvider: () async => 'android_test-installation',
      session: session,
      inner: MockClient((_) async {
        calls += 1;
        return http.Response('{}', 401);
      }),
    );

    final response = await client.get(config.resolve('/api/history'));

    expect(response.statusCode, 401);
    expect(calls, 2);
  });
}

InstallationCredentials _storedCredentials({
  required String accessToken,
  required Duration accessExpiresIn,
}) => InstallationCredentials(
  clientId: 'android_test-installation',
  installationSecret: 'a' * 48,
  accessToken: accessToken,
  accessTokenExpiresAt: DateTime.now().toUtc().add(accessExpiresIn),
  refreshToken: 'refresh-old',
  refreshTokenExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
);

Map<String, Object> _sessionResponse(String access, String refresh) =>
    <String, Object>{
      'accessToken': access,
      'accessTokenExpiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
      'refreshToken': refresh,
      'refreshTokenExpiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
    };

class _MemoryCredentialStore extends InstallationCredentialStore {
  InstallationCredentials? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<InstallationCredentials?> read() async => value;

  @override
  Future<void> write(InstallationCredentials credentials) async {
    value = credentials;
  }
}
