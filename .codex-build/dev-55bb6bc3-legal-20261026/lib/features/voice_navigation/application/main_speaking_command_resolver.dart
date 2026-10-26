import '../domain/master_navigation_contract.dart';

enum MainSpeakingCommand { stopTranslation }

/// Only the exact stop phrase interrupts continuous translation. Other speech
/// remains translation content until the child presses MAIN.
class MainSpeakingCommandResolver {
  const MainSpeakingCommandResolver();

  MainSpeakingCommand? resolve(String recognizedText) =>
      MasterNavigationContract.isTranslationStop(recognizedText)
      ? MainSpeakingCommand.stopTranslation
      : null;
}
