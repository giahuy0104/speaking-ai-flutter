import 'dart:typed_data';

/// Allows a prerecorded prompt to finish without changing the microphone's
/// response window. Unknown/dynamic text retains the caller's normal timeout.
abstract interface class AuthoredPromptBudgetProvider {
  Future<Duration?> authoredPromptBudget(
    String text, {
    String locale = 'vi-VN',
  });
}

/// Resolves prerecorded assistant prompts by stable semantic key. [text] and
/// [locale] are retained solely for the TTS fallback.
abstract interface class KeyedAuthoredPromptBudgetProvider {
  Future<Duration?> authoredPromptBudgetForKey(
    String audioKey, {
    required String text,
    String locale = 'vi-VN',
  });
}

abstract interface class KeyedVoicePromptService {
  Future<void> speakAndWaitWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  });
}

abstract interface class KeyedSelectedMediaOutputVoicePromptService {
  Future<void> speakAndWaitOnSelectedMediaOutputWithAudioKey(
    String audioKey,
    String text, {
    String locale = 'vi-VN',
  });
}

/// Optional native playback on the same route/lifecycle as TTS. Bytes have
/// already been verified by the caller; speed is baked into the file.
abstract interface class AuthoredAudioVoicePromptService {
  Future<void> playAuthoredAudioAndWait(
    Uint8List bytes, {
    bool forcePhoneSpeaker = false,
    bool forceMediaPlayback = false,
  });
}

abstract interface class VoicePromptService {
  Future<void> speak(String text, {String locale = 'vi-VN'});

  /// Plays a prompt and completes only after speech output has stopped.
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'});

  Future<void> stop();

  Future<void> dispose();
}

/// Optional capability for voice prompt implementations that can signal when
/// the child may begin speaking.
abstract interface class SpeechReadyCuePlayer {
  /// Plays a short audible cue and completes after the cue has finished.
  Future<void> playSpeechReadyCue();
}

/// Optional capability for prompts that must be distinguishable from lesson
/// audio routed through a selected two-way H20 device.
abstract interface class PhoneSpeakerVoicePromptService {
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  });
}

/// Plays a lesson prompt through the currently selected H20 output.
///
/// On iOS the native bridge keeps the selected HFP route when it is available;
/// ordinary media playback is only the disconnected-device fallback.
abstract interface class SelectedMediaOutputVoicePromptService {
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  });
}

/// Per-utterance style; never changes the defaults of other learning prompts.
abstract interface class StyledMediaOutputVoicePromptService {
  Future<void> speakAndWaitStyled(
    String text, {
    required String locale,
    required double speechRate,
    required double pitch,
  });
}

/// Optional native capability that brackets one physical/virtual MAIN turn.
/// The iOS implementation uses this boundary to keep one AVAudioSession owner
/// from the first prompt through the final speech result.
abstract interface class MainTurnVoicePromptService {
  Future<String?> beginMainTurn();

  Future<void> endMainTurn(String reason, {String? turnId});
}
