import '../domain/master_navigation_contract.dart';
import '../domain/main_assistant_audio_keys.dart';
import 'main_speaking_command_resolver.dart';

/// What the app should do after a recognized command in continuous
/// translation. Keeping this state outside [ConversationController] prevents
/// control phrases from reaching the translation backend.
enum MainSpeakingFallbackAction { stopTranslation }

class MainSpeakingFallbackTurn {
  const MainSpeakingFallbackTurn({
    required this.action,
    this.promptText,
    this.audioKey,
  });

  final MainSpeakingFallbackAction action;
  final String? promptText;
  final String? audioKey;
}

/// The only in-translation control is stop. MAIN opens navigation separately.
class MainSpeakingFallbackFlow {
  MainSpeakingFallbackFlow({
    MainSpeakingCommandResolver commandResolver =
        const MainSpeakingCommandResolver(),
  }) : _commandResolver = commandResolver;

  final MainSpeakingCommandResolver _commandResolver;

  // Compatibility for the app adapter; FINAL has no yes/no translation node.
  bool get isAwaitingConfirmation => false;
  void reset() {}
  bool canHandle(String text) => _commandResolver.resolve(text) != null;

  MainSpeakingFallbackTurn? handle(String text) =>
      switch (_commandResolver.resolve(text)) {
        MainSpeakingCommand.stopTranslation => const MainSpeakingFallbackTurn(
          action: MainSpeakingFallbackAction.stopTranslation,
          promptText: MasterNavigationContract.translationStopped,
          audioKey: MainAssistantAudioKeys.translationStopped,
        ),
        null => null,
      };
}
