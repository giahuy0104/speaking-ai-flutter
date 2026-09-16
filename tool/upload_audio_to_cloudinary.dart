import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _audioExtensions = <String>{'.mp3', '.wav', '.m4a', '.aac', '.ogg'};

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final credentials = _Credentials.fromFile(options.credentialsFile);
  final audioDirectory = Directory(options.audioDirectory);
  if (!audioDirectory.existsSync()) {
    stderr.writeln('Audio directory not found: ${audioDirectory.path}');
    exitCode = 2;
    return;
  }

  final files =
      audioDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _audioExtensions.contains(_extension(file.path)))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  final manifestFile = File(options.manifestFile);
  final entries = await _readExistingEntries(manifestFile);
  final startedAt = DateTime.now().toUtc();
  var nextIndex = 0;
  var uploaded = 0;
  var skipped = 0;
  var failed = 0;
  var completedSinceCheckpoint = 0;
  final failures = <String>[];

  stdout.writeln(
    'Uploading ${files.length} audio files to Cloudinary '
    '(concurrency ${options.concurrency}).',
  );

  Future<void> checkpoint() async {
    await _writeManifest(
      manifestFile: manifestFile,
      cloudName: credentials.cloudName,
      remotePrefix: options.remotePrefix,
      entries: entries,
      generatedAt: DateTime.now().toUtc(),
    );
    completedSinceCheckpoint = 0;
  }

  Future<void> worker() async {
    final client = http.Client();
    try {
      while (true) {
        final index = nextIndex++;
        if (index >= files.length) return;
        final file = files[index];
        final assetPath = _assetPath(file, audioDirectory);
        final bytes = await file.readAsBytes();
        final digest = sha256.convert(bytes).toString();
        final previous = entries[assetPath];
        if (previous is Map<String, dynamic> &&
            previous['sha256'] == digest &&
            previous['secureUrl'] is String &&
            (previous['secureUrl'] as String).isNotEmpty) {
          skipped++;
        } else {
          try {
            final entry = await _upload(
              client: client,
              credentials: credentials,
              file: file,
              bytes: bytes,
              assetPath: assetPath,
              sha256Digest: digest,
              remotePrefix: options.remotePrefix,
            );
            entries[assetPath] = entry;
            uploaded++;
          } catch (error) {
            failed++;
            failures.add('$assetPath: $error');
            stderr.writeln('FAILED $assetPath: $error');
          }
        }

        completedSinceCheckpoint++;
        final completed = uploaded + skipped + failed;
        if (completedSinceCheckpoint >= 25 || completed == files.length) {
          await checkpoint();
        }
        if (completed % 50 == 0 || completed == files.length) {
          stdout.writeln(
            'Progress $completed/${files.length} '
            '(uploaded $uploaded, resumed $skipped, failed $failed)',
          );
        }
      }
    } finally {
      client.close();
    }
  }

  await Future.wait(List.generate(options.concurrency, (_) => worker()));
  await checkpoint();

  final elapsed = DateTime.now().toUtc().difference(startedAt);
  stdout.writeln(
    'Finished in ${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s: '
    '$uploaded uploaded, $skipped resumed, $failed failed.',
  );
  if (failures.isNotEmpty) {
    final failureFile = File('${options.manifestFile}.failures.txt');
    await failureFile.writeAsString('${failures.join('\n')}\n', flush: true);
    stderr.writeln('Failure details: ${failureFile.path}');
    exitCode = 1;
  }
}

Future<Map<String, dynamic>> _upload({
  required http.Client client,
  required _Credentials credentials,
  required File file,
  required List<int> bytes,
  required String assetPath,
  required String sha256Digest,
  required String remotePrefix,
}) async {
  final relative = assetPath.substring('assets/audio/'.length);
  final extension = _extension(relative);
  final withoutExtension = relative.substring(
    0,
    relative.length - extension.length,
  );
  final publicId = '$remotePrefix/$withoutExtension';
  final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final parameters = <String, String>{
    'invalidate': 'true',
    'overwrite': 'true',
    'public_id': publicId,
    'tags': 'homi-audio',
    'timestamp': '$timestamp',
  };
  final stringToSign = parameters.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('&');
  final signature = sha1
      .convert(utf8.encode('$stringToSign${credentials.apiSecret}'))
      .toString();
  final endpoint = Uri.https(
    'api.cloudinary.com',
    '/v1_1/${credentials.cloudName}/video/upload',
  );
  final request = http.MultipartRequest('POST', endpoint)
    ..fields.addAll(parameters)
    ..fields['api_key'] = credentials.apiKey
    ..fields['signature'] = signature
    ..files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.uri.pathSegments.last,
      ),
    );
  final streamed = await client
      .send(request)
      .timeout(const Duration(minutes: 3));
  final response = await http.Response.fromStream(streamed);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    var message = response.body;
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message =
          (decoded['error'] as Map<String, dynamic>?)?['message'] as String? ??
          response.body;
    } catch (_) {}
    throw HttpException('Cloudinary ${response.statusCode}: $message');
  }
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final secureUrl = decoded['secure_url'] as String?;
  if (secureUrl == null || !secureUrl.startsWith('https://')) {
    throw const FormatException('Cloudinary response has no secure_url.');
  }
  return <String, dynamic>{
    'secureUrl': secureUrl,
    'publicId': decoded['public_id'],
    'version': decoded['version'],
    'bytes': decoded['bytes'] ?? bytes.length,
    'durationSeconds': decoded['duration'],
    'format': decoded['format'],
    'sha256': sha256Digest,
  };
}

Future<Map<String, dynamic>> _readExistingEntries(File manifestFile) async {
  if (!manifestFile.existsSync()) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is Map<String, dynamic> && decoded['assets'] is Map) {
      return Map<String, dynamic>.from(decoded['assets'] as Map);
    }
  } catch (_) {}
  return <String, dynamic>{};
}

Future<void> _writeManifest({
  required File manifestFile,
  required String cloudName,
  required String remotePrefix,
  required Map<String, dynamic> entries,
  required DateTime generatedAt,
}) async {
  await manifestFile.parent.create(recursive: true);
  final ordered = Map<String, dynamic>.fromEntries(
    entries.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key)),
  );
  final manifest = <String, dynamic>{
    'schemaVersion': 1,
    'provider': 'cloudinary',
    'cloudName': cloudName,
    'resourceType': 'video',
    'remotePrefix': remotePrefix,
    'generatedAt': generatedAt.toIso8601String(),
    'assets': ordered,
  };
  final temporary = File('${manifestFile.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    flush: true,
  );
  if (manifestFile.existsSync()) await manifestFile.delete();
  await temporary.rename(manifestFile.path);
}

String _assetPath(File file, Directory audioDirectory) {
  final root = audioDirectory.absolute.path.replaceAll('\\', '/');
  final fullPath = file.absolute.path.replaceAll('\\', '/');
  final relative = fullPath.substring(root.length + 1);
  return 'assets/audio/$relative';
}

String _extension(String path) {
  final normalized = path.toLowerCase();
  final slash = normalized.lastIndexOf(RegExp(r'[/\\]'));
  final dot = normalized.lastIndexOf('.');
  return dot > slash ? normalized.substring(dot) : '';
}

class _Credentials {
  const _Credentials({
    required this.cloudName,
    required this.apiKey,
    required this.apiSecret,
  });

  factory _Credentials.fromFile(String path) {
    final values = <String, String>{};
    for (final line in File(path).readAsLinesSync()) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      final key = line
          .substring(0, separator)
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z]'), '');
      final value = line.substring(separator + 1).trim();
      if (value.isNotEmpty) values[key] = value;
    }
    final cloudName = values['cloudname'];
    final apiKey = values['apikey'];
    final apiSecret = values['apisecret'];
    if (cloudName == null || apiKey == null || apiSecret == null) {
      throw const FormatException(
        'Credentials file must contain Cloud name, API Key, and API Secret.',
      );
    }
    return _Credentials(
      cloudName: cloudName,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
  }

  final String cloudName;
  final String apiKey;
  final String apiSecret;
}

class _Options {
  const _Options({
    required this.credentialsFile,
    required this.audioDirectory,
    required this.manifestFile,
    required this.remotePrefix,
    required this.concurrency,
  });

  factory _Options.parse(List<String> arguments) {
    final values = <String, String>{};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!argument.startsWith('--') || index + 1 >= arguments.length) {
        throw FormatException('Expected --name value, got: $argument');
      }
      values[argument.substring(2)] = arguments[++index];
    }
    final concurrency = int.tryParse(values['concurrency'] ?? '6') ?? 6;
    return _Options(
      credentialsFile: values['credentials'] ?? 'cloudinary.txt',
      audioDirectory: values['audio-dir'] ?? 'assets/audio',
      manifestFile:
          values['manifest'] ?? 'assets/data/cloudinary_audio_manifest.json',
      remotePrefix: values['remote-prefix'] ?? 'homi/audio',
      concurrency: concurrency.clamp(1, 12),
    );
  }

  final String credentialsFile;
  final String audioDirectory;
  final String manifestFile;
  final String remotePrefix;
  final int concurrency;
}
