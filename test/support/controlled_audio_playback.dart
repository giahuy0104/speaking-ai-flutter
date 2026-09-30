import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

/// Fakes shared by the playback tests: routing and level both need a player
/// whose every call is observable and a cache that resolves on demand.

Future<void> flushMicrotasks() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ControlledCache extends DeviceAudioCache {
  Completer<Uri>? pendingResolve;
  final resolveEntered = Completer<void>();
  int resolveCalls = 0;

  @override
  Future<Uri> resolveAfterPreload(
    Uri uri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async {
    resolveCalls++;
    if (!resolveEntered.isCompleted) resolveEntered.complete();
    return pendingResolve?.future ?? uri;
  }
}

class ControlledPlayer implements AudioPlayer {
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final List<String> playedPaths = <String>[];
  final List<double> volumeChanges = <double>[];
  final List<double> volumesAtPlay = <double>[];
  final List<AndroidAudioAttributes> attributesAtPlay =
      <AndroidAudioAttributes>[];
  final blockedLoadEntered = Completer<void>();
  final speedEntered = Completer<void>();
  Completer<void>? pendingLoad;
  Completer<void>? pendingSpeed;
  AndroidAudioAttributes? attributes;
  String? loadedPath;
  int disposeCalls = 0;
  bool _playing = false;
  double _volume = 1.0;
  ProcessingState _processingState = ProcessingState.ready;
  Duration _position = Duration.zero;

  /// Pushes a player state the way just_audio would, so a test can replay the
  /// exact event order around a completion.
  void emitState({
    required bool playing,
    required ProcessingState processingState,
    Duration position = Duration.zero,
  }) {
    _playing = playing;
    _processingState = processingState;
    _position = position;
    _states.add(PlayerState(playing, processingState));
  }

  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _processingState;
  @override
  Duration get position => _position;
  @override
  Duration? get duration => const Duration(seconds: 2);
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    final pending = pendingLoad;
    if (pending != null) {
      if (!blockedLoadEntered.isCompleted) blockedLoadEntered.complete();
      await pending.future;
    }
    loadedPath = path;
    return duration;
  }

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    bool preload = true,
    Duration? initialPosition,
    dynamic package,
    dynamic tag,
  }) async {
    loadedPath = assetPath;
    return duration;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _position = position ?? Duration.zero;
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!speedEntered.isCompleted) speedEntered.complete();
    await pendingSpeed?.future;
  }

  @override
  Future<void> setAndroidAudioAttributes(AndroidAudioAttributes value) async {
    attributes = value;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumeChanges.add(volume);
  }

  @override
  Future<void> play() async {
    playedPaths.add(loadedPath!);
    volumesAtPlay.add(_volume);
    if (attributes != null) attributesAtPlay.add(attributes!);
    _playing = true;
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _states.close();
    await _positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
