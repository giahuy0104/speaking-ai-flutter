/// Flutter Web relies on the browser HTTP cache. Generated audio URLs are
/// immutable and include the content hash, so a second playback is served by
/// the browser without maintaining a duplicate Dart-side file cache.
class DeviceAudioCache {
  DeviceAudioCache({this.maxFiles = 256, this.maxBytes = 64 * 1024 * 1024});

  final int maxFiles;
  final int maxBytes;

  Future<Uri> resolve(Uri remoteUri) async => remoteUri;

  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async => remoteUri;

  Future<Uri?> cache(Uri remoteUri) async => remoteUri;

  Future<Uri?> cacheVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    int maximumFileBytes = 2 * 1024 * 1024,
  }) async => remoteUri;

  Future<Uri> resolveVerified(
    Uri remoteUri, {
    required String sha256Checksum,
  }) async => remoteUri;

  Future<Uri> resolveAfterPreloadVerified(
    Uri remoteUri, {
    required String sha256Checksum,
    Duration maxWait = const Duration(milliseconds: 500),
  }) async => remoteUri;

  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {}

  Future<void> evict(Uri remoteUri) async {}

  void dispose() {}
}
