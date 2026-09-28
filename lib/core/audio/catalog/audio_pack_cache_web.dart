import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'audio_pack_cache_base.dart';

AudioPackCache createAudioPackCache() => MemoryAudioPackCache();

final class MemoryAudioPackCache implements AudioPackCache {
  final Map<String, Uint8List> _objects = {};
  final Map<String, Map<String, Uint8List>> _active = {};
  final Map<String, Map<String, Uint8List>> _previous = {};
  final Map<String, Map<String, Uint8List>> _staging = {};

  @override
  Future<Uint8List?> readVerified({
    required String pack,
    required String sha256,
    required int maximumBytes,
  }) async {
    final object = _objects.remove(sha256);
    if (object != null) _objects[sha256] = object;
    final bytes = object ?? _active[pack]?[sha256];
    if (bytes == null || !_valid(bytes, sha256, maximumBytes)) return null;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> putVerified({
    required String pack,
    required String sha256,
    required Uint8List bytes,
    required int maximumBytes,
  }) async {
    _verify(bytes, sha256, maximumBytes);
    _objects.putIfAbsent(sha256, () => Uint8List.fromList(bytes));
  }

  @override
  Future<void> beginStaging(String pack, String version) async {
    _staging[_identity(pack, version)] = {};
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
    final stage = _staging[_identity(pack, version)];
    if (stage == null) throw StateError('Audio pack staging is not open.');
    stage[sha256] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> activateStaged({
    required String pack,
    required String version,
    required Set<String> requiredChecksums,
  }) async {
    final identity = _identity(pack, version);
    final stage = _staging[identity];
    if (stage == null || !stage.keys.toSet().containsAll(requiredChecksums)) {
      throw StateError('Audio pack staging is incomplete.');
    }
    final current = _active[pack];
    if (current != null) _previous[pack] = current;
    _active[pack] = Map<String, Uint8List>.of(stage);
    _staging.remove(identity);
  }

  @override
  Future<void> discardStaging(String pack, String version) async {
    _staging.remove(_identity(pack, version));
  }

  @override
  Future<bool> rollback(String pack) async {
    final previous = _previous.remove(pack);
    if (previous == null) return false;
    _active[pack] = previous;
    return true;
  }

  @override
  Future<int> pruneObjects({
    required Set<String> protectedChecksums,
    required int maximumBytes,
  }) async {
    var total = _objects.values.fold<int>(
      0,
      (sum, bytes) => sum + bytes.length,
    );
    var removed = 0;
    for (final checksum in List<String>.of(_objects.keys)) {
      if (total <= maximumBytes) break;
      if (protectedChecksums.contains(checksum)) continue;
      final bytes = _objects.remove(checksum);
      if (bytes != null) {
        total -= bytes.length;
        removed += 1;
      }
    }
    return removed;
  }

  static String _identity(String pack, String version) => '$pack\u0000$version';

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
