import 'dart:async';

import 'package:flutter/services.dart';

/// Event kinds reported by the native `StreamingAudioBridge` (iOS only).
enum IosStreamingAudioEventType { playing, completed, error }

/// One event parsed from `ailingo_streaming_audio/events`. Pure data class,
/// separated from the channel plumbing so it can be unit tested without a
/// running native side.
class IosStreamingAudioEvent {
  const IosStreamingAudioEvent({
    required this.type,
    this.playing,
    this.errorCode,
    this.errorMessage,
  });

  factory IosStreamingAudioEvent.fromRaw(Object? raw) {
    final values = raw is Map
        ? raw.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final rawType = values['type']?.toString();
    return IosStreamingAudioEvent(
      type: switch (rawType) {
        'playing' => IosStreamingAudioEventType.playing,
        'completed' => IosStreamingAudioEventType.completed,
        _ => IosStreamingAudioEventType.error,
      },
      playing: values['value'] as bool?,
      errorCode: switch (values['code']) {
        final num code => code.toInt(),
        _ => null,
      },
      errorMessage: values['message']?.toString(),
    );
  }

  final IosStreamingAudioEventType type;
  final bool? playing;
  final int? errorCode;
  final String? errorMessage;
}

/// A playback failure reported by the native AVPlayer-backed streaming
/// bridge, carrying the original native error code (e.g. an
/// AVFoundationErrorDomain code on iOS) for diagnostics.
class IosStreamingAudioPlayerException implements Exception {
  const IosStreamingAudioPlayerException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => '($code) $message';
}

/// Thin wrapper over the native `StreamingAudioBridge` (iOS only): plays a
/// network audio clip whose HTTP response has no `Content-Length` and does
/// not support byte-range requests (a TTS clip streamed to the client while
/// still being synthesized), via a custom `AVAssetResourceLoaderDelegate`
/// instead of just_audio's own HTTP loader (which rejects such a response
/// with AVFoundationErrorDomain -11850, "Operation Stopped").
///
/// This bridge does not acquire the iOS playback-priority token itself: the
/// caller (`JustAudioPlaybackService`) already holds one via
/// `ailingo_background_learning`'s `beginAudioPlayback` for the whole
/// duration of any iOS playback, native-stream or not.
class IosStreamingAudioPlayer {
  IosStreamingAudioPlayer({
    MethodChannel methodChannel = const MethodChannel(
      'ailingo_streaming_audio',
    ),
    EventChannel eventChannel = const EventChannel(
      'ailingo_streaming_audio/events',
    ),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<IosStreamingAudioEvent>? _events;

  Stream<IosStreamingAudioEvent> get _rawEvents =>
      _events ??= _eventChannel
          .receiveBroadcastStream()
          .map(IosStreamingAudioEvent.fromRaw)
          .asBroadcastStream();

  Stream<bool> get playingStream => _rawEvents
      .where((event) => event.type == IosStreamingAudioEventType.playing)
      .map((event) => event.playing ?? false);

  Stream<void> get completionStream => _rawEvents
      .where((event) => event.type == IosStreamingAudioEventType.completed)
      .map((_) {});

  Stream<IosStreamingAudioPlayerException> get errorStream => _rawEvents
      .where((event) => event.type == IosStreamingAudioEventType.error)
      .map(
        (event) => IosStreamingAudioPlayerException(
          event.errorCode ?? -1,
          event.errorMessage ?? 'Streaming playback failed',
        ),
      );

  /// Starts playback of [uri] and completes once the native player confirms
  /// it has actually started, or throws [IosStreamingAudioPlayerException]
  /// if it fails before that point. Does not itself impose a timeout; the
  /// caller already bounds this with its own playback-preparation timeout.
  Future<void> play(Uri uri) async {
    final startedOrFailed = Completer<void>();
    final playingSubscription = playingStream.listen((playing) {
      if (playing && !startedOrFailed.isCompleted) {
        startedOrFailed.complete();
      }
    });
    final errorSubscription = errorStream.listen((error) {
      if (!startedOrFailed.isCompleted) {
        startedOrFailed.completeError(error);
      }
    });
    try {
      await _methodChannel.invokeMethod<void>('play', <String, Object>{
        'url': uri.toString(),
      });
      await startedOrFailed.future;
    } finally {
      await playingSubscription.cancel();
      await errorSubscription.cancel();
    }
  }

  Future<void> stop() =>
      _methodChannel.invokeMethod<void>('stop').catchError((Object _) {});

  Future<void> setRate(double rate) => _methodChannel
      .invokeMethod<void>('setRate', <String, Object>{'rate': rate});

  Future<void> setVolume(double volume) => _methodChannel
      .invokeMethod<void>('setVolume', <String, Object>{'volume': volume});
}
