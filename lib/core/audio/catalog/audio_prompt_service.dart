import 'dart:async';
import 'dart:typed_data';

import '../audio_diagnostics.dart';
import 'audio_prompt_request.dart';
import 'audio_prompt_resolver.dart';

typedef AuthoredAudioPlayer =
    Future<void> Function(Uint8List bytes, AudioPromptRequest request);
typedef TtsPromptPlayer = Future<void> Function(AudioPromptRequest request);
typedef AudioStopper = Future<void> Function();
typedef RouteLossClassifier = bool Function(Object error);

final class AudioPromptService {
  AudioPromptService({
    required this.resolver,
    required AuthoredAudioPlayer playAuthored,
    required TtsPromptPlayer playTts,
    required AudioStopper stopPlayback,
    RouteLossClassifier? isRouteLoss,
  }) : _playAuthored = playAuthored,
       _playTts = playTts,
       _stopPlayback = stopPlayback,
       _isRouteLoss = isRouteLoss ?? ((_) => false);

  final AudioPromptResolver resolver;
  final AuthoredAudioPlayer _playAuthored;
  final TtsPromptPlayer _playTts;
  final AudioStopper _stopPlayback;
  final RouteLossClassifier _isRouteLoss;
  Future<void> _playQueue = Future<void>.value();
  int _stopGeneration = 0;
  Completer<void>? _activeCancellation;

  Future<AudioPromptSource> play(AudioPromptRequest request) {
    final stopGeneration = _stopGeneration;
    final previous = _playQueue;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed prompt must not poison later queued prompts.
      }
      if (stopGeneration != _stopGeneration) {
        return AudioPromptSource.unavailable;
      }
      return _playQueued(request, stopGeneration);
    }();
    _playQueue = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<AudioPromptSource> _playQueued(
    AudioPromptRequest request,
    int stopGeneration,
  ) async {
    final cancellation = Completer<void>();
    _activeCancellation = cancellation;
    final diagnosticFields = <String, Object?>{
      'key': request.key.value,
      'locale': request.locale,
    };
    AudioDiagnostics.event('registry.prompt.start', diagnosticFields);
    try {
      final resolution = await _untilCancelled(
        resolver.resolve(request),
        cancellation,
        request.timeout,
      );
      if (stopGeneration != _stopGeneration) {
        return AudioPromptSource.unavailable;
      }
      AudioDiagnostics.event('registry.prompt.resolved', {
        ...diagnosticFields,
        'source': resolution.source.name,
      });

      if (resolution.bytes != null) {
        try {
          await _untilCancelled(
            _playAuthored(resolution.bytes!, request),
            cancellation,
            _authoredPlaybackTimeout(request, resolution),
          );
          AudioDiagnostics.event('registry.prompt.authored.completed', {
            ...diagnosticFields,
            'source': resolution.source.name,
          });
          return stopGeneration == _stopGeneration
              ? resolution.source
              : AudioPromptSource.unavailable;
        } on _AudioPromptCancelled {
          return AudioPromptSource.unavailable;
        } catch (error) {
          if (_isRouteLoss(error)) rethrow;
          if (stopGeneration != _stopGeneration || !request.allowTtsFallback) {
            return AudioPromptSource.unavailable;
          }
          // A native decoder/timeout may leave MediaPlayer active. Finish that
          // exact attempt before TTS starts, otherwise TTS releases it midway
          // and sounds like an unexplained authored-audio cut-off.
          await _stopPlayback();
          AudioDiagnostics.event('registry.prompt.authored.fallback', {
            ...diagnosticFields,
            'reason': error.runtimeType.toString(),
          });
        }
      } else if (resolution.source == AudioPromptSource.unavailable) {
        return AudioPromptSource.unavailable;
      }

      if (stopGeneration != _stopGeneration) {
        return AudioPromptSource.unavailable;
      }
      AudioDiagnostics.event('registry.prompt.tts.start', diagnosticFields);
      await _untilCancelled(_playTts(request), cancellation, request.timeout);
      AudioDiagnostics.event('registry.prompt.tts.completed', diagnosticFields);
      return stopGeneration == _stopGeneration
          ? AudioPromptSource.tts
          : AudioPromptSource.unavailable;
    } on _AudioPromptCancelled {
      return AudioPromptSource.unavailable;
    } finally {
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
    }
  }

  Future<Duration?> budget(AudioPromptRequest request) =>
      resolver.budget(request);

  Future<void> stop() async {
    _stopGeneration += 1;
    _cancelActiveRequest();
    await _stopPlayback();
  }

  Duration _authoredPlaybackTimeout(
    AudioPromptRequest request,
    AudioPromptResolution resolution,
  ) {
    final expectedMilliseconds =
        ((resolution.prompt?.durationSeconds ?? 0) * 1000).ceil() + 5000;
    final expected = Duration(milliseconds: expectedMilliseconds);
    return expected > request.timeout ? expected : request.timeout;
  }

  Future<T> _untilCancelled<T>(
    Future<T> operation,
    Completer<void> cancellation,
    Duration timeout,
  ) => Future.any<T>(<Future<T>>[
    operation,
    cancellation.future.then<T>((_) => throw const _AudioPromptCancelled()),
  ]).timeout(timeout);

  void _cancelActiveRequest() {
    final cancellation = _activeCancellation;
    _activeCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }
}

final class _AudioPromptCancelled implements Exception {
  const _AudioPromptCancelled();
}
