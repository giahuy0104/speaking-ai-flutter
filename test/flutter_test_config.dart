import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/homi_hero_3d.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // HOMI's endless idle motion would keep pumpAndSettle from settling, and
  // resized decoding finishes outside the fake clock (goldens miss images).
  HomiHero3D.motionEnabled = false;
  HomiHero3D.decodeAtDisplaySize = false;
  final comparator = goldenFileComparator;
  if (Platform.isWindows && comparator is LocalFileComparator) {
    goldenFileComparator = _WindowsGoldenFileComparator(comparator);
  }
  await testMain();
}

// Skia rasterizes text and icons differently on Windows. Keep exact pixel
// comparisons by using a Windows baseline instead of weakening the matcher.
class _WindowsGoldenFileComparator extends GoldenFileComparator {
  _WindowsGoldenFileComparator(this._local);

  final LocalFileComparator _local;

  Uri _windowsKey(Uri golden) {
    final segments = golden.pathSegments;
    if (segments.isEmpty || segments.first != 'goldens') return golden;
    return Uri(
      pathSegments: <String>['goldens', 'windows', ...segments.skip(1)],
    );
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) =>
      _local.compare(imageBytes, _windowsKey(golden));

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      _local.update(_windowsKey(golden), imageBytes);
}
