import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'lesson_wav_normalizer.dart';

const MethodChannel _iosLessonRecordingChannel = MethodChannel(
  'ailingo_voice_prompt',
);

String lessonRecordingFileExtension({TargetPlatform? platform}) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.android
    ? 'wav'
    : 'm4a';

Future<String> createLessonRecordingPath(
  String lessonId,
  int sentenceNumber, {
  String? extension,
}) async {
  final directory = await getApplicationDocumentsDirectory();
  final recordings = Directory(
    '${directory.path}${Platform.pathSeparator}lesson_recordings',
  );
  await recordings.create(recursive: true);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final resolvedExtension =
      extension?.replaceFirst(RegExp(r'^\.'), '').trim() ??
      lessonRecordingFileExtension();
  return '${recordings.path}${Platform.pathSeparator}'
      '$lessonId-sentence-$sentenceNumber-$timestamp.$resolvedExtension';
}

Future<String?> findLessonRecording(String path) async =>
    await File(path).exists() ? path : null;

Future<void> deleteLessonRecording(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath,
) async {
  final path = recordedPath ?? expectedPath;
  final recording = File(path);
  if (!await recording.exists()) return null;
  if (defaultTargetPlatform == TargetPlatform.android &&
      path.toLowerCase().endsWith('.wav')) {
    final original = await recording.readAsBytes();
    final normalized = normalizeLessonWavLoudness(
      normalizeAndroidLessonWav(original),
    );
    if (!identical(original, normalized)) {
      // Write and flush a sibling first. A same-directory rename replaces the
      // completed recording atomically; failures leave the original intact.
      final staging = File(
        '$path.mono-${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await staging.writeAsBytes(normalized, flush: true);
        await staging.rename(path);
      } finally {
        if (await staging.exists()) await staging.delete();
      }
      debugPrint(
        'Lesson WAV normalized: sampleRate=16000 channels=2->1 '
        'sourceBytes=${original.length} outputBytes=${normalized.length}',
      );
    }
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      final normalizedPath = await _iosLessonRecordingChannel
          .invokeMethod<String>('normalizeLessonRecording', <String, Object?>{
            'path': path,
          });
      if (normalizedPath != null &&
          normalizedPath.trim().isNotEmpty &&
          await File(normalizedPath).exists()) {
        return normalizedPath;
      }
    } on MissingPluginException {
      // Unit tests and older native shells do not expose the normalizer. Keep
      // the valid original recording instead of making capture unusable.
    } on PlatformException catch (error) {
      debugPrint('iOS lesson recording normalization skipped: $error');
    }
  }
  return path;
}
