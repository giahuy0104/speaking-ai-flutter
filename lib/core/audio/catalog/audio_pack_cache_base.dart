import 'dart:typed_data';

abstract interface class AudioPackCache {
  Future<Uint8List?> readVerified({
    required String pack,
    required String sha256,
    required int maximumBytes,
  });

  Future<void> putVerified({
    required String pack,
    required String sha256,
    required Uint8List bytes,
    required int maximumBytes,
  });

  Future<void> beginStaging(String pack, String version);

  Future<void> stageVerified({
    required String pack,
    required String version,
    required String sha256,
    required Uint8List bytes,
    required int maximumBytes,
  });

  Future<void> activateStaged({
    required String pack,
    required String version,
    required Set<String> requiredChecksums,
  });

  Future<void> discardStaging(String pack, String version);

  Future<bool> rollback(String pack);

  Future<int> pruneObjects({
    required Set<String> protectedChecksums,
    required int maximumBytes,
  });
}
