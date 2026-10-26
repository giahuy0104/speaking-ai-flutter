import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_pack_cache_base.dart';

AudioPackCache createAudioPackCache() => NativeAudioPackCache();

final class NativeAudioPackCache implements AudioPackCache {
  NativeAudioPackCache({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<Directory>? _root;

  @override
  Future<Uint8List?> readVerified({
    required String pack,
    required String sha256,
    required int maximumBytes,
  }) async {
    _validateIdentity(pack);
    final object = File(
      '${(await _objects()).path}${Platform.pathSeparator}$sha256.mp3',
    );
    final objectBytes = await _readValid(object, sha256, maximumBytes);
    if (objectBytes != null) return objectBytes;
    final active = Directory(
      '${(await _active()).path}${Platform.pathSeparator}$pack',
    );
    return _readValid(
      File('${active.path}${Platform.pathSeparator}$sha256.mp3'),
      sha256,
      maximumBytes,
    );
  }

  @override
  Future<void> putVerified({
    required String pack,
    required String sha256,
    required Uint8List bytes,
    required int maximumBytes,
  }) async {
    _validateIdentity(pack);
    _verify(bytes, sha256, maximumBytes);
    final target = File(
      '${(await _objects()).path}${Platform.pathSeparator}$sha256.mp3',
    );
    if (await _readValid(target, sha256, maximumBytes) != null) return;
    await _writeStagedFile(target, bytes);
  }

  @override
  Future<void> beginStaging(String pack, String version) async {
    final directory = await _staging(pack, version);
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  @override
  Future<void> stageVerified({
    required String pack,
    required String version,
    required String sha256,
    required Uint8List bytes,
    required int maximumBytes,
  }) async {
    _verify(bytes, sha256, maximumBytes);
    final directory = await _staging(pack, version);
    if (!await directory.exists()) {
      throw StateError('Audio pack staging is not open.');
    }
    await _writeStagedFile(
      File('${directory.path}${Platform.pathSeparator}$sha256.mp3'),
      bytes,
    );
  }

  @override
  Future<void> activateStaged({
    required String pack,
    required String version,
    required Set<String> requiredChecksums,
  }) async {
    final staged = await _staging(pack, version);
    for (final checksum in requiredChecksums) {
      final file = File('${staged.path}${Platform.pathSeparator}$checksum.mp3');
      if (!await file.exists()) {
        throw StateError('Audio pack staging is incomplete.');
      }
    }
    final active = Directory(
      '${(await _active()).path}${Platform.pathSeparator}$pack',
    );
    final rollback = Directory(
      '${(await _rollback()).path}${Platform.pathSeparator}$pack',
    );
    if (await rollback.exists()) await rollback.delete(recursive: true);
    var movedActive = false;
    try {
      if (await active.exists()) {
        await active.rename(rollback.path);
        movedActive = true;
      }
      await staged.rename(active.path);
    } catch (_) {
      if (!await active.exists() && movedActive && await rollback.exists()) {
        await rollback.rename(active.path);
      }
      rethrow;
    }
  }

  @override
  Future<void> discardStaging(String pack, String version) async {
    final staged = await _staging(pack, version);
    if (await staged.exists()) await staged.delete(recursive: true);
  }

  @override
  Future<bool> rollback(String pack) async {
    _validateIdentity(pack);
    final active = Directory(
      '${(await _active()).path}${Platform.pathSeparator}$pack',
    );
    final previous = Directory(
      '${(await _rollback()).path}${Platform.pathSeparator}$pack',
    );
    if (!await previous.exists()) return false;
    final failed = Directory('${active.path}.failed');
    if (await failed.exists()) await failed.delete(recursive: true);
    if (await active.exists()) await active.rename(failed.path);
    try {
      await previous.rename(active.path);
      if (await failed.exists()) await failed.delete(recursive: true);
      return true;
    } catch (_) {
      if (!await active.exists() && await failed.exists()) {
        await failed.rename(active.path);
      }
      rethrow;
    }
  }

  @override
  Future<int> pruneObjects({
    required Set<String> protectedChecksums,
    required int maximumBytes,
  }) async {
    final directory = await _objects();
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.mp3'))
        .cast<File>()
        .toList();
    final entries = await Future.wait(
      files.map(
        (file) async => (
          file: file,
          checksum: file.uri.pathSegments.last.replaceFirst('.mp3', ''),
          bytes: await file.length(),
          modified: await file.lastModified(),
        ),
      ),
    );
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    var total = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    var removed = 0;
    for (final entry in entries) {
      if (total <= maximumBytes) break;
      if (protectedChecksums.contains(entry.checksum)) continue;
      await entry.file.delete();
      total -= entry.bytes;
      removed += 1;
    }
    return removed;
  }

  Future<void> _writeStagedFile(File target, Uint8List bytes) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<Uint8List?> _readValid(
    File file,
    String checksum,
    int maximumBytes,
  ) async {
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (_valid(bytes, checksum, maximumBytes)) {
      await file.setLastModified(DateTime.now());
      return bytes;
    }
    await file.delete();
    return null;
  }

  Future<Directory> _rootDirectory() => _root ??= () async {
    final support = await _directoryProvider();
    return Directory(
      '${support.path}${Platform.pathSeparator}audio_registry',
    ).create(recursive: true);
  }();

  Future<Directory> _objects() async => Directory(
    '${(await _rootDirectory()).path}${Platform.pathSeparator}objects',
  ).create(recursive: true);

  Future<Directory> _active() async => Directory(
    '${(await _rootDirectory()).path}${Platform.pathSeparator}active',
  ).create(recursive: true);

  Future<Directory> _rollback() async => Directory(
    '${(await _rootDirectory()).path}${Platform.pathSeparator}rollback',
  ).create(recursive: true);

  Future<Directory> _staging(String pack, String version) async {
    _validateIdentity(pack);
    _validateIdentity(version);
    final root = await _rootDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}staging${Platform.pathSeparator}$pack-$version',
    );
  }

  static final RegExp _identity = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  static void _validateIdentity(String value) {
    if (!_identity.hasMatch(value)) {
      throw const FormatException('Invalid audio pack path identity.');
    }
  }

  static bool _valid(Uint8List bytes, String checksum, int maximumBytes) =>
      bytes.isNotEmpty &&
      bytes.length <= maximumBytes &&
      sha256.convert(bytes).toString() == checksum;

  static void _verify(Uint8List bytes, String checksum, int maximumBytes) {
    if (!_valid(bytes, checksum, maximumBytes)) {
      throw const FormatException('Cached audio integrity check failed.');
    }
  }
}
