import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../hfp_audio_control.dart';
import '../voice_prompt_service_base.dart';
import 'audio_pack_cache.dart';
import 'audio_pack_repository.dart';
import 'audio_prompt_key.dart';
import 'audio_prompt_request.dart';
import 'audio_prompt_resolver.dart';
import 'audio_prompt_service.dart';

final class VoicePromptAudioRegistryAdapter
    implements
        VoicePromptService,
        AuthoredPromptBudgetProvider,
        KeyedAuthoredPromptBudgetProvider,
        KeyedVoicePromptService,
        KeyedSelectedMediaOutputVoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  VoicePromptAudioRegistryAdapter({
    required VoicePromptService delegate,
    required List<String> manifestAssets,
    AssetBundle? bundle,
    AudioPackCache? cache,
    http.Client? httpClient,
    Set<String> allowedCdnHosts = const {'res.cloudinary.com'},
  }) : _delegate = delegate,
       repository = AudioPackRepository(
         bundledManifestAssets: manifestAssets,
         bundle: bundle,
         cache: cache,
         httpClient: httpClient,
         allowedCdnHosts: allowedCdnHosts,
       ) {
    resolver = AudioPromptResolver(repository: repository);
    service = AudioPromptService(
      resolver: resolver,
      playAuthored: _playAuthored,
      playTts: _playTts,
      stopPlayback: delegate.stop,
      isRouteLoss: _isRouteLoss,
    );
  }

  final VoicePromptService _delegate;
  final AudioPackRepository repository;
  late final AudioPromptResolver resolver;
  late final AudioPromptService service;
  bool _disposed = false;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      _delegate.speak(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      service.play(_unkeyedRequest(text, locale)).then<void>((_) {});

  @override
  Future<void> speakAndWaitWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    if (_disposed) return;
    await service.play(_request(audioKey, text, locale));
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  }) async {
    if (_disposed) return;
    await service.play(
      _request(
        audioKey,
        text,
        locale,
        route: AudioOutputRoute.selectedMediaOutput,
        style: AudioPlaybackStyle.lesson,
      ),
    );
  }

  @override
  Future<Duration?> authoredPromptBudgetForKey(
    String audioKey, {
    required String text,
    String locale = 'vi-VN',
  }) => service.budget(_request(audioKey, text, locale));

  @override
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  }) => service.budget(_unkeyedRequest(text, locale));

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => service
      .play(
        _unkeyedRequest(
          text,
          locale,
          route: AudioOutputRoute.selectedMediaOutput,
          style: AudioPlaybackStyle.lesson,
        ),
      )
      .then<void>((_) {});

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => service
      .play(_unkeyedRequest(text, locale, route: AudioOutputRoute.phoneSpeaker))
      .then<void>((_) {});

  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) {
    final delegate = _delegate;
    return delegate is StyledMediaOutputVoicePromptService
        ? (delegate as StyledMediaOutputVoicePromptService).speakAndWaitStyled(
            text,
            locale: locale,
            speechRate: speechRate,
            pitch: pitch,
          )
        : delegate.speakAndWait(text, locale: locale);
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

  Future<void> _playAuthored(
    Uint8List bytes,
    AudioPromptRequest request,
  ) async {
    final delegate = _delegate;
    if (delegate is! AuthoredAudioVoicePromptService) {
      throw const FormatException(
        'Native authored-audio playback unavailable.',
      );
    }
    await (delegate as AuthoredAudioVoicePromptService)
        .playAuthoredAudioAndWait(
          bytes,
          forcePhoneSpeaker:
              request.outputRoute == AudioOutputRoute.phoneSpeaker,
          forceMediaPlayback:
              request.outputRoute == AudioOutputRoute.selectedMediaOutput,
        );
  }

  Future<void> _playTts(AudioPromptRequest request) {
    final delegate = _delegate;
    switch (request.outputRoute) {
      case AudioOutputRoute.selectedMediaOutput:
        return delegate is SelectedMediaOutputVoicePromptService
            ? (delegate as SelectedMediaOutputVoicePromptService)
                  .speakAndWaitOnSelectedMediaOutput(
                    request.fallbackText,
                    locale: request.locale,
                  )
            : delegate.speakAndWait(
                request.fallbackText,
                locale: request.locale,
              );
      case AudioOutputRoute.phoneSpeaker:
        return delegate is PhoneSpeakerVoicePromptService
            ? (delegate as PhoneSpeakerVoicePromptService)
                  .speakAndWaitOnPhoneSpeaker(
                    request.fallbackText,
                    locale: request.locale,
                  )
            : delegate.speakAndWait(
                request.fallbackText,
                locale: request.locale,
              );
      case AudioOutputRoute.defaultOutput:
        return delegate.speakAndWait(
          request.fallbackText,
          locale: request.locale,
        );
    }
  }

  AudioPromptRequest _request(
    String key,
    String text,
    String locale, {
    AudioOutputRoute route = AudioOutputRoute.defaultOutput,
    AudioPlaybackStyle style = AudioPlaybackStyle.assistant,
  }) => AudioPromptRequest(
    key: AudioPromptKey(key),
    fallbackText: text,
    locale: locale,
    outputRoute: route,
    playbackStyle: style,
  );

  AudioPromptRequest _unkeyedRequest(
    String text,
    String locale, {
    AudioOutputRoute route = AudioOutputRoute.defaultOutput,
    AudioPlaybackStyle style = AudioPlaybackStyle.assistant,
  }) => AudioPromptRequest(
    // This intentionally never exists in a manifest. It lets unkeyed dynamic
    // speech share the same serial queue as authored prompts without matching
    // mutable text to an asset.
    key: AudioPromptKey('runtime.tts.unkeyed'),
    fallbackText: text,
    locale: locale,
    outputRoute: route,
    playbackStyle: style,
  );

  static bool _isRouteLoss(Object error) =>
      error is HfpAudioException ||
      (error is PlatformException && error.code.startsWith('HFP_ROUTE_'));

  @override
  Future<void> stop() => service.stop();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await service.stop();
    repository.dispose();
    await _delegate.dispose();
  }
}
