import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'audio_diagnostics.dart';
import 'voice_prompt_service_base.dart';

/// Allowlisted fixed assistant prompts. It is wrapped INSIDE the existing
/// audio-turn coordinator, so file playback and TTS share one exclusive lease.
/// Never recognizes commands or changes learning/session state.
class MainAssistantAudioPromptService
    implements
        VoicePromptService,
        AuthoredPromptBudgetProvider,
        KeyedAuthoredPromptBudgetProvider,
        KeyedVoicePromptService,
        KeyedSelectedMediaOutputVoicePromptService,
        AuthoredAudioVoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  MainAssistantAudioPromptService({
    required VoicePromptService delegate,
    AssetBundle? bundle,
    this.enabled = false,
    this.assetLoadTimeout = const Duration(milliseconds: 500),
    this.remoteAudioLoadTimeout = const Duration(seconds: 8),
    this.cacheLateRemoteAudio = false,
    this.preferBundledAudio = false,
    this.additionalManifestAssets = const [],
    this.groupEnabled = const {},
    http.Client? httpClient,
  }) : _delegate = delegate,
       _bundle = bundle ?? rootBundle,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static const manifestAsset = 'assets/data/assistant_core_audio.json';
  static const maximumAudioSeconds = 45.0;
  static const mainNavigationGroup = 'main-navigation';
  static const translationControlsGroup = 'translation-controls';
  static const challengeCueGroup = 'challenge-cues';
  static const conversationRecoveryGroup = 'conversation-recovery';

  final VoicePromptService _delegate;
  final AssetBundle _bundle;
  final bool enabled;
  final Duration assetLoadTimeout;
  final Duration remoteAudioLoadTimeout;
  final bool cacheLateRemoteAudio;
  final bool preferBundledAudio;
  final List<String> additionalManifestAssets;
  final Map<String, bool> groupEnabled;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  Future<Map<String, dynamic>>? _manifest;
  final Set<void Function()> _pendingWaits = {};
  // Reuse only checksum-verified, immutable audio. Repeated MAIN turns should
  // not download the same short prompt again while holding the headset route.
  final Map<String, Uint8List> _verifiedAudio = {};
  final Map<String, Future<Uint8List>> _remoteAudioLoads = {};
  final Set<String> _unavailableBundledAudio = {};
  static const _maximumCachedAudioBytes = 4 * 1024 * 1024;
  int _generation = 0;
  bool _disposed = false;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  bool _matchesKey(Map<String, dynamic> entry, String audioKey, String locale) {
    final group = entry['group'];
    if (group is String && group.isNotEmpty && groupEnabled[group] == false) {
      return false;
    }
    return entry['enabled'] == true &&
        entry['key'] == audioKey &&
        (entry['locale'] == locale ||
            (entry['lookupLocales'] as List<dynamic>? ?? const []).contains(
              locale,
            ));
  }

  bool _matchesText(Map<String, dynamic> entry, String text, String locale) {
    final group = entry['group'];
    if (group is String && group.isNotEmpty && groupEnabled[group] == false) {
      return false;
    }
    final normalizedText = text.trim();
    final lookupTexts = entry['lookupTexts'] as List<dynamic>? ?? const [];
    return entry['enabled'] == true &&
        (entry['text'] == normalizedText ||
            lookupTexts.contains(normalizedText)) &&
        (entry['locale'] == locale ||
            (entry['lookupLocales'] as List<dynamic>? ?? const []).contains(
              locale,
            ));
  }

  @override
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  }) =>
      _authoredPromptBudgetWhere((entry) => _matchesText(entry, text, locale));

  @override
  Future<Duration?> authoredPromptBudgetForKey(
    String audioKey, {
    required String text,
    String locale = 'vi-VN',
  }) => _authoredPromptBudgetWhere(
    (entry) => _matchesKey(entry, audioKey, locale),
  );

  Future<Duration?> _authoredPromptBudgetWhere(
    bool Function(Map<String, dynamic> entry) matchesEntry,
  ) async {
    if (_disposed ||
        !enabled ||
        _delegate is! AuthoredAudioVoicePromptService) {
      return null;
    }
    try {
      final manifest = await _loadManifest();
      if (manifest['enabled'] != true || _disposed) return null;
      final matches = (manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where(matchesEntry)
          .toList();
      if (matches.length != 1) return null;
      final seconds = (matches.single['durationSeconds'] as num).toDouble();
      if (!seconds.isFinite || seconds <= 0 || seconds > maximumAudioSeconds) {
        return null;
      }
      // Loading/decoder margin plus a bounded TTS recovery; not a fixed delay.
      return Duration(milliseconds: (seconds * 1000).ceil() + 10000);
    } catch (_) {
      return null;
    }
  }

  // Future.timeout alone keeps its timer alive after stop/dispose when the
  // underlying asset/native future has not completed. Own and cancel the wait
  // explicitly so leaving a screen cannot resurrect playback or leak timers.
  Future<T> _bounded<T>(Future<T> work, Duration duration) {
    final result = Completer<T>();
    late final Timer timer;
    late final void Function() cancel;
    void cleanUp() {
      timer.cancel();
      _pendingWaits.remove(cancel);
    }

    void fail(Object error, [StackTrace? stack]) {
      if (result.isCompleted) return;
      cleanUp();
      result.completeError(error, stack);
    }

    cancel = () => fail(StateError('Authored prompt cancelled.'));
    timer = Timer(
      duration,
      () => fail(TimeoutException('Authored prompt timed out.', duration)),
    );
    _pendingWaits.add(cancel);
    work.then((value) {
      if (result.isCompleted) return;
      cleanUp();
      result.complete(value);
    }, onError: fail);
    return result.future;
  }

  Future<Map<String, dynamic>> _loadManifest() => _manifest ??= () async {
    final text = await _bounded(
      _bundle.loadString(manifestAsset),
      assetLoadTimeout,
    );
    final manifest = jsonDecode(text) as Map<String, dynamic>;
    if (manifest['schemaVersion'] != 1) {
      throw const FormatException('Unsupported MAIN audio manifest.');
    }
    final prompts = List<dynamic>.of(manifest['prompts'] as List<dynamic>);
    for (final asset in additionalManifestAssets) {
      try {
        final extra =
            jsonDecode(
                  await _bounded(_bundle.loadString(asset), assetLoadTimeout),
                )
                as Map<String, dynamic>;
        if (extra['schemaVersion'] == 1 && extra['enabled'] == true) {
          prompts.addAll(extra['prompts'] as List<dynamic>);
        }
      } catch (_) {
        // A missing optional curriculum pack must not disable MAIN or TTS.
      }
    }
    manifest['prompts'] = prompts;
    return manifest;
  }();

  Future<void> _playKeyed(
    String audioKey,
    String text,
    String locale,
    Future<void> Function() fallback, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) => _playMatching(
    text,
    locale,
    (entry) => _matchesKey(entry, audioKey, locale),
    fallback,
    forcePhoneSpeaker: forcePhoneSpeaker,
    forceMediaPlayback: forceMediaPlayback,
  );

  Future<void> _playText(
    String text,
    String locale,
    Future<void> Function() fallback, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) => _playMatching(
    text,
    locale,
    (entry) => _matchesText(entry, text, locale),
    fallback,
    forcePhoneSpeaker: forcePhoneSpeaker,
    forceMediaPlayback: forceMediaPlayback,
  );

  Future<void> _playMatching(
    String text,
    String locale,
    bool Function(Map<String, dynamic> entry) matchesEntry,
    Future<void> Function() fallback, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) async {
    if (_disposed) return;
    final generation = _generation;
    final promptId = AudioDiagnostics.nextId();
    final loadingWatch = Stopwatch()..start();
    final player = _delegate;
    var startedAudio = false;
    if (enabled && player is AuthoredAudioVoicePromptService) {
      try {
        final manifest = await _loadManifest();
        if (!_isCurrent(generation)) return;
        if (manifest['enabled'] == true) {
          final matches = (manifest['prompts'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .where(matchesEntry)
              .toList();
          // Ambiguous mappings fall back instead of choosing an arbitrary file.
          if (matches.length == 1) {
            final entry = matches.single;
            final asset = entry['asset'] as String;
            final seconds = (entry['durationSeconds'] as num).toDouble();
            if (!(asset.startsWith('assets/audio/MAIN/GAP66/') ||
                    asset.startsWith('assets/audio/assistant-core/') ||
                    asset.startsWith('assets/audio/listening-common/') ||
                    asset.startsWith('assets/audio/listening-3-5/') ||
                    asset.startsWith('assets/audio/listening-6-7/') ||
                    asset.startsWith('assets/audio/listening-8-10/') ||
                    asset.startsWith('assets/audio/listening-11-12/') ||
                    asset.startsWith('assets/audio/listening-13-15/') ||
                    asset.startsWith('assets/audio/challenge-3-5/') ||
                    asset.startsWith('assets/audio/challenge-6-7/') ||
                    asset.startsWith('assets/audio/challenge-8-10/') ||
                    asset.startsWith('assets/audio/challenge-11-12/') ||
                    asset.startsWith('assets/audio/challenge-13-15/')) ||
                asset.contains('..') ||
                !asset.endsWith('.mp3') ||
                !seconds.isFinite ||
                seconds <= 0 ||
                seconds > maximumAudioSeconds) {
              throw const FormatException('Invalid MAIN audio entry.');
            }
            final checksum = entry['sha256'] as String;
            final cached = _verifiedAudio[checksum];
            if (cached != null) {
              AudioDiagnostics.event('prompt.audio.cache.hit', {
                'promptId': promptId,
                'asset': asset,
              });
            }
            final bytes =
                cached ??
                await _loadAudioBytes(entry, asset, generation, promptId);
            if (!_isCurrent(generation)) return;
            if (bytes.isEmpty ||
                bytes.length > 2 * 1024 * 1024 ||
                sha256.convert(bytes).toString() != entry['sha256']) {
              throw const FormatException('MAIN audio integrity check failed.');
            }
            _rememberVerifiedAudio(checksum, bytes);
            AudioDiagnostics.event('prompt.audio.loaded', {
              'promptId': promptId,
              'asset': asset,
              'loadMs': loadingWatch.elapsedMilliseconds,
            });
            startedAudio = true;
            await _bounded(
              (player as AuthoredAudioVoicePromptService)
                  .playAuthoredAudioAndWait(
                    bytes,
                    forcePhoneSpeaker: forcePhoneSpeaker,
                    forceMediaPlayback: forceMediaPlayback,
                  ),
              Duration(milliseconds: (seconds * 1000).ceil() + 3000),
            );
            return;
          }
        }
      } catch (error) {
        // Cancellation is not a playback failure: never resurrect a stale
        // prompt with TTS after MAIN has stopped or handed over to a lesson.
        if (!_isCurrent(generation)) return;
        AudioDiagnostics.event('prompt.audio.fallback', {
          'promptId': promptId,
          'loadMs': loadingWatch.elapsedMilliseconds,
          'reason': error is TimeoutException
              ? 'timeout'
              : '${error.runtimeType}',
        });
        if (startedAudio) await _delegate.stop();
        // Losing the selected headset is not a decoder failure. Native route
        // cleanup has closed SCO, so a TTS retry could play on the phone.
        if (error is PlatformException && error.code.startsWith('HFP_ROUTE_')) {
          rethrow;
        }
      }
    }
    if (_isCurrent(generation)) await fallback();
  }

  void _rememberVerifiedAudio(String checksum, Uint8List bytes) {
    // Move the entry to the end so frequently used navigation stays cached.
    _verifiedAudio.remove(checksum);
    _verifiedAudio[checksum] = bytes;
    var total = _verifiedAudio.values.fold<int>(
      0,
      (sum, item) => sum + item.length,
    );
    while (total > _maximumCachedAudioBytes) {
      total -= _verifiedAudio.remove(_verifiedAudio.keys.first)!.length;
    }
  }

  Future<Uint8List> _loadAudioBytes(
    Map<String, dynamic> entry,
    String asset,
    int generation,
    int promptId,
  ) async {
    // Navigation and vocabulary menus are packaged with the Android app. Use
    // their verified bytes before trying the optional CDN copy; a network
    // outage must not add a timeout to each selection. Missing curriculum
    // files still use the remote/TTS policy below.
    if (preferBundledAudio && !_unavailableBundledAudio.contains(asset)) {
      try {
        final data = await _bounded(_bundle.load(asset), assetLoadTimeout);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (bytes.isEmpty ||
            bytes.length > 2 * 1024 * 1024 ||
            sha256.convert(bytes).toString() != entry['sha256']) {
          throw const FormatException('Bundled prompt integrity check failed.');
        }
        AudioDiagnostics.event('prompt.audio.bundled', {
          'promptId': promptId,
          'asset': asset,
        });
        return bytes;
      } catch (_) {
        if (!_isCurrent(generation)) rethrow;
        _unavailableBundledAudio.add(asset);
      }
    }
    final remoteValue = entry['url'];
    final remoteUri = remoteValue is String ? Uri.tryParse(remoteValue) : null;
    if (remoteUri != null &&
        remoteUri.isScheme('https') &&
        remoteUri.host == 'res.cloudinary.com') {
      AudioDiagnostics.event('prompt.audio.remote.wait', {
        'promptId': promptId,
        'asset': asset,
        'timeoutMs': remoteAudioLoadTimeout.inMilliseconds,
      });
      if (cacheLateRemoteAudio) {
        final checksum = entry['sha256'] as String;
        final download = _remoteAudioLoads.putIfAbsent(
          checksum,
          () => _downloadVerifiedAudio(remoteUri, checksum),
        );
        return _bounded(download, remoteAudioLoadTimeout);
      }
      final response = await _bounded(
        _httpClient.get(remoteUri),
        remoteAudioLoadTimeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Cloudinary audio request failed (${response.statusCode}).',
        );
      }
      return response.bodyBytes;
    }

    // Retained for injected test bundles and for manifests created before the
    // Cloudinary migration. Production manifests include a Cloudinary URL.
    final data = await _bounded(_bundle.load(asset), assetLoadTimeout);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Uint8List> _downloadVerifiedAudio(Uri uri, String checksum) async {
    try {
      final response = await _httpClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Cloudinary audio request failed (${response.statusCode}).',
        );
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty ||
          bytes.length > 2 * 1024 * 1024 ||
          sha256.convert(bytes).toString() != checksum) {
        throw const FormatException('MAIN audio integrity check failed.');
      }
      // A short Android wait can fall back to TTS while HTTP finishes. Only
      // retain immutable, verified bytes here: never replay a timed-out or
      // cancelled utterance. A later explicit turn may reuse them after stop.
      if (!_disposed) _rememberVerifiedAudio(checksum, bytes);
      return bytes;
    } finally {
      _remoteAudioLoads.remove(checksum);
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      _playText(text, locale, () => _delegate.speak(text, locale: locale));

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      _playText(
        text,
        locale,
        () => _delegate.speakAndWait(text, locale: locale),
      );

  @override
  Future<void> speakAndWaitWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) => _playKeyed(
    audioKey,
    text,
    locale,
    () => _delegate.speakAndWait(text, locale: locale),
  );

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => _playText(text, locale, () {
    final delegate = _delegate;
    return delegate is SelectedMediaOutputVoicePromptService
        ? (delegate as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  }, forceMediaPlayback: true);

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) => _playKeyed(audioKey, text, locale, () {
    final delegate = _delegate;
    return delegate is SelectedMediaOutputVoicePromptService
        ? (delegate as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  }, forceMediaPlayback: true);

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => _playText(text, locale, () {
    final delegate = _delegate;
    return delegate is PhoneSpeakerVoicePromptService
        ? (delegate as PhoneSpeakerVoicePromptService)
              .speakAndWaitOnPhoneSpeaker(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  }, forcePhoneSpeaker: true);

  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List audioBytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) {
    final delegate = _delegate;
    if (delegate is! AuthoredAudioVoicePromptService) {
      throw const FormatException(
        'Native authored-audio playback unavailable.',
      );
    }
    return (delegate as AuthoredAudioVoicePromptService)
        .playAuthoredAudioAndWait(
          audioBytes,
          forcePhoneSpeaker: forcePhoneSpeaker,
          forceMediaPlayback: forceMediaPlayback,
        );
  }

  // Style requests must not silently play an asset authored with another style.
  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) async {
    if (_disposed) return;
    final delegate = _delegate;
    if (delegate is StyledMediaOutputVoicePromptService) {
      await (delegate as StyledMediaOutputVoicePromptService)
          .speakAndWaitStyled(
            text,
            locale: locale,
            speechRate: speechRate,
            pitch: pitch,
          );
    } else {
      await delegate.speakAndWait(text, locale: locale);
    }
  }

  @override
  Future<void> playSpeechReadyCue() async {
    final delegate = _delegate;
    if (!_disposed && delegate is SpeechReadyCuePlayer) {
      await (delegate as SpeechReadyCuePlayer).playSpeechReadyCue();
    }
  }

  @override
  Future<String?> beginMainTurn() async {
    final delegate = _delegate;
    return !_disposed && delegate is MainTurnVoicePromptService
        ? (delegate as MainTurnVoicePromptService).beginMainTurn()
        : null;
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    final delegate = _delegate;
    if (delegate is MainTurnVoicePromptService) {
      await (delegate as MainTurnVoicePromptService).endMainTurn(
        reason,
        turnId: turnId,
      );
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    for (final cancel in _pendingWaits.toList()) {
      cancel();
    }
    // A cancelled/failed cached manifest must not poison the next prompt turn.
    _manifest = null;
    await _delegate.stop();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _verifiedAudio.clear();
    _remoteAudioLoads.clear();
    _unavailableBundledAudio.clear();
    if (_ownsHttpClient) _httpClient.close();
    await _delegate.dispose();
  }
}
