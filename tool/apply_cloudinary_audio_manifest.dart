import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final manifestPath = arguments.isEmpty
      ? 'assets/data/cloudinary_audio_manifest.json'
      : arguments.first;
  final manifest = jsonDecode(await File(manifestPath).readAsString());
  if (manifest is! Map<String, dynamic> || manifest['assets'] is! Map) {
    throw const FormatException('Invalid Cloudinary audio manifest.');
  }

  final urls = <String, String>{};
  for (final entry in (manifest['assets'] as Map).entries) {
    final value = entry.value;
    if (entry.key is String && value is Map && value['secureUrl'] is String) {
      urls[entry.key as String] = value['secureUrl'] as String;
    }
  }

  final dataDirectory = Directory('assets/data');
  final dataFiles =
      dataDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .where((file) => _normalized(file.path) != _normalized(manifestPath))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  var changedFiles = 0;
  var replacedUris = 0;
  var addedUrls = 0;
  for (final file in dataFiles) {
    final decoded = jsonDecode(await file.readAsString());
    var fileChanged = false;

    Object? visit(Object? value) {
      if (value is String) {
        final assetPath = _assetPathFromUri(value);
        if (assetPath == null) return value;
        final remoteUrl = urls[assetPath];
        if (remoteUrl == null) {
          throw StateError('${file.path}: no uploaded URL for $assetPath');
        }
        fileChanged = true;
        replacedUris++;
        return remoteUrl;
      }
      if (value is List) {
        for (var index = 0; index < value.length; index++) {
          value[index] = visit(value[index]);
        }
        return value;
      }
      if (value is Map<String, dynamic>) {
        final asset = value['asset'];
        if (asset is String && asset.startsWith('assets/audio/')) {
          final remoteUrl = urls[asset];
          if (remoteUrl == null) {
            throw StateError('${file.path}: no uploaded URL for $asset');
          }
          if (value['url'] != remoteUrl) {
            value['url'] = remoteUrl;
            fileChanged = true;
            addedUrls++;
          }
        }
        for (final key in value.keys.toList(growable: false)) {
          value[key] = visit(value[key]);
        }
        return value;
      }
      return value;
    }

    final updated = visit(decoded);
    if (fileChanged) {
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
        flush: true,
      );
      changedFiles++;
    }
  }

  stdout.writeln(
    'Updated $changedFiles JSON files: $replacedUris audio URIs replaced, '
    '$addedUrls prompt URLs added.',
  );
}

String? _assetPathFromUri(String value) {
  const prefixes = <String>[
    'asset:///assets/audio/',
    'asset:/assets/audio/',
    'asset:assets/audio/',
  ];
  for (final prefix in prefixes) {
    if (value.startsWith(prefix)) {
      return 'assets/audio/${value.substring(prefix.length)}';
    }
  }
  return null;
}

String _normalized(String value) =>
    File(value).absolute.path.replaceAll('\\', '/').toLowerCase();
