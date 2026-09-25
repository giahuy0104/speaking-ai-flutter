import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'resolves readable retained recordings immediately before playback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lesson-recording-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}${Platform.pathSeparator}attempt.wav',
      ).writeAsBytes(const <int>[1, 2, 3]);

      expect(await findLessonRecording(file.path), file.path);
      expect(lessonRecordingUri(file.path).scheme, 'file');
      expect(
        lessonRecordingUri(file.path).toFilePath(windows: Platform.isWindows),
        file.path,
      );
    },
  );

  test('rejects a missing retained recording', () async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'missing-${DateTime.now().microsecondsSinceEpoch}.m4a';

    expect(await findLessonRecording(path), isNull);
  });

  test('normalizes Windows, Android and iOS recording references', () {
    final windows = lessonRecordingUri(r'C:\recordings\child.wav');
    final android = lessonRecordingUri('/data/user/0/app/child.wav');
    final ios = lessonRecordingUri('/var/mobile/app/child.normalized.wav');

    expect(windows.scheme, 'file');
    expect(windows.toFilePath(windows: true), r'C:\recordings\child.wav');
    expect(android.path, '/data/user/0/app/child.wav');
    expect(ios.path, '/var/mobile/app/child.normalized.wav');
  });
}
