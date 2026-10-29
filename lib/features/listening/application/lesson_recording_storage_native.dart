import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nnnoiseless/flutter_nnnoiseless.dart';
import 'package:path_provider/path_provider.dart';

import 'lesson_wav_normalizer.dart';

const MethodChannel _iosLessonRecordingChannel = MethodChannel(
  'ailingo_voice_prompt',
);
const double _replayNoiseSuppressionWet = 0.8;
final Map<String, Future<String>> _pendingReplayDenoising = {};

bool isLocalLessonRecordingFile(String path) => File(path).existsSync();

String _replayDenoisedPath(String path) =>
    '${path.replaceFirst(RegExp(r'\.[^./\\]+$'), '')}.replay-cleaned.wav';

Future<String> prepareLessonRecordingForReplay(String path) async {
  final pending = _pendingReplayDenoising.putIfAbsent(
    path,
    () => _prepareLessonRecordingForReplay(path),
  );
  try {
    return await pending;
  } finally {
    if (identical(_pendingReplayDenoising[path], pending)) {
      _pendingReplayDenoising.remove(path);
    }
  }
}

Future<String> _prepareLessonRecordingForReplay(String path) async {
  final source = File(path);
  if (!await source.exists()) throw StateError('Recording is missing.');
  final output = File(_replayDenoisedPath(path));
  final sourceModified = await source.lastModified();
  if (await output.exists() &&
      await output.length() > 44 &&
      !(await output.lastModified()).isBefore(sourceModified)) {
    debugPrint('Lesson replay denoise cache hit');
    return output.path;
  }

  final staging = File(
    '${output.path.substring(0, output.path.length - 4)}.'
    '${DateTime.now().microsecondsSinceEpoch}.tmp.wav',
  );
  final timer = Stopwatch()..start();
  try {
    await Noiseless.instance.denoiseFile(
      inputPathStr: path,
      outputPathStr: staging.path,
      wet: _replayNoiseSuppressionWet,
    );
    if (!await staging.exists() || await staging.length() <= 44) {
      throw StateError('Denoiser produced no playable WAV.');
    }
    if (await output.exists()) await output.delete();
    await staging.rename(output.path);
    debugPrint(
      'Lesson replay denoise complete: ${timer.elapsedMilliseconds} ms',
    );
    return output.path;
  } finally {
    if (await staging.exists()) await staging.delete();
  }
}

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

Future<String?> retainStarRecording(String path) async {
  final source = File(path);
  if (!await source.exists()) return null;
  final extensionStart = path.lastIndexOf('.');
  final retainedPath = extensionStart < 0
      ? '$path.star'
      : '${path.substring(0, extensionStart)}.star${path.substring(extensionStart)}';
  if (path != retainedPath) {
    await source.copy(retainedPath);
  }
  return retainedPath;
}

Future<void> deleteLessonRecording(String path) async {
  final pending = _pendingReplayDenoising[path];
  if (pending != null) {
    try {
      await pending;
    } catch (_) {
      // Delete both paths even if denoising failed.
    }
  }
  final replayFile = File(_replayDenoisedPath(path));
  if (await replayFile.exists()) await replayFile.delete();
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<String?> resolveLessonRecording(
  String? recordedPath,
  String expectedPath, {
  bool requireNormalization = false,
}) async {
  final path = recordedPath ?? expectedPath;
  final recording = File(path);
  if (!await recording.exists()) return null;
  if (defaultTargetPlatform == TargetPlatform.android &&
      path.toLowerCase().endsWith('.wav')) {
    final original = await recording.readAsBytes();
    final normalized = trimLessonWavSilence(
      normalizeLessonWavLoudness(normalizeAndroidLessonWav(original)),
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
      if (requireNormalization) {
        throw StateError('Native normalization returned no usable recording.');
      }
    } on MissingPluginException {
      if (requireNormalization) rethrow;
      // Unit tests and older native shells do not expose the normalizer. Keep
      // the valid original recording instead of making capture unusable.
    } on PlatformException catch (error) {
      if (requireNormalization) rethrow;
      debugPrint('iOS lesson recording normalization skipped: $error');
    }
  }
  return path;
}
