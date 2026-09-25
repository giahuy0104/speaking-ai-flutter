import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_gain.dart';
import 'audio_diagnostics.dart';
import 'audio_turn_coordinator.dart';
import 'browser_audio_playback.dart';
import 'browser_audio_playback_factory.dart';
import 'device_audio_cache.dart';
import 'just_audio_asset_cache_directory.dart';

class PlaybackStartMetrics {
  const PlaybackStartMetrics({
    required this.audioLoadDuration,
    required this.startedAfterRequest,
    required this.fromDeviceCache,
    this.preloadedSourceLoaded = false,
    this.preloadedSourceReady = false,
    this.preloadLoadedDuration,
    this.preloadReadyDuration,
  });

  final Duration audioLoadDuration;
  final Duration startedAfterRequest;
  final bool fromDeviceCache;
  final bool preloadedSourceLoaded;
  final bool preloadedSourceReady;
  final Duration? preloadLoadedDuration;
  final Duration? preloadReadyDuration;
}

abstract interface class AudioPlaybackService {
  Stream<bool> get playingStream;
  Future<void> prepare();
  Future<void> preload(Uri uri);
  Future<PlaybackStartMetrics> play(Uri uri);
  Future<void> stop();
  Future<void> dispose();
}

/// Optional capability for callers that must distinguish a temporary pause
/// from the source actually reaching its end.
abstract interface class CompletionAwareAudioPlaybackService {
  Stream<void> get completionStream;
}

/// Optional playback telemetry used by long-form media such as songs.
///
/// Short lesson prompts do not need to implement this capability, which keeps
/// existing test doubles and lightweight playback implementations compatible.
abstract interface class ProgressAwareAudioPlaybackService {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Duration get position;
  Duration? get duration;
}

/// Optional capability for long-form audio that must restart from the
/// beginning without replacing its source or changing the selected route.
abstract interface class SeekableAudioPlaybackService {
  Future<void> seek(Duration position);
}

/// Optional capability used by browsers that require audio playback to be
/// started directly from a user gesture before later automatic playback.
abstract interface class UserGestureAudioPlaybackService {
  Future<void> unlockForUserGesture();
}

/// Optional web capability that resumes an already loaded source directly
/// inside the browser's tap callback.
abstract interface class DirectUserGestureAudioPlaybackService {
  Future<PlaybackStartMetrics?> playLoadedForUserGesture(Uri uri);
}

/// Optional capability for two-way HFP/SCO devices. Media playback attributes
/// can leave Android on A2DP or the phone speaker; communication attributes
/// keep English audio on the same HFP route as the external microphone.
abstract interface class CommunicationRouteAwareAudioPlaybackService {
  void setCommunicationRouteActive(bool active);
}

/// Optional capability for speech that should be played more slowly without
/// changing ASR, translation, TTS generation, or network processing time.
abstract interface class PlaybackRateAwareAudioPlaybackService {
  void setPlaybackRate(double rate);
}

/// Verifies backend-generated clips before native playback. Web keeps using
/// the browser's media cache, while native platforms enforce SHA-256 locally.
abstract interface class IntegrityAwareAudioPlaybackService {
  Future<void> preloadVerified(
    Uri uri, {
    required String sha256,
    int maximumBytes = 2 * 1024 * 1024,
  });

  Future<PlaybackStartMetrics> playVerified(
    Uri uri, {
    required String sha256,
    int maximumBytes = 2 * 1024 * 1024,
  });
}

/// Optional Android capability for temporarily lifting quiet child recordings
/// without changing the volume of authored clips or synthesized prompts.
abstract interface class PlaybackGainAwareAudioPlaybackService {
  Future<void> setPlaybackGainDb(double gainDb);
}

/// Optional capability for a clip whose requested gain is intentional and
/// must not be replaced by per-file loudness metering. This is reserved for
/// the child's own lesson recordings; authored audio keeps adaptive metering.
abstract interface class FixedPlaybackGainAwareAudioPlaybackService {
  Future<void> setFixedPlaybackGainDb(double gainDb);
}

class _DefaultAudioPlayer {
  const _DefaultAudioPlayer({
    required this.player,
    required this.loudnessEnhancer,
  });

  final AudioPlayer player;
  final AndroidLoudnessEnhancer? loudnessEnhancer;
}

class JustAudioPlaybackService
    implements
        AudioPlaybackService,
        CompletionAwareAudioPlaybackService,
        ProgressAwareAudioPlaybackService,
        SeekableAudioPlaybackService,
        UserGestureAudioPlaybackService,
        DirectUserGestureAudioPlaybackService,
        IntegrityAwareAudioPlaybackService,
        CommunicationRouteAwareAudioPlaybackService,
        PlaybackRateAwareAudioPlaybackService,
        PlaybackGainAwareAudioPlaybackService,
        FixedPlaybackGainAwareAudioPlaybackService {
  static Future<void>? _assetCacheRefresh;
  static const MethodChannel _backgroundLearningChannel = MethodChannel(
    'ailingo_background_learning',
  );
  static const MethodChannel _levelChannel = MethodChannel(
    'ailingo_voice_prompt',
  );
  // A modest boost makes speech clearer on small speakers and HFP headsets
  // without pushing typical voice recordings into heavy clipping.
  static const double androidPlaybackGainDb = androidSpeechBoostDb;

  factory JustAudioPlaybackService({
    AudioPlayer? player,
    DeviceAudioCache? cache,
    AudioTurnCoordinator? audioTurnCoordinator,
    AudioTurnOwner audioTurnOwner = AudioTurnOwner.legacy,
  }) {
    final defaults = player == null ? _createDefaultPlayer() : null;
    return JustAudioPlaybackService._(
      player: player ?? defaults!.player,
      androidLoudnessEnhancer: defaults?.loudnessEnhancer,
      cache: cache,
      audioTurnCoordinator: audioTurnCoordinator,
      audioTurnOwner: audioTurnOwner,
    );
  }

  JustAudioPlaybackService._({
    required AudioPlayer player,
    required AndroidLoudnessEnhancer? androidLoudnessEnhancer,
    DeviceAudioCache? cache,
    AudioTurnCoordinator? audioTurnCoordinator,
    required AudioTurnOwner audioTurnOwner,
  }) : _cache = cache ?? DeviceAudioCache(),
       _ownsCache = cache == null,
       _browserPlayback = createBrowserAudioPlayback(),
       _player = player,
       _androidLoudnessEnhancer = androidLoudnessEnhancer,
       _audioTurnCoordinator = audioTurnCoordinator,
       _audioTurnOwner = audioTurnOwner {
    _audioSession = AudioSession.instance;
    if (audioTurnCoordinator != null) {
      _audioTurnCompletionSubscription = completionStream.listen((_) {
        unawaited(_releaseAudioTurn());
      });
    }
  }

  static _DefaultAudioPlayer _createDefaultPlayer() {
    final androidEffects = <AndroidAudioEffect>[];
    AndroidLoudnessEnhancer? loudnessEnhancer;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      loudnessEnhancer = AndroidLoudnessEnhancer();
      // These setters update the effect's initial configuration synchronously
      // while the player is inactive, so playback starts with the boost ready.
      unawaited(loudnessEnhancer.setTargetGain(androidPlaybackGainDb));
      unawaited(loudnessEnhancer.setEnabled(true));
      androidEffects.add(loudnessEnhancer);
    }
    return _DefaultAudioPlayer(
      player: AudioPlayer(
        // Android attributes belong to this player. Another idle feature may
        // configure the process-wide session for media while H20 is playing.
        androidApplyAudioAttributes:
            kIsWeb || defaultTargetPlatform != TargetPlatform.android,
        audioPipeline: AudioPipeline(androidAudioEffects: androidEffects),
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(
            minBufferDuration: Duration(milliseconds: 600),
            maxBufferDuration: Duration(seconds: 8),
            bufferForPlaybackDuration: Duration(milliseconds: 180),
            bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 500),
            prioritizeTimeOverSizeThresholds: true,
          ),
        ),
      ),
      loudnessEnhancer: loudnessEnhancer,
    );
  }

  final AudioPlayer _player;
  final AndroidLoudnessEnhancer? _androidLoudnessEnhancer;
  final BrowserAudioPlayback? _browserPlayback;
  final DeviceAudioCache _cache;
  final bool _ownsCache;
  final AudioTurnCoordinator? _audioTurnCoordinator;
  final AudioTurnOwner _audioTurnOwner;
  late final Future<AudioSession> _audioSession;
  StreamSubscription<void>? _audioTurnCompletionSubscription;
  AudioTurnLease? _audioTurnLease;
  Future<void>? _playbackSessionPreparation;
  int _playbackPreparationGeneration = 0;
  Future<void> _sourceOperation = Future<void>.value();
  Uri? _loadedOriginalUri;
  Uri? _loadedResolvedUri;
  int _preloadRevision = 0;
  bool _communicationRouteActive = false;
  double _playbackRate = 1.0;
  double _fallbackGainDb = androidPlaybackGainDb;
  double? _fixedGainDb;
  _PlaybackRequest? _playbackRequest;
  final Map<Uri, ({String sha256, int maximumBytes})> _integrity = {};
  bool _disposed = false;

  @override
  Future<void> setPlaybackGainDb(double gainDb) async {
    _fixedGainDb = null;
    _fallbackGainDb = gainDb.clamp(0.0, androidMaxPlaybackGainDb).toDouble();
    AudioDiagnostics.event('media.gain.request', {
      'owner': _audioTurnOwner.name,
      'gainDb': gainDb,
    });
    final enhancer = _androidLoudnessEnhancer;
    if (enhancer == null) return;
    await enhancer.setTargetGain(
      gainDb.clamp(0.0, androidMaxPlaybackGainDb).toDouble(),
    );
    await enhancer.setEnabled(true);
  }

  @override
  Future<void> setFixedPlaybackGainDb(double gainDb) async {
    final fixedGain = gainDb.clamp(0.0, androidMaxPlaybackGainDb).toDouble();
    _fixedGainDb = fixedGain;
    _fallbackGainDb = fixedGain;
    AudioDiagnostics.event('media.gain.fixed_request', {
      'owner': _audioTurnOwner.name,
      'gainDb': fixedGain,
    });
    final enhancer = _androidLoudnessEnhancer;
    if (enhancer == null) return;
    await enhancer.setTargetGain(fixedGain);
    await enhancer.setEnabled(true);
  }

  Future<double?> _measurePlaybackGain(Uri uri) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final Map<String, Object?> arguments;
    if (uri.isScheme('file')) {
      arguments = {'path': uri.toFilePath()};
    } else if (uri.isScheme('asset')) {
      arguments = {'asset': uri.path.replaceFirst(RegExp(r'^/'), '')};
    } else {
      return null; // Never add a blocking network download to playback.
    }
    try {
      final result = await _levelChannel
          .invokeMapMethod<String, Object?>('analyzePlaybackLevel', arguments)
          .timeout(const Duration(milliseconds: 450));
      final gain = (result?['gainDb'] as num?)?.toDouble();
      return gain != null && gain.isFinite
          ? gain.clamp(-96.0, androidMaxPlaybackGainDb).toDouble()
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _applySourceLevel(Uri uri, _PlaybackRequest request) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Metering does not mutate the player. Cancelling this wait lets the next
    // queued source start immediately; a late meter response cannot apply gain.
    final fixedGain = _fixedGainDb;
    final measuredGain = fixedGain == null
        ? await request.wait(_measurePlaybackGain(uri))
        : null;
    _requireCurrentPlayback(request);
    final gain = fixedGain ?? measuredGain ?? _fallbackGainDb;
    // Reset attenuation even if this source cannot be measured, including
    // injected players without an Android effect pipeline.
    await _player.setVolume(
      math.pow(10.0, math.min(gain, 0.0) / 20.0).toDouble(),
    );
    _requireCurrentPlayback(request);
    await _androidLoudnessEnhancer?.setTargetGain(math.max(gain, 0.0));
    _requireCurrentPlayback(request);
    AudioDiagnostics.event('media.level.applied', {
      'owner': _audioTurnOwner.name,
      'gainDb': gain,
      'measured': measuredGain != null,
      'fixed': fixedGain != null,
    });
  }

  @override
  void setPlaybackRate(double rate) {
    final safeRate = rate.clamp(0.4, 2.0).toDouble();
    if (_playbackRate == safeRate) return;
    _playbackRate = safeRate;
    _browserPlayback?.setPlaybackRate(safeRate);
  }

  @override
  void setCommunicationRouteActive(bool active) {
    if (_communicationRouteActive == active) return;
    _communicationRouteActive = active;
    _playbackSessionPreparation = null;
    ++_playbackPreparationGeneration;
  }

  @override
  Future<void> unlockForUserGesture() async {
    final browserPlayback = _browserPlayback;
    if (browserPlayback == null) {
      return;
    }

    try {
      await browserPlayback.unlockForUserGesture();
    } catch (error) {
      debugPrint('Web audio unlock was skipped: $error');
    }
  }

  Future<void> _configurePlaybackAudioSession() async {
    if (await _reuseIosNativeAudioSession()) {
      // Native speech/HFP owns a live playAndRecord/voiceChat session. In the
      // background its input gate is closed during playback; a continuous
      // translation session can also deliberately retain the same HFP lease.
      // Reconfiguring that process-wide session to .playback here makes iOS
      // reject the operation with '!pri'. just_audio can render through the
      // already selected output without taking AVAudioSession ownership away.
      return;
    }
    final session = await _audioSession;
    try {
      // Recording changes the shared audio session, so restore the desired
      // route before every playback request.
      if (_communicationRouteActive) {
        await session.configure(
          const AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth,
            avAudioSessionMode: AVAudioSessionMode.voiceChat,
            androidAudioAttributes: AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          ),
        );
        return;
      }
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
    } on PlatformException catch (error) {
      // The arm request and playback preparation can cross by a few
      // milliseconds. Confirm native ownership once more before surfacing the
      // iOS insufficient-priority error; Android and every other iOS error
      // retain their previous behaviour.
      if (isIosAudioSessionInsufficientPriority(error) &&
          await _reuseIosNativeAudioSession()) {
        return;
      }
      rethrow;
    }
  }

  Future<bool> _reuseIosNativeAudioSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      return await _backgroundLearningChannel.invokeMethod<bool>(
            'isAudioHandoffActive',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> prepare() {
    if (_browserPlayback != null) {
      return Future<void>.value();
    }
    final communicationRoute = _communicationRouteActive;
    final generation = ++_playbackPreparationGeneration;
    final requestedAt = DateTime.now();
    AudioDiagnostics.event('media.prepare.requested', {
      'generation': generation,
      'owner': _audioTurnOwner.name,
      'communicationRoute': communicationRoute,
    });
    final preparation = () async {
      try {
        await _configurePlaybackAudioSession();
        if (_disposed || generation != _playbackPreparationGeneration) {
          AudioDiagnostics.event('media.prepare.cancelled', {
            'generation': generation,
            'owner': _audioTurnOwner.name,
            'stage': 'audio_session',
          });
          return;
        }
        AudioDiagnostics.event('media.prepare.audio_session_ready', {
          'generation': generation,
          'owner': _audioTurnOwner.name,
          'elapsedMs': DateTime.now().difference(requestedAt).inMilliseconds,
        });
        await _applyAndroidPlaybackAttributes(communicationRoute);
        AudioDiagnostics.event('media.prepare.completed', {
          'generation': generation,
          'owner': _audioTurnOwner.name,
          'elapsedMs': DateTime.now().difference(requestedAt).inMilliseconds,
        });
      } catch (error) {
        AudioDiagnostics.event('media.prepare.failed', {
          'generation': generation,
          'owner': _audioTurnOwner.name,
          'errorType': error.runtimeType.toString(),
          'elapsedMs': DateTime.now().difference(requestedAt).inMilliseconds,
        });
        rethrow;
      }
    }();
    _playbackSessionPreparation = preparation;
    return preparation;
  }

  Future<void> _applyAndroidPlaybackAttributes(bool communicationRoute) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _player.setAndroidAudioAttributes(
      AndroidAudioAttributes(
        contentType: communicationRoute
            ? AndroidAudioContentType.speech
            : AndroidAudioContentType.music,
        usage: communicationRoute
            ? AndroidAudioUsage.voiceCommunication
            : AndroidAudioUsage.media,
      ),
    );
  }

  Future<void> _consumePlaybackPreparation() async {
    final preparation = _playbackSessionPreparation ?? prepare();
    try {
      await preparation;
    } finally {
      if (identical(_playbackSessionPreparation, preparation)) {
        _playbackSessionPreparation = null;
      }
    }
  }

  Future<void> _startPlayback(_PlaybackRequest request) async {
    final started = Completer<void>();
    started.future.ignore();
    late final StreamSubscription<Duration> positionSubscription;
    late final StreamSubscription<PlayerState> playerStateSubscription;
    positionSubscription = _player.positionStream.listen(
      (position) {
        if (position > Duration.zero && !started.isCompleted) {
          started.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
        }
      },
    );
    playerStateSubscription = _player.playerStateStream.listen(
      (state) {
        if (state.playing &&
            state.processingState == ProcessingState.ready &&
            !started.isCompleted) {
          started.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
        }
      },
    );

    try {
      await request.wait(_player.setSpeed(_playbackRate));
      await request.wait(
        _applyAndroidPlaybackAttributes(request.communicationRoute),
      );
      _requireCurrentPlayback(request);
      final playback = _player.play();
      unawaited(
        playback.catchError((Object error, StackTrace stackTrace) {
          if (!started.isCompleted) {
            started.completeError(error, stackTrace);
          }
        }),
      );
      await request.wait(started.future.timeout(const Duration(seconds: 2)));
    } finally {
      await Future.wait<void>(<Future<void>>[
        positionSubscription.cancel(),
        playerStateSubscription.cancel(),
      ]);
    }
  }

  Future<void> _rewindCompletedPlayback() async {
    final duration = _player.duration;
    final reachedEnd =
        duration != null &&
        duration > Duration.zero &&
        _player.position >= duration - const Duration(milliseconds: 20);
    if (_player.processingState == ProcessingState.completed || reachedEnd) {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<PlaybackStartMetrics?> playLoadedForUserGesture(Uri uri) async {
    final browserPlayback = _browserPlayback;
    if (browserPlayback == null) {
      return null;
    }

    final requestedAt = DateTime.now();
    final reusedPreloadedSource = browserPlayback.hasPreloadedSource(uri);
    final preloadedSourceLoaded = browserPlayback.hasLoadedPreloadedSource(uri);
    final preloadedSourceReady = browserPlayback.hasReadyPreloadedSource(uri);
    final preloadLoadedDuration = browserPlayback.preloadedSourceLoadedAfter(
      uri,
    );
    final preloadReadyDuration = browserPlayback.preloadedSourceReadyAfter(uri);
    try {
      // The browser implementation invokes HTMLMediaElement.play() before its
      // first await, preserving Safari's transient activation for this tap.
      final playback = browserPlayback.play(uri);
      await playback;
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: DateTime.now().difference(requestedAt),
        fromDeviceCache: reusedPreloadedSource,
        preloadedSourceLoaded: preloadedSourceLoaded,
        preloadedSourceReady: preloadedSourceReady,
        preloadLoadedDuration: preloadLoadedDuration,
        preloadReadyDuration: preloadReadyDuration,
      );
    } catch (error) {
      debugPrint('Direct web playback failed: $error');
      throw const PlaybackException(
        'Safari chưa thể phát âm thanh. Hãy chạm nút phát lại một lần nữa.',
      );
    }
  }

  @override
  Stream<bool> get playingStream =>
      _browserPlayback?.playingStream ??
      _player.playerStateStream
          .map(
            (state) =>
                state.playing &&
                state.processingState != ProcessingState.completed,
          )
          .distinct();

  @override
  Stream<Duration> get positionStream =>
      _browserPlayback?.positionStream ?? _player.positionStream;

  @override
  Stream<Duration?> get durationStream =>
      _browserPlayback?.durationStream ?? _player.durationStream;

  @override
  Duration get position => _browserPlayback?.position ?? _player.position;

  @override
  Duration? get duration => _browserPlayback?.duration ?? _player.duration;

  @override
  Future<void> seek(Duration position) async {
    final safePosition = position.isNegative ? Duration.zero : position;
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      await browserPlayback.seek(safePosition);
      return;
    }
    await _player.seek(safePosition);
  }

  Future<void> _refreshAssetCacheOnce() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    // just_audio extracts bundled assets into a persistent cache keyed by the
    // asset path. When an asset is replaced without changing its path, older
    // installations can otherwise keep playing the previously extracted file.
    // Share this future across service instances so the cache is cleared only
    // once per app process and always before the first asset is loaded.
    return _assetCacheRefresh ??= () async {
      // just_audio 0.10.6 lists this directory while clearing it, but does not
      // create it first. A fresh install (or Android clearing app cache) then
      // throws PathNotFoundException before the first bundled clip can load.
      await ensureJustAudioAssetCacheDirectory();
      await AudioPlayer.clearAssetCache();
    }();
  }

  @override
  Stream<void> get completionStream {
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      return browserPlayback.playingStream
          .where((playing) => !playing)
          .map((_) {});
    }
    final tracker = PlaybackCompletionTracker(
      processingState: _player.processingState,
      playing: _player.playing,
      duration: _player.duration,
    );
    return _player.playerStateStream
        .where(
          (state) => tracker.observe(
            processingState: state.processingState,
            playing: state.playing,
            position: _player.position,
            duration: _player.duration,
          ),
        )
        .map((_) {});
  }

  Future<void> _setSource(Uri uri) async {
    if (uri.isScheme('asset')) {
      await _refreshAssetCacheOnce();
      final assetPath = uri.path.startsWith('/')
          ? uri.path.substring(1)
          : uri.path;
      await _player.setAsset(assetPath).timeout(const Duration(seconds: 8));
    } else if (uri.isScheme('file')) {
      await _player
          .setFilePath(uri.toFilePath())
          .timeout(const Duration(seconds: 8));
    } else {
      await _player.setUrl(uri.toString()).timeout(const Duration(seconds: 8));
    }
  }

  Future<void> _queueSource(Future<void> Function() operation) {
    final next = _sourceOperation.catchError((_) {}).then((_) => operation());
    _sourceOperation = next;
    return next;
  }

  @override
  Future<void> preload(Uri uri) async {
    if (_disposed) return;
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      await browserPlayback.preload(uri);
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return;
    }

    final revision = ++_preloadRevision;
    final integrity = _integrity[uri];
    final cachedUri = integrity == null
        ? await _cache.cache(uri)
        : await _cache.cacheVerified(
            uri,
            sha256Checksum: integrity.sha256,
            maximumFileBytes: integrity.maximumBytes,
          );
    if (_disposed || cachedUri == null || revision != _preloadRevision) {
      return;
    }
    unawaited(
      _measurePlaybackGain(cachedUri),
    ); // Warm the native bounded meter cache.
    await _queueSource(() async {
      if (_disposed ||
          revision != _preloadRevision ||
          (_loadedOriginalUri == uri && _loadedResolvedUri == cachedUri)) {
        return;
      }
      _loadedOriginalUri = null;
      _loadedResolvedUri = null;
      await _setSource(cachedUri);
      if (_disposed || revision != _preloadRevision) return;
      _loadedOriginalUri = uri;
      _loadedResolvedUri = cachedUri;
    });
  }

  @override
  Future<void> preloadVerified(
    Uri uri, {
    required String sha256,
    int maximumBytes = 2 * 1024 * 1024,
  }) {
    _rememberIntegrity(uri, sha256, maximumBytes);
    return preload(uri);
  }

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    final diagnosticOperation = AudioDiagnostics.nextId();
    AudioDiagnostics.event('media.play.request', {
      'operation': diagnosticOperation,
      'owner': _audioTurnOwner.name,
      'communicationRoute': _communicationRouteActive,
      'scheme': uri.scheme,
    });
    if (_disposed) throw const PlaybackException('Lượt phát âm thanh đã dừng.');
    _playbackRequest?.cancel();
    final request = _PlaybackRequest(
      _communicationRouteActive,
      diagnosticOperation: diagnosticOperation,
    );
    _playbackRequest = request;
    try {
      await _acquireAudioTurn(request);
      _requireCurrentPlayback(request);
      final metrics = await _playWithoutTurnCoordination(uri, request);
      AudioDiagnostics.event('media.play.started', {
        'operation': diagnosticOperation,
        'owner': _audioTurnOwner.name,
        'startDelayMs': metrics.startedAfterRequest.inMilliseconds,
      });
      return metrics;
    } catch (error) {
      AudioDiagnostics.event('media.play.failed', {
        'operation': diagnosticOperation,
        'owner': _audioTurnOwner.name,
        'errorType': error.runtimeType.toString(),
      });
      // An older failed/cancelled start cannot release the next clip's lease.
      if (identical(_playbackRequest, request)) {
        _playbackRequest = null;
        await _releaseAudioTurn();
      }
      rethrow;
    }
  }

  @override
  Future<PlaybackStartMetrics> playVerified(
    Uri uri, {
    required String sha256,
    int maximumBytes = 2 * 1024 * 1024,
  }) {
    _rememberIntegrity(uri, sha256, maximumBytes);
    return play(uri);
  }

  void _rememberIntegrity(Uri uri, String checksum, int maximumBytes) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Invalid backend audio checksum.');
    }
    _integrity[uri] = (
      sha256: checksum.toLowerCase(),
      maximumBytes: maximumBytes,
    );
    while (_integrity.length > 128) {
      _integrity.remove(_integrity.keys.first);
    }
  }

  void _requireCurrentPlayback(_PlaybackRequest request) {
    if (_disposed ||
        request.isCancelled ||
        !identical(_playbackRequest, request)) {
      throw const PlaybackException('Lượt phát âm thanh đã dừng.');
    }
  }

  Future<PlaybackStartMetrics> _playWithoutTurnCoordination(
    Uri uri,
    _PlaybackRequest request,
  ) async {
    final requestedAt = DateTime.now();
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      final reusedPreloadedSource = browserPlayback.hasPreloadedSource(uri);
      final preloadedSourceLoadedBeforePlayback = browserPlayback
          .hasLoadedPreloadedSource(uri);
      final preloadedSourceReadyBeforePlayback = browserPlayback
          .hasReadyPreloadedSource(uri);
      final loadStartedAt = DateTime.now();
      try {
        await request.wait(browserPlayback.play(uri));
      } catch (error) {
        debugPrint('Browser audio playback failed: $error');
        throw const PlaybackException(
          'Safari chưa cho phép tự phát. Hãy chạm nút phát câu tiếng Anh.',
        );
      }
      final startedAt = DateTime.now();
      // Safari can dispatch loadeddata/canplay while the play() promise is
      // pending. Sample readiness again after playback starts so telemetry does
      // not report a false miss for the exact element that was successfully
      // buffered and reused.
      final preloadedSourceLoaded =
          preloadedSourceLoadedBeforePlayback ||
          browserPlayback.hasLoadedPreloadedSource(uri);
      final preloadedSourceReady =
          preloadedSourceReadyBeforePlayback ||
          browserPlayback.hasReadyPreloadedSource(uri);
      final preloadLoadedDuration = browserPlayback.preloadedSourceLoadedAfter(
        uri,
      );
      final preloadReadyDuration = browserPlayback.preloadedSourceReadyAfter(
        uri,
      );
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return PlaybackStartMetrics(
        audioLoadDuration: startedAt.difference(loadStartedAt),
        startedAfterRequest: startedAt.difference(requestedAt),
        // On Web this flag means no second network source was assigned after
        // finalize: the exact HTMLAudioElement preload continued into play().
        fromDeviceCache: reusedPreloadedSource,
        preloadedSourceLoaded: preloadedSourceLoaded,
        preloadedSourceReady: preloadedSourceReady,
        preloadLoadedDuration: preloadLoadedDuration,
        preloadReadyDuration: preloadReadyDuration,
      );
    }

    ++_preloadRevision;
    _diagnosePlaybackStage(request, 'preparation_wait_started');
    await request.wait(_consumePlaybackPreparation());
    _requireCurrentPlayback(request);
    _diagnosePlaybackStage(request, 'preparation_wait_completed');
    final integrity = _integrity[uri];
    _diagnosePlaybackStage(request, 'cache_resolve_started', {
      'verified': integrity != null,
      'scheme': uri.scheme,
    });
    final resolvedUri = await request.wait(
      integrity == null
          ? _cache.resolveAfterPreload(uri)
          : _cache.resolveAfterPreloadVerified(
              uri,
              sha256Checksum: integrity.sha256,
            ),
    );
    _requireCurrentPlayback(request);
    _diagnosePlaybackStage(request, 'cache_resolve_completed', {
      'resolvedScheme': resolvedUri.scheme,
    });
    final loadStartedAt = DateTime.now();
    _diagnosePlaybackStage(request, 'source_load_started');
    await request.wait(
      _queueSource(() async {
        _requireCurrentPlayback(request);
        if (_loadedOriginalUri == uri && _loadedResolvedUri == resolvedUri) {
          return;
        }
        _loadedOriginalUri = null;
        _loadedResolvedUri = null;
        await _setSource(resolvedUri);
        _requireCurrentPlayback(request);
        _loadedOriginalUri = uri;
        _loadedResolvedUri = resolvedUri;
      }),
    );
    _requireCurrentPlayback(request);
    final loadedAt = DateTime.now();
    _diagnosePlaybackStage(request, 'source_load_completed', {
      'elapsedMs': loadedAt.difference(loadStartedAt).inMilliseconds,
    });
    _diagnosePlaybackStage(request, 'level_apply_started');
    await request.wait(
      _queueSource(() => _applySourceLevel(resolvedUri, request)),
    );
    _requireCurrentPlayback(request);
    _diagnosePlaybackStage(request, 'level_apply_completed');
    assert(() {
      debugPrint(
        'Audio source ready for $uri after '
        '${loadedAt.difference(requestedAt).inMilliseconds} ms '
        '(duration: ${_player.duration}, position: ${_player.position}).',
      );
      return true;
    }());
    try {
      _diagnosePlaybackStage(request, 'first_playing_wait_started');
      await request.wait(_rewindCompletedPlayback());
      _requireCurrentPlayback(request);
      await _startPlayback(request);
    } on TimeoutException {
      // ExoPlayer can occasionally remain in a completed-but-playing state
      // when the same short clip is used again. Reset and retry once.
      _requireCurrentPlayback(request);
      await request.wait(_player.pause());
      await request.wait(_player.seek(Duration.zero));
      try {
        await _startPlayback(request);
      } on TimeoutException {
        throw const PlaybackException('Không thể bắt đầu phát câu tiếng Anh.');
      }
    } catch (error) {
      debugPrint('Audio playback failed: $error');
      throw PlaybackException(
        kIsWeb
            ? 'Trình duyệt chưa cho phép phát âm thanh. Hãy chạm nút phát lại.'
            : 'Không thể bắt đầu phát câu tiếng Anh.',
      );
    }

    final startedAt = DateTime.now();
    _diagnosePlaybackStage(request, 'first_playing_received', {
      'elapsedMs': startedAt.difference(requestedAt).inMilliseconds,
    });
    if (!resolvedUri.isScheme('file')) {
      unawaited(_cache.cache(uri));
    }
    return PlaybackStartMetrics(
      audioLoadDuration: loadedAt.difference(loadStartedAt),
      startedAfterRequest: startedAt.difference(requestedAt),
      fromDeviceCache: resolvedUri.isScheme('file'),
    );
  }

  void _diagnosePlaybackStage(
    _PlaybackRequest request,
    String stage, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    AudioDiagnostics.event('media.play.stage', {
      'operation': request.diagnosticOperation,
      'owner': _audioTurnOwner.name,
      'stage': stage,
      'communicationRoute': request.communicationRoute,
      ...fields,
    });
  }

  @override
  Future<void> stop() async {
    _playbackRequest?.cancel();
    _playbackRequest = null;
    ++_playbackPreparationGeneration;
    _playbackSessionPreparation = null;
    ++_preloadRevision;
    final lease = _audioTurnLease;
    _audioTurnLease = null;
    try {
      await (_browserPlayback?.pause() ?? _player.pause());
    } finally {
      await lease?.release();
    }
  }

  Future<void> _acquireAudioTurn(_PlaybackRequest request) async {
    final coordinator = _audioTurnCoordinator;
    if (coordinator == null) {
      return;
    }
    final current = _audioTurnLease;
    if (current != null && current.isCurrent) {
      return;
    }
    final lease = await coordinator.acquire(
      owner: _audioTurnOwner,
      mode: AudioTurnMode.mediaPlayback,
      cancellation: request.turnCancellation,
    );
    if (_disposed ||
        request.isCancelled ||
        !identical(_playbackRequest, request)) {
      await lease.release();
      _requireCurrentPlayback(request);
    }
    _audioTurnLease = lease;
  }

  Future<void> _releaseAudioTurn() async {
    final lease = _audioTurnLease;
    _audioTurnLease = null;
    await lease?.release();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _playbackRequest?.cancel();
    _playbackRequest = null;
    ++_playbackPreparationGeneration;
    _playbackSessionPreparation = null;
    ++_preloadRevision;
    await _audioTurnCompletionSubscription?.cancel();
    await _releaseAudioTurn();
    await _browserPlayback?.dispose();
    await _player.dispose();
    if (_ownsCache) {
      _cache.dispose();
    }
  }
}

/// Stops awaiting slow cache/native work immediately, while the source queue
/// still serializes native loads. Cancelled work can finish but cannot play.
class _PlaybackRequest {
  _PlaybackRequest(
    this.communicationRoute, {
    required this.diagnosticOperation,
  });

  final bool communicationRoute;
  final int diagnosticOperation;
  final AudioTurnCancellation turnCancellation = AudioTurnCancellation();
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    turnCancellation.cancel();
    _cancelled.complete();
  }

  Future<T> wait<T>(Future<T> work) => Future.any<T>(<Future<T>>[
    work,
    _cancelled.future.then<T>((_) {
      throw const PlaybackException('Lượt phát âm thanh đã dừng.');
    }),
  ]);
}

@visibleForTesting
bool isIosAudioSessionInsufficientPriority(PlatformException error) {
  return error.code == '561017449' ||
      (error.message?.contains('561017449') ?? false);
}

@visibleForTesting
bool isPlaybackAtSourceEnd({
  required ProcessingState processingState,
  required Duration position,
  required Duration? duration,
  required bool currentPlaybackStarted,
}) {
  if (processingState != ProcessingState.completed ||
      !currentPlaybackStarted ||
      duration == null ||
      duration <= Duration.zero) {
    return false;
  }
  const tolerance = Duration(milliseconds: 200);
  return position >= duration - tolerance;
}

/// Tracks completion for the playback source that starts after a listener is
/// attached.
///
/// A listener is intentionally armed before [play] so a very short cached clip
/// cannot finish before the subscription exists. At that moment just_audio can
/// still expose the duration of the *previous* completed source. Keeping that
/// stale duration makes a shorter following sentence play normally but never
/// satisfy the completion predicate, leaving continuous translation in
/// "preparing audio" until its 30-second safety timeout. This tracker accepts a
/// duration only after the new playback has actually started.
class PlaybackCompletionTracker {
  PlaybackCompletionTracker({
    required ProcessingState processingState,
    required bool playing,
    required Duration? duration,
  }) : _currentPlaybackStarted =
           playing && processingState != ProcessingState.completed,
       _activeDuration = playing && processingState != ProcessingState.completed
           ? duration
           : null;

  bool _currentPlaybackStarted;
  Duration? _activeDuration;

  bool observe({
    required ProcessingState processingState,
    required bool playing,
    required Duration position,
    required Duration? duration,
  }) {
    if (processingState == ProcessingState.loading &&
        position == Duration.zero) {
      // A new source invalidates every duration observed for an older source.
      _activeDuration = null;
    }
    if (playing && processingState != ProcessingState.completed) {
      _currentPlaybackStarted = true;
    }
    if (_currentPlaybackStarted &&
        duration != null &&
        duration > Duration.zero &&
        (processingState == ProcessingState.ready ||
            processingState == ProcessingState.completed)) {
      _activeDuration = duration;
    }
    // just_audio can publish ProcessingState.completed before its position
    // stream has delivered the final position for the same source. Since this
    // tracker is driven by playerStateStream, there may be no later state event
    // on which to re-check the position. Once a non-completed playing state for
    // the current source has been observed, the completed state itself is the
    // authoritative end signal. The started gate still rejects the replayed
    // completed state from the previous source when the listener is armed.
    if (_currentPlaybackStarted &&
        processingState == ProcessingState.completed) {
      return true;
    }
    return isPlaybackAtSourceEnd(
      processingState: processingState,
      position: position,
      duration: _activeDuration,
      currentPlaybackStarted: _currentPlaybackStarted,
    );
  }
}

class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}
