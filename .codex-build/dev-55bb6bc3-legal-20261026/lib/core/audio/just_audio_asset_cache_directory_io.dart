import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Ensures just_audio can safely enumerate its asset cache on a fresh install.
Future<void> ensureJustAudioAssetCacheDirectory() async {
  final temporaryDirectory = await getTemporaryDirectory();
  final assetCacheDirectory = Directory(
    '${temporaryDirectory.path}${Platform.pathSeparator}just_audio_cache',
  );
  await assetCacheDirectory.create(recursive: true);
}
