import 'dart:async';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_gain.dart';
import 'debug/playback_rate_debug.dart';
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

  /// Thời gian tối đa chờ file cache để đo được mức âm lượng thật.
  ///
  /// Bản tải do `_cache.cache(...)` chạy song song với lúc bắt đầu phát, nên
  /// chờ ở đây hầu như không thêm độ trễ. Quá hạn thì dùng gain dự phòng và
  /// lần phát sau sẽ chốt mức đo được.
  static const Duration _gainCacheWait = Duration(milliseconds: 800);

  /// Mức nâng âm lượng cho giọng dịch, tính bằng dB.
  ///
  /// Bộ đo chuẩn hoá giọng đọc về RMS -21 dBFS, và mức đó trên loa ngoài hoặc
  /// H20 nghe hơi nhỏ. Cộng thêm mức này cho MỌI nguồn (file cache và URL mạng)
  /// nên âm lượng vẫn đồng nhất giữa lần tự đọc và lần nghe lại. Đây là con số
  /// duy nhất cần chỉnh khi muốn to/nhỏ hơn: tăng lên thì to hơn.
  ///
  /// Chỉ bật cho player của giọng dịch (xem `speechBoostDb` ở factory). Player
  /// của bài học để 0 nên giữ nguyên mức đã căn chỉnh trước đây.
  static const double translatedSpeechBoostDb = 5.0;

  /// Công tắc cho phép tắt hẳn phần đo và tự cân âm lượng ở máy.
  ///
  /// Lý tưởng nhất là backend trả file đã đồng đều âm lượng, khi đó app chỉ cần
  /// phát ở mức 1.0 và không phải đo gì. Công tắc này để kiểm chứng điều đó:
  ///
  /// ```bash
  /// # Tắt đo, phát đúng mức file (volume 1.0, không tăng, không giảm)
  /// flutter run --dart-define=HOMI_TRANSLATION_GAIN_METERING=false
  /// ```
  ///
  /// Khi tắt, cả lần tự đọc lẫn lần nghe lại đều phát ở 1.0 nên chắc chắn không
  /// còn lệch âm lượng. Chỉ áp cho player của giọng dịch; luồng nào tự đặt gain
  /// qua `setPlaybackGainDb`/`setFixedPlaybackGainDb` vẫn giữ nguyên.
  static const bool translationGainMeteringEnabled = bool.fromEnvironment(
    'HOMI_TRANSLATION_GAIN_METERING',
    defaultValue: true,
  );

  factory JustAudioPlaybackService({
    AudioPlayer? player,
    DeviceAudioCache? cache,
    AudioTurnCoordinator? audioTurnCoordinator,
    AudioTurnOwner audioTurnOwner = AudioTurnOwner.legacy,
    double speechBoostDb = 0.0,
  }) {
    final defaults = player == null ? _createDefaultPlayer() : null;
    return JustAudioPlaybackService._(
      player: player ?? defaults!.player,
      androidLoudnessEnhancer: defaults?.loudnessEnhancer,
      cache: cache,
      audioTurnCoordinator: audioTurnCoordinator,
      audioTurnOwner: audioTurnOwner,
      speechBoostDb: speechBoostDb,
    );
  }

  JustAudioPlaybackService._({
    required AudioPlayer player,
    required AndroidLoudnessEnhancer? androidLoudnessEnhancer,
    DeviceAudioCache? cache,
    AudioTurnCoordinator? audioTurnCoordinator,
    required AudioTurnOwner audioTurnOwner,
    double speechBoostDb = 0.0,
  }) : _speechBoostDb = speechBoostDb,
       _cache = cache ?? DeviceAudioCache(),
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
    PlaybackRateDebug.watchPlayer(
      _audioTurnOwner.name,
      currentRate: () => _playbackRate,
      position: () => _player.position,
      isPlaying: () => _player.playing,
    );
    // Ghi lại từng lần player đổi trạng thái. Hai lần phát chồng nhau sẽ hiện
    // thành hai lần chuyển sang playing mà không có lần dừng xen giữa.
    _playerStateDebugSubscription = _player.playerStateStream.listen((state) {
      PlaybackRateDebug.mark('player.state', <String, Object?>{
        'owner': _audioTurnOwner.name,
        'playing': state.playing,
        'processing': state.processingState.name,
        'positionMs': _player.position.inMilliseconds,
      });
    });
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
  StreamSubscription<PlayerState>? _playerStateDebugSubscription;
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
  /// Mức nâng thêm cho giọng dịch của tính năng này (0 = không nâng).
  ///
  /// Lớn hơn 0 cũng đánh dấu đây là player của giọng dịch, tức là player duy
  /// nhất chịu công tắc [translationGainMeteringEnabled].
  final double _speechBoostDb;
  /// Gain đã đo được, ghi theo từng file audio.
  ///
  /// Lần phát đầu nhận URL mạng nên phép đo trực tiếp không chạy được; nếu để
  /// rơi vào gain dự phòng thì lần nghe lại (đã có file trong cache, đo được)
  /// sẽ nhỏ hơn hẳn, dù là cùng một câu. Nhớ kết quả đo để mọi lần phát về sau
  /// của đúng file đó dùng cùng một mức âm lượng.
  ///
  /// Nhớ theo *file cache* vì đó mới là thứ được đo; URI mạng chỉ là chìa khoá
  /// tra cứu.
  static final Map<Uri, double> _rememberedGainByFile = <Uri, double>{};

  /// Xoá bộ nhớ mức âm lượng. Dành cho test cần cô lập; trong ứng dụng thật bộ
  /// nhớ này sống cùng tiến trình vì mỗi câu chỉ nên có một mức âm lượng.
  @visibleForTesting
  static void resetRememberedGainForTesting() => _rememberedGainByFile.clear();
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

  /// Đo mức âm lượng của một file đã có trên máy.
  ///
  /// Chỉ nhận file/asset. Một URL mạng luôn trả null vì phép đo không tải mạng.
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

  /// Chờ bản tải nền hoàn tất để đo được chính file cache.
  ///
  /// Chỉ dùng cho nguồn mạng khi phép đo trực tiếp không chạy được. Bản tải do
  /// `_cache.cache(...)` khởi động ngay sau khi bắt đầu phát, nên lần phát đầu
  /// dùng chung chính future đó. Trả về URI của file nếu kịp, ngược lại giữ
  /// nguyên URI mạng (hành vi cũ).
  Future<Uri> _resolveLocalForGain(Uri uri) async {
    if (uri.isScheme('file') || uri.isScheme('asset')) return uri;
    if (!uri.isScheme('http') && !uri.isScheme('https')) return uri;
    try {
      final cached = await _cache
          .cache(uri)
          .timeout(_gainCacheWait, onTimeout: () => null);
      return cached ?? uri;
    } catch (_) {
      return uri;
    }
  }

  Future<void> _applySourceLevel(Uri uri, _PlaybackRequest request) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Metering does not mutate the player. Cancelling this wait lets the next
    // queued source start immediately; a late meter response cannot apply gain.
    final fixedGain = _fixedGainDb;
    // Chỉ player của giọng dịch đi theo chính sách này; mọi player khác giữ
    // nguyên cách xử lý cũ.
    final handlesTranslationSpeech = _speechBoostDb > 0.0;
    if (handlesTranslationSpeech && !translationGainMeteringEnabled) {
      // Công tắc đã tắt phần đo: phát đúng mức file gốc, không tăng không giảm.
      // Đây là phép thử xem backend đã trả file đồng đều âm lượng chưa.
      PlaybackRateDebug.mark('gain.metering_disabled', <String, Object?>{
        'uri': PlaybackRateDebug.uriTag(uri),
        'playerVolume': 1.0,
      });
      await _player.setVolume(1.0);
      await _androidLoudnessEnhancer?.setTargetGain(0.0);
      return;
    }
    Uri? measuredFile;
    var measuredGain = fixedGain == null ? _rememberedGainByFile[uri] : null;
    if (fixedGain == null && measuredGain == null) {
      // Đo chính file cache cho MỌI lần phát, kể cả lần tự đọc đầu tiên.
      //
      // Lần tự đọc nhận URL mạng nên phép đo trực tiếp không chạy được, và nếu
      // để rơi vào gain dự phòng thì lần nghe lại (đã có file, đo được) sẽ nhỏ
      // hơn hẳn. Chờ bản tải nền rồi đo đúng file đó để hai đường dùng chung
      // một mức.
      final local = await request
          .wait(_resolveLocalForGain(uri))
          .catchError((Object _) => uri);
      // Bước chờ cache ở trên có thể đã bị hủy. Kiểm tra ngay, để một lượt đã
      // dừng không đi tiếp vào phép đo và không treo lượt phát kế tiếp.
      _requireCurrentPlayback(request);
      if (local != uri) {
        measuredFile = local;
        measuredGain = await request.wait(_measurePlaybackGain(local));
        _requireCurrentPlayback(request);
      }
      if (measuredGain == null) {
        // Phép đo ở URI gốc có thể không bao giờ trả về (đang chờ native).
        // Dừng lượt phát phải cắt được nó, nên chờ qua `request.wait` và kiểm
        // tra hủy sau khi có kết quả.
        measuredGain = await request.wait(_measurePlaybackGain(uri));
        _requireCurrentPlayback(request);
      }
    }
    _requireCurrentPlayback(request);
    final rememberedGain = measuredGain ??
        (measuredFile == null ? null : _rememberedGainByFile[measuredFile]);
    // Ghi cả URI gốc và URI file để lần tự đọc (URI mạng) và lần nghe lại (URI
    // file) cùng tra ra đúng một mức.
    final resolvedGain = fixedGain ?? rememberedGain ?? _fallbackGainDb;
    // Nâng đều cho giọng dịch. Áp cho cả mức đo được lẫn mức dự phòng nên hai
    // đường phát vẫn khớp nhau; bỏ qua khi tính năng đã tự đặt gain riêng.
    final gain = fixedGain == null
        ? resolvedGain + _speechBoostDb
        : resolvedGain;
    if (fixedGain == null && rememberedGain != null) {
      _rememberedGainByFile[uri] = rememberedGain;
      if (measuredFile != null) {
        _rememberedGainByFile[measuredFile] = rememberedGain;
      }
    }
    // Reset attenuation even if this source cannot be measured, including
    // injected players without an Android effect pipeline.
    final appliedVolume = math.pow(10.0, math.min(gain, 0.0) / 20.0).toDouble();
    PlaybackRateDebug.mark('gain.applying', <String, Object?>{
      'uri': PlaybackRateDebug.uriTag(uri),
      'measuredGainDb': measuredGain,
      'rememberedGainDb': rememberedGain,
      'fixedGainDb': fixedGain,
      'fallbackGainDb': _fallbackGainDb,
      'effectiveGainDb': gain,
      'volume': appliedVolume,
      'enhancer': _androidLoudnessEnhancer != null ? 'present' : 'none',
      'positionMs': _player.position.inMilliseconds,
      'playingNow': _player.playing,
    });
    await _player.setVolume(appliedVolume);
    _requireCurrentPlayback(request);
    await _androidLoudnessEnhancer?.setTargetGain(math.max(gain, 0.0));
    _requireCurrentPlayback(request);
    PlaybackRateDebug.mark('gain.applied', <String, Object?>{
      'uri': PlaybackRateDebug.uriTag(uri),
      'effectiveGainDb': gain,
      'volume': appliedVolume,
      'enhancerTargetGainDb': _androidLoudnessEnhancer == null
          ? null
          : math.max(gain, 0.0),
    });
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
    final previous = _playbackRate;
    if (_playbackRate == safeRate) {
      PlaybackRateDebug.mark('rate.no_op', <String, Object?>{
        'owner': _audioTurnOwner.name,
        'requested': rate,
        'held': safeRate,
      });
      return;
    }
    _playbackRate = safeRate;
    PlaybackRateDebug.mark('rate.held', <String, Object?>{
      'owner': _audioTurnOwner.name,
      'requested': rate,
      'from': previous,
      'to': safeRate,
      'positionMs': _player.position.inMilliseconds,
      'playingNow': _player.playing,
    });
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
    final preparation = () async {
      await _configurePlaybackAudioSession();
      if (_disposed || generation != _playbackPreparationGeneration) return;
      await _applyAndroidPlaybackAttributes(communicationRoute);
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
      PlaybackRateDebug.mark('speed.applying', <String, Object?>{
        'owner': _audioTurnOwner.name,
        'rate': _playbackRate,
        'positionMsBefore': _player.position.inMilliseconds,
        'playingBefore': _player.playing,
        'elapsedMs': DateTime.now().millisecondsSinceEpoch,
      });
      await request.wait(_player.setSpeed(_playbackRate));
      PlaybackRateDebug.mark('speed.applied', <String, Object?>{
        'owner': _audioTurnOwner.name,
        'rate': _playbackRate,
        'positionMsAfter': _player.position.inMilliseconds,
        'playingAfter': _player.playing,
      });
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

  /// Luôn đưa player về trạng thái dừng, ở đầu clip, trước khi ghi tốc độ.
  ///
  /// Bản cũ chỉ `seek(0)` khi clip đã phát hết. Khi trẻ bấm nghe lại lúc clip
  /// gần kết thúc, `processingState` vẫn là ready nên không có `seek(0)`, và
  /// `setUrl` được gọi trong lúc player vẫn đang phát. ExoPlayer tạo lại nguồn
  /// ở trạng thái playing, nên đoạn đầu của clip mới phát ra trước khi tốc độ
  /// kịp ghi — đúng hiện tượng "đoạn đầu nhanh, đoạn sau chậm".
  Future<void> _rewindCompletedPlayback() async {
    PlaybackRateDebug.mark('rewind.start', <String, Object?>{
      'playing': _player.playing,
      'positionMs': _player.position.inMilliseconds,
      'processing': _player.processingState.name,
    });
    if (_player.playing) {
      await _player.pause();
      PlaybackRateDebug.mark('rewind.paused', <String, Object?>{
        'playing': _player.playing,
        'positionMs': _player.position.inMilliseconds,
      });
    }
    if (_player.position > Duration.zero) {
      await _player.seek(Duration.zero);
      PlaybackRateDebug.mark('rewind.seeked', <String, Object?>{
        'playing': _player.playing,
        'positionMs': _player.position.inMilliseconds,
      });
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
    AudioDiagnostics.event('media.play.request', {
      'owner': _audioTurnOwner.name,
      'communicationRoute': _communicationRouteActive,
      'scheme': uri.scheme,
    });
    if (_disposed) throw const PlaybackException('Lượt phát âm thanh đã dừng.');
    _playbackRequest?.cancel();
    final previousRequest = _playbackRequest;
    PlaybackRateDebug.mark('play.enter', <String, Object?>{
      'owner': _audioTurnOwner.name,
      'uri': PlaybackRateDebug.uriTag(uri),
      'heldRate': _playbackRate,
      'playerTag': PlaybackRateDebug.uriTag(_loadedOriginalUri ?? _loadedResolvedUri),
      'positionMs': _player.position.inMilliseconds,
      'playerPlaying': _player.playing,
      'cancelledPreviousRequest': previousRequest != null,
    });
    final request = _PlaybackRequest(_communicationRouteActive);
    _playbackRequest = request;
    try {
      await _acquireAudioTurn(request);
      _requireCurrentPlayback(request);
      final metrics = await _playWithoutTurnCoordination(uri, request);
      PlaybackRateDebug.mark('play.started', <String, Object?>{
        'owner': _audioTurnOwner.name,
        'uri': PlaybackRateDebug.uriTag(uri),
        'rate': _playbackRate,
        'playerTag': PlaybackRateDebug.uriTag(_loadedOriginalUri ?? _loadedResolvedUri),
        'startDelayMs': metrics.startedAfterRequest.inMilliseconds,
        'fromDeviceCache': metrics.fromDeviceCache,
        'positionMs': _player.position.inMilliseconds,
        'volume': _player.volume,
        'audioSessionId': _player.androidAudioSessionId,
      });
      AudioDiagnostics.event('media.play.started', {
        'owner': _audioTurnOwner.name,
        'startDelayMs': metrics.startedAfterRequest.inMilliseconds,
      });
      return metrics;
    } catch (_) {
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
    await request.wait(_consumePlaybackPreparation());
    _requireCurrentPlayback(request);
    // Dừng player trước khi đổi nguồn. Nếu để ExoPlayer đổi nguồn trong lúc
    // đang phát, nguồn mới kế thừa trạng thái playing và phát ra trước khi
    // `setSpeed` bên dưới kịp chạy (xem `_rewindCompletedPlayback`).
    if (_player.playing) {
      await request.wait(_player.pause());
      _requireCurrentPlayback(request);
    }
    final integrity = _integrity[uri];
    final resolvedUri = await request.wait(
      integrity == null
          ? _cache.resolveAfterPreload(uri)
          : _cache.resolveAfterPreloadVerified(
              uri,
              sha256Checksum: integrity.sha256,
            ),
    );
    _requireCurrentPlayback(request);
    final loadStartedAt = DateTime.now();
    var reusedLoadedSource = false;
    await request.wait(
      _queueSource(() async {
        _requireCurrentPlayback(request);
        // So sánh cả hai chiều: lần tự phát trao URI mạng, lần nghe lại trao
        // thẳng URI file trong cache. Nếu chỉ so URI gốc thì guard luôn trượt,
        // source bị nạp lại mỗi lần nghe lại, và ExoPlayer tạo AudioTrack mới
        // trong lúc track cũ chưa nhả — nguồn gốc của tiếng to bất thường.
        final sameLoadedSource =
            (_loadedOriginalUri == uri && _loadedResolvedUri == resolvedUri) ||
            _loadedResolvedUri == uri;
        if (sameLoadedSource) {
          reusedLoadedSource = true;
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
    PlaybackRateDebug.mark('source.ready', <String, Object?>{
      'uri': PlaybackRateDebug.uriTag(uri),
      'resolved': PlaybackRateDebug.uriTag(resolvedUri),
      'reusedLoadedSource': reusedLoadedSource,
      'loadMs': loadedAt.difference(loadStartedAt).inMilliseconds,
    });
    if (!reusedLoadedSource) {
      assert(() {
        debugPrint(
          'Audio source ready for $uri after '
          '${loadedAt.difference(requestedAt).inMilliseconds} ms '
          '(duration: ${_player.duration}, position: ${_player.position}).',
        );
        return true;
      }());
    }
    await request.wait(
      _queueSource(() => _applySourceLevel(resolvedUri, request)),
    );
    _requireCurrentPlayback(request);
    try {
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
    if (!resolvedUri.isScheme('file')) {
      unawaited(_cache.cache(uri));
    }
    return PlaybackStartMetrics(
      audioLoadDuration: loadedAt.difference(loadStartedAt),
      startedAfterRequest: startedAt.difference(requestedAt),
      fromDeviceCache: resolvedUri.isScheme('file'),
    );
  }

  @override
  Future<void> stop() async {
    PlaybackRateDebug.mark('stop.enter', <String, Object?>{
      'owner': _audioTurnOwner.name,
      'heldRate': _playbackRate,
      'playerTag': PlaybackRateDebug.uriTag(_loadedOriginalUri ?? _loadedResolvedUri),
      'positionMs': _player.position.inMilliseconds,
    });
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
    await _playerStateDebugSubscription?.cancel();
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
  _PlaybackRequest(this.communicationRoute);

  final bool communicationRoute;
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
