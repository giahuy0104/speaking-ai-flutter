import '../domain/master_navigation_contract.dart';
import 'main_speaking_command_resolver.dart';

/// What the app should do after a recognized command in continuous
/// translation. Keeping this state outside [ConversationController] prevents
/// control phrases from reaching the translation backend.
enum MainSpeakingFallbackAction {
  resumeTranslation,
  openOtherLearning,
  stopTranslation,
}

class MainSpeakingFallbackTurn {
  const MainSpeakingFallbackTurn({required this.action, this.promptText});

  final MainSpeakingFallbackAction action;
  final String? promptText;
}

/// FINAL control-only handoff. Menu answers belong to navigation ASR.
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
        ),
        MainSpeakingCommand.otherLearning => const MainSpeakingFallbackTurn(
          action: MainSpeakingFallbackAction.openOtherLearning,
        ),
        MainSpeakingCommand.help => const MainSpeakingFallbackTurn(
          action: MainSpeakingFallbackAction.resumeTranslation,
          promptText: MasterNavigationContract.translationIntro,
        ),
        null => null,
      };
}
