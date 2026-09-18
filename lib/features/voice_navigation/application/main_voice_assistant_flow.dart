import '../../../core/device/active_learning_module.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../listening/domain/listening_content.dart';
import '../../listening/domain/v4_completion_flow.dart';
import '../../vocabulary/data/vocabulary_store.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';
import '../domain/controlled_speech_lexicon.dart';
import '../domain/homi_fallback_catalog.dart';
import '../domain/master_navigation_contract.dart';
import 'active_learning_command_resolver.dart';
import 'voice_navigation_intent_resolver.dart';

enum MainVoiceAssistantStage {
  idle,
  chooseFeature,
  chooseOtherLearning,
  chooseModuleSwitch,
  chooseAfterTranslationStop,
  chooseAlternativeAfterLearning,
  chooseVocabularyCollection,
  activeLearning,
  askAge,
  chooseTopic,
  chooseTopicAfterCompletion,
  chooseCourseRelearnLevel,
  confirmReplayTopic,
  chooseLesson,
  confirmReplayLesson,
}

class MainVoiceAssistantUtterance {
  const MainVoiceAssistantUtterance(this.text, {this.locale = 'vi-VN'});

  final String text;
  final String locale;
}

class MainVoiceAssistantTurn {
  const MainVoiceAssistantTurn({
    required this.promptText,
    required this.continueListening,
    this.promptSequence = const <MainVoiceAssistantUtterance>[],
    this.onPromptCompleted,
    this.navigationBeforePrompt,
    this.navigationAfterPrompt,
    this.activeLearningCommand,
  });

  final String promptText;
  final bool continueListening;
  final List<MainVoiceAssistantUtterance> promptSequence;
  final Future<void> Function()? onPromptCompleted;
  final VoiceNavigationIntent? navigationBeforePrompt;
  final VoiceNavigationIntent? navigationAfterPrompt;
  final ActiveLearningCommand? activeLearningCommand;
}

/// Holds the multi-turn conversation started from the fixed Main button.
///
/// Topic and lesson counts are read from the same catalogs used by the UI, so
/// the spoken questions stay correct when learning content changes.
class MainVoiceAssistantFlow {
  MainVoiceAssistantFlow({
    List<ListeningAgeCatalog> catalogs = listeningCatalogs,
    Future<ListeningContentCatalog> Function()? contentLoader,
    Future<List<VocabularyEntry>> Function()? vocabularyLoader,
    Future<void> Function(Iterable<String>)? vocabularyIntroducedMarker,
    int? childAge,
  }) : _catalogs = catalogs,
       _contentLoader = contentLoader ?? _loadDefaultContent,
       _vocabularyLoader = vocabularyLoader ?? _loadDefaultVocabulary,
       _configuredChildAge = childAge;

  static const String openingPrompt = MasterNavigationContract.mainPrompt;
  static const String noSpeechRetryPrompt = MasterNavigationContract.mainRetry;
  static const String noSpeechExitPrompt = MasterNavigationContract.pause;
  static const String otherLearningPrompt =
      MasterNavigationContract.translationSwitch;
  static const String afterTranslationStopPrompt =
      MasterNavigationContract.afterTranslationStop;
  static const String activeLearningPrompt =
      MasterNavigationContract.coreControlPrompt;
  static const String courseRelearnLevelPrompt =
      'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?';
  static const String alternativeAfterLearningPrompt =
      MasterNavigationContract.translationSwitch;
  static const String stopPrompt = MasterNavigationContract.pause;
  static final String translationModeAcknowledgement =
      HomiFallbackCatalog.assistantPromptById['AI-020'] ??
      'Mình cùng dịch sang tiếng Anh nha.';
  static const String continuousTranslationPrompt =
      MasterNavigationContract.translationIntro;
  static const ActiveLearningCommandResolver _activeLearningCommandResolver =
      ActiveLearningCommandResolver();

  final List<ListeningAgeCatalog> _catalogs;
  final Future<ListeningContentCatalog> Function() _contentLoader;
  final Future<List<VocabularyEntry>> Function() _vocabularyLoader;

  int? _configuredChildAge;
  MainVoiceAssistantStage _stage = MainVoiceAssistantStage.idle;
  int? _selectedAge;
  ListeningAgeCatalog? _selectedCatalog;
  int? _selectedTopicNumber;
  ListeningTopicContent? _selectedTopicContent;
  Set<int> _completedTopicNumbers = const <int>{};
  Set<int> _allowedTopicNumbers = const <int>{};
  Set<int> _allowedLevelNumbers = const <int>{};
  int? _pendingReplayTopicNumber;
  Set<int> _completedLessonNumbers = const <int>{};
  int? _pendingReplayLessonNumber;
  ActiveLearningModuleKind? _activeLearningKind;
  ActiveLearningVoiceNode? _activeVoiceNode;
  String? _activeVoicePrompt;
  ActiveLearningVoiceSelectionContext? _activeVoiceSelection;
  bool _pausedChoice = false;
  final Map<MainVoiceAssistantStage, int> _fallbackAttempts =
      <MainVoiceAssistantStage, int>{};

  MainVoiceAssistantStage get stage => _stage;

  void setChildAge(int age) {
    if (_configuredChildAge == age) {
      return;
    }
    _configuredChildAge = age;
    reset();
  }

  String begin() {
    if (_pausedChoice) {
      _pausedChoice = false;
      _fallbackAttempts.clear();
      return currentPrompt;
    }
    reset();
    _stage = MainVoiceAssistantStage.chooseFeature;
    return openingPrompt;
  }

  String beginOtherLearning() {
    reset();
    _stage = MainVoiceAssistantStage.chooseOtherLearning;
    return otherLearningPrompt;
  }

  String beginAfterTranslationStop() {
    reset();
    _stage = MainVoiceAssistantStage.chooseAfterTranslationStop;
    return afterTranslationStopPrompt;
  }

  String beginActiveLearning({
    ActiveLearningModuleKind? kind,
    ActiveLearningVoiceContext? voiceContext,
  }) {
    reset();
    _activeLearningKind = kind;
    _activeVoiceNode = voiceContext?.mainVoiceNode;
    _activeVoicePrompt = voiceContext?.mainVoicePrompt;
    _activeVoiceSelection = voiceContext is ActiveLearningVoiceSelectionContext
        ? voiceContext as ActiveLearningVoiceSelectionContext
        : null;
    _stage = MainVoiceAssistantStage.activeLearning;
    return _activeVoicePrompt ?? activeLearningPrompt;
  }

  String beginLevelTopicSelection({
    required int childAge,
    required int levelNumber,
    required List<int> topicNumbers,
    required List<int> completedTopicNumbers,
    required bool announceLevel,
  }) {
    reset();
    final catalog = _catalogForAge(childAge);
    if (catalog == null || topicNumbers.isEmpty) {
      _stage = MainVoiceAssistantStage.chooseFeature;
      return openingPrompt;
    }
    _selectedAge = childAge;
    _selectedCatalog = catalog;
    _allowedTopicNumbers = topicNumbers.toSet();
    _completedTopicNumbers = completedTopicNumbers.toSet();
    _stage = MainVoiceAssistantStage.chooseTopicAfterCompletion;
    final levelLead = announceLevel ? 'Bắt đầu Level $levelNumber. ' : '';
    return '${levelLead}Có ${topicNumbers.length} Chủ đề. Bạn chọn Chủ đề số mấy?';
  }

  String beginCourseRelearnLevelSelection({
    required int childAge,
    required List<int> levelNumbers,
  }) {
    reset();
    final catalog = _catalogForAge(childAge);
    if (catalog == null || levelNumbers.isEmpty) {
      _stage = MainVoiceAssistantStage.chooseFeature;
      return openingPrompt;
    }
    _selectedAge = childAge;
    _selectedCatalog = catalog;
    _allowedLevelNumbers = levelNumbers.toSet();
    _stage = MainVoiceAssistantStage.chooseCourseRelearnLevel;
    return courseRelearnLevelPrompt;
  }

  String beginLessonSelectionForTopic({
    required int childAge,
    required int topicNumber,
    required ListeningTopicContent topicContent,
    required List<int> completedLessonNumbers,
  }) {
    reset();
    if (topicContent.lessons.isEmpty) {
      _stage = MainVoiceAssistantStage.chooseFeature;
      return 'Chủ đề này chưa có bài học. Bạn chọn Chủ đề khác nhé.';
    }
    _selectedAge = childAge;
    _selectedCatalog = _catalogForAge(childAge);
    _selectedTopicNumber = topicNumber;
    _selectedTopicContent = topicContent;
    _completedLessonNumbers = completedLessonNumbers
        .where((number) => number >= 1 && number <= topicContent.lessons.length)
        .toSet();
    if (_nextIncompleteLessonNumber == null) {
      _pendingReplayTopicNumber = topicNumber;
      _stage = MainVoiceAssistantStage.confirmReplayTopic;
      return _replayTopicPrompt;
    }
    _stage = MainVoiceAssistantStage.chooseLesson;
    return _lessonSelectionPrompt;
  }

  void reset() {
    _pausedChoice = false;
    _stage = MainVoiceAssistantStage.idle;
    _selectedAge = null;
    _selectedCatalog = null;
    _selectedTopicNumber = null;
    _selectedTopicContent = null;
    _completedTopicNumbers = const <int>{};
    _allowedTopicNumbers = const <int>{};
    _allowedLevelNumbers = const <int>{};
    _pendingReplayTopicNumber = null;
    _completedLessonNumbers = const <int>{};
    _pendingReplayLessonNumber = null;
    _activeLearningKind = null;
    _activeVoiceNode = null;
    _activeVoicePrompt = null;
    _activeVoiceSelection = null;
    _fallbackAttempts.clear();
  }

  void pauseChoice() {
    _pausedChoice =
        _stage != MainVoiceAssistantStage.idle &&
        _stage != MainVoiceAssistantStage.chooseFeature &&
        _stage != MainVoiceAssistantStage.activeLearning;
  }

  bool canHandle(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty || _looksLikePromptEcho(normalized)) {
      return false;
    }
    final stageCanHandle = _hasStageSpecificIntent(normalized);
    if (_isStopChoice(normalized)) {
      return _stage != MainVoiceAssistantStage.idle;
    }
    return stageCanHandle ||
        (_stage != MainVoiceAssistantStage.idle && _isHelpChoice(normalized));
  }

  /// Returns true only for a complete, unambiguous local command. The 500
  /// fallback phrases are resolved on-device once Android produces a stable
  /// partial transcript; number choices and broad phrases still wait for the
  /// final ASR result so "mình muốn học từ mới" never becomes a topic request
  /// before the final words arrive.
  bool canHandlePartial(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty || _looksLikePromptEcho(normalized)) {
      return false;
    }
    if (!_hasStageSpecificIntent(normalized) && !_isStopChoice(normalized)) {
      return false;
    }
    if (_isStopChoice(normalized)) {
      return _stage != MainVoiceAssistantStage.idle;
    }
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature ||
      MainVoiceAssistantStage.chooseOtherLearning ||
      MainVoiceAssistantStage.chooseModuleSwitch ||
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        _isUnambiguousFeatureChoice(normalized),
      MainVoiceAssistantStage.chooseAfterTranslationStop =>
        _isTopicChoice(normalized) ||
            _isVocabularyChoice(normalized) ||
            _isContinueTranslationChoice(normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        _isParentVocabularyChoice(normalized) ||
            _isReviewVocabularyChoice(normalized) ||
            _isStarVocabularyChoice(normalized),
      MainVoiceAssistantStage.activeLearning =>
        _resolveActiveCommand(normalized) != null ||
            _isTopicChoice(normalized) ||
            _isVocabularyChoice(normalized) ||
            _isTranslationChoice(normalized) ||
            _isSwitchModuleMenuChoice(normalized) ||
            (_activeVoiceNode == null &&
                _isLeaveActiveLearningChoice(normalized)),
      MainVoiceAssistantStage.confirmReplayTopic =>
        _isReplayTopicChoice(normalized) || _isOtherTopicChoice(normalized),
      MainVoiceAssistantStage.confirmReplayLesson =>
        _isReplayLessonChoice(normalized) ||
            _isContinueLessonChoice(normalized) ||
            _hasSelectableLessonNumber(normalized),
      // A number can arrive after a partial prefix ("chủ đề số ..."), so
      // selecting age, topic, or lesson always waits for the final transcript.
      MainVoiceAssistantStage.askAge ||
      MainVoiceAssistantStage.chooseTopic ||
      MainVoiceAssistantStage.chooseTopicAfterCompletion ||
      MainVoiceAssistantStage.chooseCourseRelearnLevel ||
      MainVoiceAssistantStage.chooseLesson ||
      MainVoiceAssistantStage.idle => false,
    };
  }

  bool _hasStageSpecificIntent(String normalized) => switch (_stage) {
    MainVoiceAssistantStage.chooseFeature =>
      _isSpeakingChoice(normalized) ||
          _isTopicChoice(normalized) ||
          _isVocabularyChoice(normalized) ||
          _isTranslationChoice(normalized),
    MainVoiceAssistantStage.chooseOtherLearning =>
      _isTopicChoice(normalized) ||
          _isVocabularyChoice(normalized) ||
          _isContinueTranslationChoice(normalized),
    MainVoiceAssistantStage.chooseModuleSwitch =>
      _isTopicChoice(normalized) ||
          _isVocabularyChoice(normalized) ||
          _isTranslationChoice(normalized),
    MainVoiceAssistantStage.chooseAfterTranslationStop =>
      _isTopicChoice(normalized) ||
          _isVocabularyChoice(normalized) ||
          _isContinueTranslationChoice(normalized),
    MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
      _isVocabularyChoice(normalized) || _isTranslationChoice(normalized),
    MainVoiceAssistantStage.chooseVocabularyCollection =>
      _isParentVocabularyChoice(normalized) ||
          _isReviewVocabularyChoice(normalized) ||
          _isStarVocabularyChoice(normalized),
    MainVoiceAssistantStage.activeLearning =>
      _resolveActiveCommand(normalized) != null ||
          _isTopicChoice(normalized) ||
          _isVocabularyChoice(normalized) ||
          _isTranslationChoice(normalized) ||
          _isSwitchModuleMenuChoice(normalized) ||
          (_activeVoiceNode == null &&
              _isLeaveActiveLearningChoice(normalized)),
    MainVoiceAssistantStage.confirmReplayTopic =>
      _isReplayTopicChoice(normalized) || _isOtherTopicChoice(normalized),
    MainVoiceAssistantStage.confirmReplayLesson =>
      _isReplayLessonChoice(normalized) ||
          _isContinueLessonChoice(normalized) ||
          _hasSelectableLessonNumber(normalized),
    MainVoiceAssistantStage.askAge ||
    MainVoiceAssistantStage.chooseTopic ||
    MainVoiceAssistantStage.chooseTopicAfterCompletion ||
    MainVoiceAssistantStage.chooseCourseRelearnLevel => switch (_stage) {
      MainVoiceAssistantStage.askAge =>
        _extractSpokenNumber(normalized) != null,
      MainVoiceAssistantStage.chooseCourseRelearnLevel =>
        _extractSpokenNumber(normalized) != null,
      MainVoiceAssistantStage.chooseTopicAfterCompletion
          when _allowedTopicNumbers.isNotEmpty =>
        _extractSpokenNumber(normalized) != null,
      _ => _hasSelectableTopicNumber(normalized),
    },
    MainVoiceAssistantStage.chooseLesson =>
      _hasSelectableLessonNumber(normalized) ||
          _isContinueLessonChoice(normalized),
    MainVoiceAssistantStage.idle => false,
  };

  Future<MainVoiceAssistantTurn> handle(String recognizedText) async {
    final normalized = _normalize(recognizedText);
    final isPromptEcho = _looksLikePromptEcho(normalized);
    final stageCanHandle = _hasStageSpecificIntent(normalized);
    if (_isStopChoice(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: stopPrompt,
        continueListening: false,
        activeLearningCommand: _stage == MainVoiceAssistantStage.activeLearning
            ? ActiveLearningCommand.stop
            : null,
      );
    }
    if (_isHelpChoice(normalized)) {
      return _helpTurn();
    }
    if (!stageCanHandle &&
        !isPromptEcho &&
        _stage != MainVoiceAssistantStage.idle) {
      final fallback = _fallbackForUnrecognizedInput();
      if (fallback != null) {
        return fallback;
      }
    } else {
      _fallbackAttempts.remove(_stage);
    }
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature => await _handleFeature(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseOtherLearning => await _handleOtherLearning(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseModuleSwitch => _handleModuleSwitch(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseAfterTranslationStop =>
        await _handleAfterTranslationStop(recognizedText, normalized),
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        await _handleAlternativeAfterLearning(recognizedText, normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        await _handleVocabularyCollection(normalized),
      MainVoiceAssistantStage.activeLearning => _handleActiveLearning(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.askAge => _handleAge(recognizedText, normalized),
      MainVoiceAssistantStage.chooseTopic => await _handleTopic(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        await _handleTopicAfterCompletion(recognizedText, normalized),
      MainVoiceAssistantStage.chooseCourseRelearnLevel =>
        _handleCourseRelearnLevel(recognizedText, normalized),
      MainVoiceAssistantStage.confirmReplayTopic =>
        await _handleReplayTopicConfirmation(recognizedText, normalized),
      MainVoiceAssistantStage.chooseLesson => _handleLesson(
        recognizedText,
        normalized,
      ),
      MainVoiceAssistantStage.confirmReplayLesson =>
        _handleReplayLessonConfirmation(recognizedText, normalized),
      MainVoiceAssistantStage.idle => const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      ),
    };
  }

  MainVoiceAssistantTurn _beginConfiguredTopicSelection(String recognizedText) {
    final age = _configuredChildAge;
    final catalog = age == null ? null : _catalogForAge(age);
    if (age == null || catalog == null) {
      // The destination resolves age from the saved profile/onboarding.
      // Voice navigation must never open the retired AGE_NUMBER flow.
      reset();
      return MainVoiceAssistantTurn(
        promptText: '',
        continueListening: false,
        navigationBeforePrompt: VoiceNavigationIntent(
          destination: VoiceNavigationDestination.topics,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'chu de',
        ),
      );
    }
    return _openLevelTopicCatalog(
      recognizedText: recognizedText,
      childAge: age,
    );
  }

  MainVoiceAssistantTurn _openLevelTopicCatalog({
    required String recognizedText,
    required int childAge,
  }) {
    final intent = VoiceNavigationIntent(
      destination: VoiceNavigationDestination.topics,
      recognizedText: recognizedText.trim(),
      matchedPhrase: 'hoc theo chu de',
      childAge: childAge,
    );
    // TopicListeningScreen owns Level/progress resolution. Keeping that state
    // out of MAIN prevents the legacy all-course count (10) from overriding
    // the FINAL Level-scoped prompt (3/3/4 with the current content).
    reset();
    return MainVoiceAssistantTurn(
      promptText: '',
      continueListening: false,
      navigationBeforePrompt: intent,
    );
  }

  ListeningAgeCatalog? _catalogForAge(int age) {
    for (final candidate in _catalogs) {
      if (age >= candidate.startAge && age <= candidate.endAge) {
        return candidate;
      }
    }
    return null;
  }

  Future<MainVoiceAssistantTurn> _handleFeature(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: openingPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _beginVocabularyLearning(
        recognizedText: recognizedText,
        matchedPhrase: 'hoc tu moi',
      );
    }
    if (_isTopicChoice(normalized)) {
      return _beginConfiguredTopicSelection(recognizedText);
    }
    if (_isTranslationChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    if (_isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: openingPrompt,
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _handleOtherLearning(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: otherLearningPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _moduleNavigationTurn(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.vocabulary,
        promptText: MasterNavigationContract.switchedToVocabulary,
      );
    }
    if (_isTopicChoice(normalized)) {
      return _moduleNavigationTurn(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.topics,
        promptText: MasterNavigationContract.switchedToSubject,
      );
    }
    if (_isContinueTranslationChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText, resuming: true);
    }
    if (_isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: otherLearningPrompt,
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _handleAfterTranslationStop(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: afterTranslationStopPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _moduleNavigationTurn(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.vocabulary,
        promptText: MasterNavigationContract.switchedToVocabulary,
      );
    }
    if (_isTopicChoice(normalized)) {
      return _moduleNavigationTurn(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.topics,
        promptText: MasterNavigationContract.switchedToSubject,
      );
    }
    if (_isContinueTranslationChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText, resuming: true);
    }
    return const MainVoiceAssistantTurn(
      promptText: afterTranslationStopPrompt,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _beginContinuousTranslation(
    String recognizedText, {
    bool resuming = false,
  }) {
    reset();
    return MainVoiceAssistantTurn(
      promptText: resuming
          ? MasterNavigationContract.translationContinue
          : continuousTranslationPrompt,
      continueListening: false,
      navigationAfterPrompt: VoiceNavigationIntent(
        destination: VoiceNavigationDestination.conversation,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'lien tuc',
        enterMainSpeakingMode: true,
      ),
    );
  }

  MainVoiceAssistantTurn _moduleNavigationTurn({
    required String recognizedText,
    required VoiceNavigationDestination destination,
    required String promptText,
  }) {
    final turn = MainVoiceAssistantTurn(
      promptText: promptText,
      continueListening: false,
      navigationAfterPrompt: VoiceNavigationIntent(
        destination: destination,
        recognizedText: recognizedText.trim(),
        matchedPhrase: switch (destination) {
          VoiceNavigationDestination.topics => 'chu de',
          VoiceNavigationDestination.vocabulary => 'bo tu vung',
          VoiceNavigationDestination.conversation => 'dich tieng anh',
          VoiceNavigationDestination.history => 'lich su',
          VoiceNavigationDestination.settings => 'cai dat',
        },
        childAge: destination == VoiceNavigationDestination.topics
            ? _configuredChildAge
            : null,
        enterMainSpeakingMode:
            destination == VoiceNavigationDestination.conversation,
      ),
    );
    reset();
    return turn;
  }

  Future<MainVoiceAssistantTurn> _handleAlternativeAfterLearning(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: alternativeAfterLearningPrompt,
        continueListening: true,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _beginVocabularyLearning(
        recognizedText: recognizedText,
        matchedPhrase: 'hoc tu vung',
      );
    }
    if (_isTranslationChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    if (_isSpeakingChoice(normalized)) {
      return _beginContinuousTranslation(recognizedText);
    }
    return const MainVoiceAssistantTurn(
      promptText: alternativeAfterLearningPrompt,
      continueListening: true,
    );
  }

  Future<MainVoiceAssistantTurn> _beginVocabularyLearning({
    required String recognizedText,
    required String matchedPhrase,
  }) async {
    final navigation = VoiceNavigationIntent(
      destination: VoiceNavigationDestination.vocabulary,
      recognizedText: recognizedText.trim(),
      matchedPhrase: matchedPhrase,
    );
    // VocabularyHomeScreen is the single V3 state machine. Navigating only
    // after the silent handoff prevents MAIN from narrating an older parallel
    // flow while the shared Android/iOS module creates today's batch, speaks
    // its exact intro/menu, and opens the next microphone window itself.
    reset();
    return MainVoiceAssistantTurn(
      promptText: '',
      continueListening: false,
      navigationBeforePrompt: navigation,
    );
  }

  Future<MainVoiceAssistantTurn> _handleVocabularyCollection(
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: 'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?',
        continueListening: true,
      );
    }
    final parentChoice = _isParentVocabularyChoice(normalized);
    final collection = parentChoice
        ? VocabularyCollection.saved
        : _isReviewVocabularyChoice(normalized)
        ? VocabularyCollection.review
        : _isStarVocabularyChoice(normalized)
        ? VocabularyCollection.star
        : null;
    if (collection == null) {
      return const MainVoiceAssistantTurn(
        promptText: 'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?',
        continueListening: true,
      );
    }

    final entries = await _loadVocabularyOrNull();
    if (entries == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'HOMI chưa tải được Bộ từ vựng. Bạn thử lại sau nhé.',
        continueListening: false,
      );
    }
    final selected = parentChoice
        ? entries
              .where(
                (entry) =>
                    entry.isParentAdded &&
                    entry.isLearnedWell &&
                    entry.word.trim().isNotEmpty,
              )
              .toList(growable: false)
        : _entriesIn(entries, collection);
    final title = parentChoice
        ? 'Phần Ba mẹ đã thêm.'
        : collection == VocabularyCollection.review
        ? 'Phần luyện lại.'
        : 'Ngôi sao của bạn.';
    final emptyPrompt = parentChoice
        ? 'Chưa có nội dung đã học tốt trong phần Ba mẹ đã thêm.'
        : collection == VocabularyCollection.review
        ? 'Phần luyện lại chưa có từ nào.'
        : 'Bạn chưa có Ngôi sao nào.';
    final utterances = <MainVoiceAssistantUtterance>[];
    _appendVocabularyCollection(
      utterances,
      title: title,
      emptyPrompt: emptyPrompt,
      entries: selected,
    );
    utterances.add(
      const MainVoiceAssistantUtterance('Mình đã học xong từ vựng rồi.'),
    );
    reset();
    return MainVoiceAssistantTurn(
      promptText: _plainPrompt(utterances),
      promptSequence: utterances,
      continueListening: false,
    );
  }

  Future<List<VocabularyEntry>?> _loadVocabularyOrNull() async {
    try {
      return await _vocabularyLoader();
    } catch (_) {
      return null;
    }
  }

  static List<VocabularyEntry> _entriesIn(
    List<VocabularyEntry> entries,
    VocabularyCollection collection,
  ) => entries
      .where(
        (entry) =>
            entry.collection == collection && entry.word.trim().isNotEmpty,
      )
      .toList(growable: false);

  static void _appendVocabularyCollection(
    List<MainVoiceAssistantUtterance> utterances, {
    required String title,
    required String emptyPrompt,
    required List<VocabularyEntry> entries,
  }) {
    if (entries.isEmpty) {
      utterances.add(MainVoiceAssistantUtterance(emptyPrompt));
      return;
    }
    utterances.add(MainVoiceAssistantUtterance(title));
    _appendVocabularyEntries(utterances, entries);
  }

  static void _appendVocabularyEntries(
    List<MainVoiceAssistantUtterance> utterances,
    List<VocabularyEntry> entries,
  ) {
    for (final entry in entries) {
      utterances.add(
        MainVoiceAssistantUtterance(entry.word.trim(), locale: 'en-US'),
      );
      final meaning = entry.meaning.trim();
      if (meaning.isNotEmpty) {
        utterances.add(MainVoiceAssistantUtterance(meaning));
      }
    }
  }

  static String _plainPrompt(List<MainVoiceAssistantUtterance> utterances) =>
      utterances.map((item) => item.text).join(' ');

  ActiveLearningCommand? _resolveActiveCommand(String normalized) {
    final selection = _activeVoiceSelection;
    if (selection != null && selection.isMainVoiceChoice) {
      return selection.resolveMainVoiceChoice(normalized);
    }
    return _activeLearningCommandResolver.resolve(
      normalized,
      state: _activeLearningSpeechState,
      node: _activeVoiceNode,
    );
  }

  MainVoiceAssistantTurn _handleActiveLearning(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _activeVoicePrompt ?? activeLearningPrompt,
        continueListening: true,
      );
    }
    // The FINAL contract makes OPEN_SUBJECT / OPEN_VOCAB / OPEN_TRANSLATE
    // global while learning. Resolve those explicit transfers before the
    // local lesson grammar so an overlapping phrase such as "Cho mình học
    // bài" cannot be consumed as an item-level action.
    if (_isTopicChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.topics,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.vocabulary,
      );
    }
    if (_isTranslationChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.conversation,
      );
    }
    if (_isSwitchModuleMenuChoice(normalized) ||
        (_activeVoiceNode == null &&
            _isLeaveActiveLearningChoice(normalized))) {
      _stage = MainVoiceAssistantStage.chooseModuleSwitch;
      _fallbackAttempts.remove(_stage);
      return const MainVoiceAssistantTurn(
        promptText: MasterNavigationContract.translationSwitch,
        continueListening: true,
      );
    }
    final command = _resolveActiveCommand(normalized);
    if (command != null) {
      return _activeLearningTurn(command);
    }
    return MainVoiceAssistantTurn(
      promptText: _activeVoicePrompt ?? activeLearningPrompt,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _handleModuleSwitch(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: MasterNavigationContract.translationSwitch,
        continueListening: true,
      );
    }
    if (_isTopicChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.topics,
      );
    }
    if (_isVocabularyChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.vocabulary,
      );
    }
    if (_isTranslationChoice(normalized)) {
      return _switchFromActiveLearning(
        recognizedText: recognizedText,
        destination: VoiceNavigationDestination.conversation,
      );
    }
    return const MainVoiceAssistantTurn(
      promptText: MasterNavigationContract.translationSwitch,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _switchFromActiveLearning({
    required String recognizedText,
    required VoiceNavigationDestination destination,
  }) {
    final sameModule = switch ((_activeLearningKind, destination)) {
      (
        ActiveLearningModuleKind.listeningLesson,
        VoiceNavigationDestination.topics,
      ) =>
        true,
      (
        ActiveLearningModuleKind.vocabulary,
        VoiceNavigationDestination.vocabulary,
      ) =>
        true,
      _ => false,
    };
    if (sameModule) {
      final promptText = switch (_activeLearningKind) {
        ActiveLearningModuleKind.listeningLesson =>
          MasterNavigationContract.continueSubject,
        ActiveLearningModuleKind.vocabulary =>
          MasterNavigationContract.continueVocabulary,
        null => MasterNavigationContract.keepCurrentContent,
      };
      return MainVoiceAssistantTurn(
        promptText: promptText,
        continueListening: false,
        activeLearningCommand: ActiveLearningCommand.resume,
      );
    }
    final promptText = switch (destination) {
      VoiceNavigationDestination.topics =>
        MasterNavigationContract.switchedToSubject,
      VoiceNavigationDestination.vocabulary =>
        MasterNavigationContract.switchedToVocabulary,
      VoiceNavigationDestination.conversation =>
        MasterNavigationContract.switchedToTranslation,
      VoiceNavigationDestination.history => 'Mình đã chuyển sang Lịch sử.',
      VoiceNavigationDestination.settings => 'Mình đã chuyển sang Cài đặt.',
    };
    return _moduleNavigationTurn(
      recognizedText: recognizedText,
      destination: destination,
      promptText: promptText,
    );
  }

  MainVoiceAssistantTurn _activeLearningTurn(ActiveLearningCommand command) {
    final isVocabulary =
        _activeLearningKind == ActiveLearningModuleKind.vocabulary;
    final promptText = switch (command) {
      ActiveLearningCommand.resume =>
        isVocabulary ||
                _activeVoiceNode == ActiveLearningVoiceNode.core ||
                _activeVoiceNode == ActiveLearningVoiceNode.challenge
            ? ''
            : 'Cùng học tiếp nhé',
      ActiveLearningCommand.replayCurrent =>
        isVocabulary ? '' : 'Mình nghe lại câu này nhé',
      ActiveLearningCommand.nextItem =>
        isVocabulary
            ? ''
            : _activeVoiceNode == ActiveLearningVoiceNode.song
            ? MasterNavigationContract.songSkipped
            : 'Mình học câu tiếp theo nhé',
      ActiveLearningCommand.previousItem => 'Mình nghe lại câu trước nhé',
      ActiveLearningCommand.nextLesson => 'Mình chuyển sang bài tiếp theo nhé',
      ActiveLearningCommand.previousLesson => 'Mình quay lại bài trước nhé',
      ActiveLearningCommand.restart => 'Mình học lại bài này từ đầu nhé',
      ActiveLearningCommand.stop => 'Đã dừng.',
      ActiveLearningCommand.exitToHome =>
        isVocabulary ? '' : 'Mình kết thúc bài học nhé',
      ActiveLearningCommand.vocabularyParentAdded ||
      ActiveLearningCommand.vocabularyPracticeAgain ||
      ActiveLearningCommand.vocabularyStars ||
      ActiveLearningCommand.vocabularyLatest ||
      ActiveLearningCommand.vocabularyAll => '',
    };
    return MainVoiceAssistantTurn(
      promptText: (_activeVoiceSelection?.isMainVoiceChoice ?? false)
          ? ''
          : promptText,
      continueListening: false,
      activeLearningCommand: command,
    );
  }

  MainVoiceAssistantTurn _handleAge(String recognizedText, String normalized) {
    final age = _extractSpokenNumber(normalized);
    if (age == null) {
      return const MainVoiceAssistantTurn(
        promptText: 'Bạn mấy tuổi? Ví dụ bạn nói: 6 tuổi.',
        continueListening: true,
      );
    }

    final catalog = _catalogForAge(age);
    if (catalog == null) {
      final minimumAge = _catalogs.isEmpty ? 0 : _catalogs.first.startAge;
      final maximumAge = _catalogs.isEmpty ? 0 : _catalogs.last.endAge;
      return MainVoiceAssistantTurn(
        promptText:
            'HOMI có bài học cho các bạn từ $minimumAge đến $maximumAge tuổi. Bạn mấy tuổi?',
        continueListening: true,
      );
    }

    return _openLevelTopicCatalog(
      recognizedText: recognizedText,
      childAge: age,
    );
  }

  Future<MainVoiceAssistantTurn> _handleTopic(
    String recognizedText,
    String normalized,
  ) async {
    final catalog = _selectedCatalog;
    final age = _selectedAge;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog?.topics.length ?? 0} Chủ đề. Bạn chọn Chủ đề số mấy?',
        continueListening: true,
      );
    }
    final topicNumber = _extractSpokenNumber(normalized);
    if (catalog == null || age == null) {
      return _beginConfiguredTopicSelection(recognizedText);
    }
    if (topicNumber == null ||
        topicNumber < 1 ||
        topicNumber > catalog.topics.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog.topics.length} Chủ đề. Bạn chọn từ số 1 đến số ${catalog.topics.length}.',
        continueListening: true,
      );
    }
    return _openTopic(recognizedText: recognizedText, topicNumber: topicNumber);
  }

  Future<MainVoiceAssistantTurn> _openTopic({
    required String recognizedText,
    required int topicNumber,
    bool relearnTopic = false,
  }) async {
    final catalog = _selectedCatalog;
    final age = _selectedAge;
    if (catalog == null || age == null) {
      return _beginConfiguredTopicSelection(recognizedText);
    }
    try {
      final content = await _contentLoader();
      final topicContent = content.topic(
        startAge: catalog.startAge,
        endAge: catalog.endAge,
        topicNumber: topicNumber,
      );
      if (topicContent.lessons.isEmpty) {
        reset();
        return const MainVoiceAssistantTurn(
          promptText: 'Chủ đề này chưa có bài học. Bạn thử lại sau nhé.',
          continueListening: false,
        );
      }
      // The topic owner decides the next lesson from saved progress.
      // MAIN must never expose a second, free lesson picker.
      final intent = VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'chu de so $topicNumber',
        topicNumber: topicNumber,
        childAge: age,
        relearnTopic: relearnTopic,
      );
      reset();
      return MainVoiceAssistantTurn(
        promptText: '',
        continueListening: false,
        navigationBeforePrompt: intent,
      );
    } catch (_) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'HOMI chưa tải được bài học. Bạn thử lại sau nhé.',
        continueListening: false,
      );
    }
  }

  Future<MainVoiceAssistantTurn> _handleTopicAfterCompletion(
    String recognizedText,
    String normalized,
  ) async {
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _topicSelectionPrompt,
        continueListening: true,
      );
    }
    final catalog = _selectedCatalog;
    final topicNumber = _extractSpokenNumber(normalized);
    if (catalog == null || _selectedAge == null) {
      return _beginConfiguredTopicSelection(recognizedText);
    }
    if (_allowedTopicNumbers.isNotEmpty &&
        (topicNumber == null ||
            topicNumber < 1 ||
            topicNumber > catalog.topics.length)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Level này có ${_allowedTopicNumbers.length} Chủ đề. Bạn chọn lại nhé.',
        continueListening: true,
      );
    }
    if (topicNumber == null ||
        topicNumber < 1 ||
        topicNumber > catalog.topics.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${catalog.topics.length} Chủ đề. Bạn chọn từ số 1 đến số ${catalog.topics.length}.',
        continueListening: true,
      );
    }
    if (_allowedTopicNumbers.isNotEmpty &&
        !_allowedTopicNumbers.contains(topicNumber)) {
      return MainVoiceAssistantTurn(
        promptText:
            'Level này có ${_allowedTopicNumbers.length} Chủ đề. Bạn chọn lại nhé.',
        continueListening: true,
      );
    }
    if (_completedTopicNumbers.contains(topicNumber)) {
      _pendingReplayTopicNumber = topicNumber;
      _stage = MainVoiceAssistantStage.confirmReplayTopic;
      return MainVoiceAssistantTurn(
        promptText: _replayTopicPrompt,
        continueListening: true,
      );
    }
    return _openTopic(recognizedText: recognizedText, topicNumber: topicNumber);
  }

  MainVoiceAssistantTurn _handleCourseRelearnLevel(
    String recognizedText,
    String normalized,
  ) {
    if (_looksLikePromptEcho(normalized)) {
      return const MainVoiceAssistantTurn(
        promptText: courseRelearnLevelPrompt,
        continueListening: true,
      );
    }
    final levelNumber = _extractSpokenNumber(normalized);
    final childAge = _selectedAge;
    if (levelNumber == null ||
        childAge == null ||
        !_allowedLevelNumbers.contains(levelNumber)) {
      final available = _allowedLevelNumbers.toList()..sort();
      return MainVoiceAssistantTurn(
        promptText: 'Bạn chọn Level ${available.join(', ')} nhé.',
        continueListening: true,
      );
    }
    final intent = VoiceNavigationIntent(
      destination: VoiceNavigationDestination.topics,
      recognizedText: recognizedText.trim(),
      matchedPhrase: 'hoc lai level $levelNumber',
      childAge: childAge,
      levelNumber: levelNumber,
      relearnLevel: true,
    );
    reset();
    return MainVoiceAssistantTurn(
      promptText: '',
      continueListening: false,
      navigationBeforePrompt: intent,
    );
  }

  Future<MainVoiceAssistantTurn> _handleReplayTopicConfirmation(
    String recognizedText,
    String normalized,
  ) async {
    final topicNumber = _pendingReplayTopicNumber;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _replayTopicPrompt,
        continueListening: true,
      );
    }
    if (_isReplayTopicChoice(normalized) && topicNumber != null) {
      _pendingReplayTopicNumber = null;
      return _openTopic(
        recognizedText: recognizedText,
        topicNumber: topicNumber,
        relearnTopic: true,
      );
    }
    if (_isOtherTopicChoice(normalized)) {
      if (_allowedTopicNumbers.isEmpty) {
        final intent = VoiceNavigationIntent(
          destination: VoiceNavigationDestination.topics,
          recognizedText: recognizedText.trim(),
          matchedPhrase: 'chu de khac',
          childAge: _selectedAge,
        );
        reset();
        return MainVoiceAssistantTurn(
          promptText: '',
          continueListening: false,
          navigationBeforePrompt: intent,
        );
      }
      _pendingReplayTopicNumber = null;
      _stage = MainVoiceAssistantStage.chooseTopicAfterCompletion;
      return MainVoiceAssistantTurn(
        promptText: _topicSelectionPrompt,
        continueListening: true,
      );
    }
    return MainVoiceAssistantTurn(
      promptText: _replayTopicPrompt,
      continueListening: true,
    );
  }

  String get _topicSelectionPrompt =>
      'Có ${_allowedTopicNumbers.length} Chủ đề. Bạn chọn Chủ đề số mấy?';

  String get _replayTopicPrompt =>
      'Chủ đề $_pendingReplayTopicNumber bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề $_pendingReplayTopicNumber?';

  bool _isReplayTopicChoice(String text) {
    if (MasterNavigationContract.matches('RELEARN_TOPIC', text)) return true;
    final number = _pendingReplayTopicNumber;
    return number != null &&
        <String>[
          'chu de $number',
          'hoc lai chu de $number',
          'minh muon hoc lai chu de $number',
          'lam lai chu de $number',
        ].contains(text);
  }

  static bool _isOtherTopicChoice(String text) =>
      MasterNavigationContract.matches('OTHER_TOPIC', text);

  MainVoiceAssistantTurn _handleLesson(
    String recognizedText,
    String normalized,
  ) {
    final age = _selectedAge;
    final topicNumber = _selectedTopicNumber;
    final topicContent = _selectedTopicContent;
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _lessonSelectionPrompt,
        continueListening: true,
      );
    }
    if (age == null || topicNumber == null || topicContent == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'HOMI chưa chọn được Chủ đề. Bạn thử lại nhé.',
        continueListening: false,
      );
    }
    if (_isContinueLessonChoice(normalized)) {
      if (normalized == 'hoc tiep') {
        return MainVoiceAssistantTurn(
          promptText: _lessonSelectionPrompt,
          continueListening: true,
        );
      }
      final nextLesson = _nextIncompleteLessonNumber;
      if (nextLesson != null) {
        return _openLessonTurn(
          recognizedText: recognizedText,
          lessonNumber: nextLesson,
        );
      }
      return MainVoiceAssistantTurn(
        promptText:
            'Bạn đã học xong cả ${topicContent.lessons.length} Bài rồi. Bạn muốn học lại Bài số mấy?',
        continueListening: true,
      );
    }
    final lessonNumber = _extractSpokenNumber(normalized);
    if (lessonNumber == null ||
        lessonNumber < 1 ||
        lessonNumber > topicContent.lessons.length) {
      return MainVoiceAssistantTurn(
        promptText:
            'Có ${topicContent.lessons.length} Bài học. Bạn chọn từ số 1 đến số ${topicContent.lessons.length}.',
        continueListening: true,
      );
    }

    if (_completedLessonNumbers.contains(lessonNumber)) {
      _pendingReplayLessonNumber = lessonNumber;
      _stage = MainVoiceAssistantStage.confirmReplayLesson;
      return MainVoiceAssistantTurn(
        promptText: _replayLessonConfirmationPrompt(lessonNumber),
        continueListening: true,
      );
    }

    final firstIncomplete = _nextIncompleteLessonNumber;
    if (firstIncomplete != null && lessonNumber > firstIncomplete) {
      return MainVoiceAssistantTurn(
        promptText: 'Bạn cần học xong Bài $firstIncomplete trước nhé.',
        continueListening: true,
      );
    }
    return _openLessonTurn(
      recognizedText: recognizedText,
      lessonNumber: lessonNumber,
    );
  }

  MainVoiceAssistantTurn _handleReplayLessonConfirmation(
    String recognizedText,
    String normalized,
  ) {
    final replayLesson = _pendingReplayLessonNumber;
    if (replayLesson == null || _selectedTopicContent == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'HOMI chưa chọn được Bài học. Bạn thử lại nhé.',
        continueListening: false,
      );
    }
    if (_looksLikePromptEcho(normalized)) {
      return MainVoiceAssistantTurn(
        promptText: _replayLessonConfirmationPrompt(replayLesson),
        continueListening: true,
      );
    }
    final choice = const V4CompletionChoiceResolver().resolve(
      recognizedText,
      stage: V4CompletionStage.lessonEnd,
      currentLesson: replayLesson,
      nextLesson: _nextIncompleteLessonNumber,
    );
    if (choice == V4CompletionAction.nextLesson) {
      final nextLesson = _nextIncompleteLessonNumber;
      if (nextLesson != null) {
        _pendingReplayLessonNumber = null;
        return _openLessonTurn(
          recognizedText: recognizedText,
          lessonNumber: nextLesson,
        );
      }
      _stage = MainVoiceAssistantStage.chooseLesson;
      return MainVoiceAssistantTurn(
        promptText:
            'Bạn đã học xong cả ${_selectedTopicContent!.lessons.length} Bài rồi. Bạn chọn một Bài để học lại nhé.',
        continueListening: true,
      );
    }
    if (choice == V4CompletionAction.relearnCurrentLesson) {
      _pendingReplayLessonNumber = null;
      return _openLessonTurn(
        recognizedText: recognizedText,
        lessonNumber: replayLesson,
        relearnLesson: true,
      );
    }
    return MainVoiceAssistantTurn(
      promptText: _replayLessonConfirmationPrompt(replayLesson),
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn _openLessonTurn({
    required String recognizedText,
    required int lessonNumber,
    bool relearnLesson = false,
  }) {
    final age = _selectedAge;
    final topicNumber = _selectedTopicNumber;
    if (age == null || topicNumber == null) {
      reset();
      return const MainVoiceAssistantTurn(
        promptText: 'HOMI chưa chọn được Chủ đề. Bạn thử lại nhé.',
        continueListening: false,
      );
    }

    return MainVoiceAssistantTurn(
      promptText: 'Bắt đầu nhé.',
      continueListening: false,
      navigationAfterPrompt: VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'bai so $lessonNumber',
        topicNumber: topicNumber,
        lessonNumber: lessonNumber,
        childAge: age,
        openLesson: true,
        relearnLesson: relearnLesson,
      ),
    );
  }

  String get _lessonSelectionPrompt {
    final nextLesson = _nextIncompleteLessonNumber;
    if (nextLesson == null) {
      return 'Bạn đã học xong Chủ đề này. Bạn muốn học lại Chủ đề hay dừng lại?';
    }
    final completed = _completedLessonNumbers.toList()..sort();
    if (completed.isEmpty) {
      return 'Bạn muốn bắt đầu Bài $nextLesson hay dừng lại?';
    }
    return 'Bạn muốn học Bài $nextLesson hay học lại Bài ${completed.last}?';
  }

  int? get _nextIncompleteLessonNumber {
    final topicContent = _selectedTopicContent;
    if (topicContent == null) {
      return null;
    }
    for (final lesson in topicContent.lessons) {
      if (!_completedLessonNumbers.contains(lesson.number)) {
        return lesson.number;
      }
    }
    return null;
  }

  String _replayLessonConfirmationPrompt(int replayLesson) {
    final nextLesson = _nextIncompleteLessonNumber;
    return nextLesson == null
        ? 'Bạn muốn học lại Bài $replayLesson hay dừng lại?'
        : 'Bạn muốn học Bài $nextLesson hay học lại Bài $replayLesson?';
  }

  static bool _isSpeakingChoice(String normalized) => const {
    'luyen noi',
    'luyen giao tiep',
    'noi chuyen',
    'con muon noi',
    'con muon luyen noi',
    'con ghi muon luyen noi',
    'con muon luyen giao tiep',
    'con muon noi chuyen',
    'noi',
  }.contains(normalized);

  static bool _isUnambiguousFeatureChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc tu vung') ||
      _containsPhrase(normalized, 'hoc tu moi') ||
      _containsPhrase(normalized, 'luyen tu') ||
      _containsPhrase(normalized, 'tu vung') ||
      _containsPhrase(normalized, 'tu moi') ||
      _containsPhrase(normalized, 'hoc theo chu de') ||
      _containsPhrase(normalized, 'hoc chu de') ||
      _containsPhrase(normalized, 'hoc tinh huong') ||
      _containsPhrase(normalized, 'dich tieng anh') ||
      _containsPhrase(normalized, 'dich sang tieng anh') ||
      _containsPhrase(normalized, 'luyen noi') ||
      _containsPhrase(normalized, 'luyen giao tiep') ||
      _containsPhrase(normalized, 'noi chuyen');

  ControlledSpeechState get _activeLearningSpeechState =>
      _activeLearningKind == ActiveLearningModuleKind.vocabulary
      ? ControlledSpeechState.vocabulary
      : ControlledSpeechState.course;

  static bool _isStopChoice(String normalized) =>
      MasterNavigationContract.matches('STOP_GLOBAL', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-001');

  static bool _isHelpChoice(String normalized) =>
      MasterNavigationContract.matches('HELP', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-016');

  static bool _isTopicChoice(String normalized) =>
      MasterNavigationContract.matches('OPEN_SUBJECT', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-002') ||
      const {
        'con muon hoc chu de',
        'con muon hoc theo chu de',
        'bat dau bai hoc',
        'hoc khoa hoc',
        'hoc bai',
      }.contains(normalized);

  static bool _isVocabularyChoice(String normalized) =>
      MasterNavigationContract.matches('OPEN_VOCAB', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-003') ||
      const {
        'con muon hoc tu vung',
        'con muon hoc tu moi',
        'hoc bo tu vung',
        'luyen tu',
      }.contains(normalized);

  static bool _isReviewVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'luyen lai') ||
      _containsPhrase(normalized, 'on lai') ||
      _containsPhrase(normalized, 'tu chua vung') ||
      _matchesFallbackIntent(normalized, 'INT-014') ||
      _containsPhrase(normalized, 'chua vung');

  static bool _isParentVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'ba me da them') ||
      _containsPhrase(normalized, 'ba me them') ||
      _containsPhrase(normalized, 'noi dung ba me') ||
      _containsPhrase(normalized, 'gia dinh');

  static bool _isStarVocabularyChoice(String normalized) =>
      _containsPhrase(normalized, 'ngoi sao') ||
      _containsPhrase(normalized, 'tu yeu thich') ||
      _matchesFallbackIntent(normalized, 'INT-015') ||
      _containsPhrase(normalized, 'yeu thich');

  static bool _isTranslationChoice(String normalized) =>
      MasterNavigationContract.matches('OPEN_TRANSLATE', normalized) ||
      MasterNavigationContract.matches('TRANSLATE_CONTINUOUS', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-004') ||
      _matchesFallbackIntent(normalized, 'INT-006');

  static bool _isContinueTranslationChoice(String normalized) =>
      MasterNavigationContract.matches('CONTINUE_TRANSLATE', normalized) ||
      _isTranslationChoice(normalized);

  static bool _isNextSentenceChoice(String normalized) =>
      _containsPhrase(normalized, 'tiep theo') ||
      normalized == 'cau tiep' ||
      _containsPhrase(normalized, 'cau tiep theo') ||
      _containsPhrase(normalized, 'hoc cau tiep') ||
      _containsPhrase(normalized, 'qua cau tiep');

  static bool _isPreviousSentenceChoice(String normalized) =>
      normalized == 'cau truoc' ||
      normalized == 'quay lai' ||
      _containsPhrase(normalized, 'nghe cau truoc') ||
      _containsPhrase(normalized, 'quay lai cau truoc') ||
      _containsPhrase(normalized, 'cau vua roi');

  static bool _isLeaveActiveLearningChoice(String normalized) =>
      normalized == 'khong' ||
      _containsPhrase(normalized, 'khong hoc nua') ||
      _containsPhrase(normalized, 'khong muon hoc') ||
      _containsPhrase(normalized, 'muon hoc cai khac') ||
      _containsPhrase(normalized, 'hoc cai khac') ||
      _containsPhrase(normalized, 'dung hoc');

  static bool _isSwitchModuleMenuChoice(String normalized) =>
      MasterNavigationContract.matches('SWITCH_MODULE_MENU', normalized);

  static bool _isReplayLessonChoice(String normalized) =>
      _containsPhrase(normalized, 'hoc lai') ||
      _containsPhrase(normalized, 'lam lai') ||
      _matchesFallbackIntent(normalized, 'INT-011') ||
      _containsPhrase(normalized, 'nghe lai');

  static bool _isContinueLessonChoice(String normalized) =>
      const {
        'tiep',
        'tiep tuc',
        'hoc tiep',
        'con muon tiep tuc',
        'minh muon tiep tuc',
      }.contains(normalized) ||
      MasterNavigationContract.matches('NEXT_LESSON', normalized) ||
      _matchesFallbackIntent(normalized, 'INT-007') ||
      _matchesFallbackIntent(normalized, 'INT-012');

  static bool _matchesFallbackIntent(String normalized, String intentId) {
    final phrases = HomiFallbackCatalog.childPhrasesByIntent[intentId];
    return phrases != null &&
        phrases.any(
          (phrase) =>
              normalized == HomiFallbackCatalog.normalizeVietnamese(phrase),
        );
  }

  static bool _containsPhrase(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

  bool _hasSelectableTopicNumber(String normalized) {
    final topicNumber = _extractSpokenNumber(normalized);
    final catalog = _selectedCatalog;
    return topicNumber != null &&
        (catalog == null ||
            (topicNumber >= 1 && topicNumber <= catalog.topics.length));
  }

  bool _hasSelectableLessonNumber(String normalized) {
    final lessonNumber = _extractSpokenNumber(normalized);
    final topicContent = _selectedTopicContent;
    return lessonNumber != null &&
        (topicContent == null ||
            (lessonNumber >= 1 && lessonNumber <= topicContent.lessons.length));
  }

  MainVoiceAssistantTurn _helpTurn() {
    final promptText = switch (_stage) {
      MainVoiceAssistantStage.chooseFeature => openingPrompt,
      MainVoiceAssistantStage.chooseOtherLearning => otherLearningPrompt,
      MainVoiceAssistantStage.chooseModuleSwitch =>
        MasterNavigationContract.translationSwitch,
      MainVoiceAssistantStage.chooseAfterTranslationStop =>
        afterTranslationStopPrompt,
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        alternativeAfterLearningPrompt,
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?',
      MainVoiceAssistantStage.activeLearning =>
        _activeVoicePrompt ?? activeLearningPrompt,
      MainVoiceAssistantStage.askAge => 'Bạn mấy tuổi? Ví dụ bạn nói: 6 tuổi.',
      MainVoiceAssistantStage.chooseTopic ||
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        _topicSelectionPrompt,
      MainVoiceAssistantStage.chooseCourseRelearnLevel =>
        courseRelearnLevelPrompt,
      MainVoiceAssistantStage.confirmReplayTopic => _replayTopicPrompt,
      MainVoiceAssistantStage.chooseLesson => _lessonSelectionPrompt,
      MainVoiceAssistantStage.confirmReplayLesson =>
        _replayLessonConfirmationPrompt(_pendingReplayLessonNumber ?? 1),
      MainVoiceAssistantStage.idle => openingPrompt,
    };
    return MainVoiceAssistantTurn(
      promptText: promptText,
      continueListening: true,
    );
  }

  MainVoiceAssistantTurn? _fallbackForUnrecognizedInput() {
    final attempts = (_fallbackAttempts[_stage] ?? 0) + 1;
    _fallbackAttempts[_stage] = attempts;
    if (attempts == 1) {
      return MainVoiceAssistantTurn(
        promptText: currentPrompt,
        continueListening: true,
      );
    }
    _fallbackAttempts.remove(_stage);
    if (_stage == MainVoiceAssistantStage.chooseOtherLearning) {
      return _moduleNavigationTurn(
        recognizedText: '',
        destination: VoiceNavigationDestination.conversation,
        promptText: MasterNavigationContract.keepCurrentContent,
      );
    }
    if (_stage == MainVoiceAssistantStage.chooseModuleSwitch ||
        _stage == MainVoiceAssistantStage.activeLearning) {
      return const MainVoiceAssistantTurn(
        promptText: MasterNavigationContract.keepCurrentContent,
        continueListening: false,
        activeLearningCommand: ActiveLearningCommand.resume,
      );
    }
    return MainVoiceAssistantTurn(
      promptText: MasterNavigationContract.pause,
      continueListening: false,
      activeLearningCommand: _stage == MainVoiceAssistantStage.activeLearning
          ? ActiveLearningCommand.stop
          : null,
    );
  }

  String get currentPrompt => _helpTurn().promptText;

  String get silenceRetryPrompt =>
      _stage == MainVoiceAssistantStage.chooseFeature
      ? noSpeechRetryPrompt
      : currentPrompt;

  /// Every navigation state uses the same second-silence outcome.
  ///
  /// No speech is distinct from an invalid spoken answer: the former preserves
  /// the checkpoint in a paused state, while the latter resumes after the
  /// approved "Mình giữ nội dung hiện tại nhé." fallback.
  String get silenceExitPrompt => MasterNavigationContract.pause;

  MainVoiceAssistantTurn handleSilenceExit() {
    return MainVoiceAssistantTurn(
      promptText: silenceExitPrompt,
      continueListening: false,
      activeLearningCommand: _stage == MainVoiceAssistantStage.activeLearning
          ? ActiveLearningCommand.stop
          : null,
    );
  }

  bool _looksLikePromptEcho(String normalized) {
    if (normalized == _normalize(currentPrompt)) return true;
    return switch (_stage) {
      MainVoiceAssistantStage.chooseFeature =>
        (_isTopicChoice(normalized) &&
                _isVocabularyChoice(normalized) &&
                _isTranslationChoice(normalized)) ||
            (_isSpeakingChoice(normalized) && _isTopicChoice(normalized)) ||
            _containsPhrase(normalized, 'hay hoc chu de ne') ||
            normalized == 'hoc chu de ne',
      MainVoiceAssistantStage.chooseOtherLearning =>
        (_isTopicChoice(normalized) &&
                _isVocabularyChoice(normalized) &&
                _isTranslationChoice(normalized)) ||
            (_isTopicChoice(normalized) && _isVocabularyChoice(normalized)) ||
            _containsPhrase(normalized, 'hay hoc tu vung ne') ||
            normalized == 'hoc tu vung ne',
      MainVoiceAssistantStage.chooseModuleSwitch =>
        (_isTopicChoice(normalized) &&
                _isVocabularyChoice(normalized) &&
                _isTranslationChoice(normalized)) ||
            normalized ==
                HomiFallbackCatalog.normalizeVietnamese(
                  MasterNavigationContract.translationSwitch,
                ),
      MainVoiceAssistantStage.chooseAfterTranslationStop =>
        (_isTopicChoice(normalized) && _isVocabularyChoice(normalized)) ||
            normalized ==
                HomiFallbackCatalog.normalizeVietnamese(
                  afterTranslationStopPrompt,
                ),
      MainVoiceAssistantStage.chooseAlternativeAfterLearning =>
        _isTranslationChoice(normalized) && _isVocabularyChoice(normalized),
      MainVoiceAssistantStage.chooseVocabularyCollection =>
        (_isParentVocabularyChoice(normalized) &&
                _isReviewVocabularyChoice(normalized)) ||
            (_isParentVocabularyChoice(normalized) &&
                _isStarVocabularyChoice(normalized)) ||
            (_isReviewVocabularyChoice(normalized) &&
                _isStarVocabularyChoice(normalized)),
      MainVoiceAssistantStage.activeLearning =>
        (_isNextSentenceChoice(normalized) &&
                _isPreviousSentenceChoice(normalized)) ||
            (_isNextSentenceChoice(normalized) &&
                _isLeaveActiveLearningChoice(normalized)) ||
            (_isPreviousSentenceChoice(normalized) &&
                _isLeaveActiveLearningChoice(normalized)),
      MainVoiceAssistantStage.askAge => normalized == 'con may tuoi',
      MainVoiceAssistantStage.chooseTopic =>
        _containsPhrase(normalized, 'chu de so may') ||
            (_selectedCatalog != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedCatalog!.topics.length} chu de',
                )),
      MainVoiceAssistantStage.chooseTopicAfterCompletion =>
        _containsPhrase(normalized, 'con muon hoc chu de so may') ||
            _containsPhrase(normalized, 'chu de so may') ||
            (_selectedCatalog != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedCatalog!.topics.length} chu de',
                )),
      MainVoiceAssistantStage.chooseCourseRelearnLevel =>
        normalized ==
                HomiFallbackCatalog.normalizeVietnamese(
                  courseRelearnLevelPrompt,
                ) ||
            _containsPhrase(normalized, 'hoc lai level so may'),
      MainVoiceAssistantStage.confirmReplayTopic =>
        _containsPhrase(normalized, 'con da hoc roi') ||
            _containsPhrase(normalized, 'co muon hoc lai khong'),
      MainVoiceAssistantStage.chooseLesson =>
        _containsPhrase(normalized, 'bai so may') ||
            _containsPhrase(normalized, 'tiep tuc bai') ||
            (_selectedTopicContent != null &&
                _containsPhrase(
                  normalized,
                  'co ${_selectedTopicContent!.lessons.length} bai hoc',
                )),
      MainVoiceAssistantStage.confirmReplayLesson =>
        _containsPhrase(normalized, 'con da hoc xong roi') ||
            (_containsPhrase(normalized, 'hoc lai bai') &&
                _containsPhrase(normalized, 'hay tiep tuc bai')),
      MainVoiceAssistantStage.idle => false,
    };
  }

  int? _extractSpokenNumber(String normalized) {
    final scope = switch (_stage) {
      MainVoiceAssistantStage.chooseCourseRelearnLevel => 'level',
      MainVoiceAssistantStage.chooseLesson ||
      MainVoiceAssistantStage.confirmReplayLesson => 'bai',
      _ => 'chu de',
    };
    final numberPattern = RegExp(
      '^(?:(?:con|minh|toi) )?(?:(?:chon|hoc lai|hoc|muon|muon hoc|muon hoc lai|muon chon|cho minh hoc|mo lai) )?'
      '(?:$scope )?(?:so )?'
      r'(\d{1,2}|mot|hai|ba|bon|tu|nam|sau|bay|tam|chin|muoi(?: (?:mot|hai|ba|bon|tu|lam))?|dau tien)(?: nhe| a| di)?$',
    );
    final match = numberPattern.firstMatch(normalized);
    return match == null ? null : _extractNumberToken(match.group(1)!);
  }

  static int? _extractNumberToken(String normalized) {
    final digitMatch = RegExp(r'(^| )(\d{1,2})( |$)').firstMatch(normalized);
    final numeric = int.tryParse(digitMatch?.group(2) ?? '');
    if (numeric != null) {
      return numeric;
    }

    const values = <String, int>{
      'muoi lam': 15,
      'muoi bon': 14,
      'muoi tu': 14,
      'muoi ba': 13,
      'muoi hai': 12,
      'muoi mot': 11,
      'muoi': 10,
      'chin': 9,
      'tam': 8,
      'bay': 7,
      'sau': 6,
      'nam': 5,
      'lam': 5,
      'bon': 4,
      'tu': 4,
      'ba': 3,
      'hai': 2,
      'mot': 1,
      'dau tien': 1,
    };
    for (final entry in values.entries) {
      if (_containsPhrase(normalized, entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static String _normalize(String value) =>
      HomiFallbackCatalog.normalizeVietnamese(value);

  static Future<ListeningContentCatalog> _loadDefaultContent() =>
      AssetListeningContentRepository().load();

  static Future<List<VocabularyEntry>> _loadDefaultVocabulary() =>
      const VocabularyStore().read();
}
