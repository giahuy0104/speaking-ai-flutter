import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional, bounded Android output lease spanning capture finalization/replay.
abstract interface class LessonRecordingHandoff {
  Future<int?> begin();
  Future<void> end(int token);
}

class AndroidLessonRecordingHandoff implements LessonRecordingHandoff {
  const AndroidLessonRecordingHandoff();

  static const _channel = MethodChannel('ailingo_hfp_audio');

  @override
  Future<int?> begin() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    return _channel.invokeMethod<int>('beginLessonAudioHandoff');
  }

  @override
  Future<void> end(int token) => _channel.invokeMethod<void>(
    'endLessonAudioHandoff',
    <String, Object?>{'token': token},
  );
}
