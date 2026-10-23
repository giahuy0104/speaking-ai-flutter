import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/application/lesson_recording_storage_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retained Star recording survives history file eviction', () async {
    final directory = await Directory.systemTemp.createTemp('star-recording-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File(
      '${directory.path}${Platform.pathSeparator}attempt.wav',
    );
    await source.writeAsBytes(<int>[1, 2, 3, 4]);

    final retained = await retainStarRecording(source.path);
    expect(retained, isNotNull);
    expect(retained, endsWith('attempt.star.wav'));
    await deleteLessonRecording(source.path);

    expect(await findLessonRecording(source.path), isNull);
    expect(await File(retained!).readAsBytes(), <int>[1, 2, 3, 4]);
  });
}
