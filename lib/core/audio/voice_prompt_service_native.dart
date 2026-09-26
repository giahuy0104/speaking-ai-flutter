import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'audio_gain.dart';
import 'audio_diagnostics.dart';
import 'voice_prompt_service_base.dart';

VoicePromptService createPlatformVoicePromptService() =>
    const MethodChannelVoicePromptService();

class MethodChannelVoicePromptService
    implements
        VoicePromptService,
        AuthoredAudioVoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        StyledMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  const MethodChannelVoicePromptService({
    MethodChannel channel = const MethodChannel('ailingo_voice_prompt'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  }) => _channel.invokeMethod<void>('playAuthoredAudioAndWait', {
    'bytes': bytes,
    'gainDb': androidAssistantSpeechBoostDb,
    'forcePhoneSpeaker': forcePhoneSpeaker,
    'forceMediaPlayback': forceMediaPlayback,
  });

  @override
  Future<String?> beginMainTurn() async {
    try {
      return await _channel.invokeMethod<String>('beginMainTurn');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    try {
      await _channel.invokeMethod<void>('endMainTurn', <String, dynamic>{
        'reason': reason,
        'turnId': ?turnId,
      });
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // Turn cleanup is best effort during navigation cancellation.
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speak', text, locale: locale);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    await _invokeSpeak('speakAndWait', text, locale: locale);
  }

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) async {
    await _invokeSpeak(
      'speakAndWait',
      text,
      locale: locale,
      forcePhoneSpeaker: true,
    );
  }

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    await _invokeSpeak(
      'speakAndWait',
      text,
      locale: locale,
      forceMediaPlayback: true,
    );
  }

  Future<void> _invokeSpeak(
    String method,
    String text, {
    required String locale,
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
    double? speechRate,
    double? pitch,
  }) async {
    if (text.trim().isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, <String, dynamic>{
        'text': text.trim(),
        'locale': locale,
        'gainDb': androidAssistantSpeechBoostDb,
        'forcePhoneSpeaker': forcePhoneSpeaker,
        'forceMediaPlayback': forceMediaPlayback,
        'speechRate': ?speechRate,
        'pitch': ?pitch,
      });
    } on MissingPluginException {
      // The prompt is supplementary. The visible message remains available on
      // platforms where the native bridge has not been implemented yet.
    } on PlatformException {
      // Awaited Android prompts gate capture. Reporting a failed or interrupted
      // utterance as completed skips the model and opens the microphone early.
      if (defaultTargetPlatform == TargetPlatform.android &&
          method == 'speakAndWait') {
        rethrow;
      }
    }
  }

  @override
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  }) => _invokeSpeak(
    'speakAndWait',
    text,
    locale: locale,
    forceMediaPlayback: true,
    speechRate: speechRate,
    pitch: pitch,
  );

  @override
  Future<void> playSpeechReadyCue() async {
    try {
      AudioDiagnostics.event('cue.channel.request');
      await _channel.invokeMethod<void>('playSpeechReadyCue');
      AudioDiagnostics.event('cue.channel.completed');
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // Android capture is gated by this cue. Do not silently open a recorder
      // after a failed cue/route and make the child speak without a ready signal.
      if (defaultTargetPlatform == TargetPlatform.android) rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Optional native capability.
    } on PlatformException {
      // Best effort only.
    }
  }

  @override
  Future<void> dispose() => stop();
}
