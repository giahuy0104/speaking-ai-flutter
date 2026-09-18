import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../l10n/display_language.dart';
import '../../../core/navigation/active_learning_navigation.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../core/platform/background_learning_session.dart';
import '../../../core/platform/platform_access_policy.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../conversation/presentation/conversation_screen.dart';
import '../../listening/application/listening_voice_navigation_target.dart';
import '../../listening/data/active_listening_session_store.dart';
import '../../listening/data/listening_progress_store.dart';
import '../../listening/domain/listening_content.dart';
import '../../listening/presentation/listening_route_names.dart';
import '../../listening/presentation/topic_listening_screen.dart';
import '../../onboarding/application/onboarding_progress_store.dart';
import '../../onboarding/presentation/user_onboarding_tour.dart';
import '../../../core/privacy/parental_gate.dart';
import '../../settings/presentation/history_sheet.dart';
import '../../settings/presentation/settings_sheet.dart';
import '../../settings/application/parent_media_settings.dart';
import '../../vocabulary/data/minhqnd_dictionary_provider.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';
import '../../vocabulary/presentation/vocabulary_home_screen.dart';
import '../../voice_navigation/application/voice_navigation_controller.dart';
import '../../voice_navigation/application/voice_navigation_intent_resolver.dart';
import '../../voice_navigation/application/main_speaking_session_controller.dart';
import '../application/authored_vocabulary_suggestion_provider.dart';
import '../application/background_learning_coordinator.dart';
import 'home_mode_rail.dart';

class HomeLearningShell extends StatefulWidget {
  const HomeLearningShell({
    required this.controller,
    required this.config,
    this.voiceNavigationController,
    this.speakingSessionController,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onActiveLearningExitCommitted,
    this.onMainSpeakingModeStarted,
    this.onScreenMainPressed,
    this.onVocabularyVoiceChoiceRequested,
    this.vocabularySuggestionProvider,
    this.onModalVisibilityChanged,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.onboardingStore,
    this.listeningContentFuture,
    this.listeningProgressStore = const ListeningProgressStore(),
    this.parentAccessGate,
    this.backgroundLearningSession,
    this.parentMediaSettingsStore =
        const SharedPreferencesParentMediaSettingsStore(),
    super.key,
  });

  final ConversationController controller;
  final AppConfig config;
  final VoiceNavigationController? voiceNavigationController;
  final MainSpeakingSessionController? speakingSessionController;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onActiveLearningExitCommitted;
  final Future<void> Function()? onMainSpeakingModeStarted;
  final Future<void> Function()? onScreenMainPressed;
  final Future<void> Function({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  })?
  onVocabularyVoiceChoiceRequested;
  final VocabularySuggestionProvider? vocabularySuggestionProvider;
  final ValueChanged<bool>? onModalVisibilityChanged;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final OnboardingProgressStore? onboardingStore;
  final Future<ListeningContentCatalog>? listeningContentFuture;
  final ListeningProgressStore listeningProgressStore;
  final Future<bool> Function(BuildContext context)? parentAccessGate;
  final BackgroundLearningSessionControl? backgroundLearningSession;
  final ParentMediaSettingsStore parentMediaSettingsStore;

  @override
  State<HomeLearningShell> createState() => _HomeLearningShellState();
}

class _HomeLearningShellState extends State<HomeLearningShell>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  late final AuthoredVocabularySuggestionProvider
  _authoredVocabularySuggestionProvider;
  late final MinhqndDictionaryProvider _vocabularyDictionaryProvider;
  int _page = 0;
  bool _openingTopics = false;
  ActiveListeningSessionCheckpoint? _pausedListeningCheckpoint;
  Completer<void>? _topicRouteClosedCompleter;
  bool _tutorialActive = false;
  int _tutorialStep = 0;
  Timer? _voiceNavigationRestartTimer;
  bool _voiceNavigationPausedForOverlay = false;
  bool _voiceNavigationHelpShown = false;
  int? _activeVoiceTopicIndex;
  late final BackgroundLearningCoordinator _backgroundLearningCoordinator;
  late final BackgroundLearningSessionControl _backgroundLearningSession;
  final VocabularyActivationController _vocabularyActivationController =
      VocabularyActivationController();
  bool _stopMediaWhenBackgrounded = defaultStopMediaWhenBackgrounded();
  Future<void>? _backgroundMediaStopOperation;
  final VocabularyHomeNavigationController _vocabularyNavigationController =
      VocabularyHomeNavigationController();
  int _lifecycleDecisionGeneration = 0;

  final GlobalKey _speakActionKey = GlobalKey(
    debugLabel: 'onboarding-speak-action',
  );
  final GlobalKey _resultPanelKey = GlobalKey(
    debugLabel: 'onboarding-result-panel',
  );
  final GlobalKey _vocabularyTabKey = GlobalKey(
    debugLabel: 'onboarding-vocabulary-tab',
  );
  final GlobalKey _topicTabKey = GlobalKey(debugLabel: 'onboarding-topic-tab');
  final GlobalKey _historyButtonKey = GlobalKey(
    debugLabel: 'onboarding-history-button',
  );
  final GlobalKey _settingsButtonKey = GlobalKey(
    debugLabel: 'onboarding-settings-button',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _authoredVocabularySuggestionProvider =
        AuthoredVocabularySuggestionProvider(
          loadCatalog: () =>
              widget.listeningContentFuture ??
              AssetListeningContentRepository().load(),
        );
    _vocabularyDictionaryProvider = MinhqndDictionaryProvider();
    _backgroundLearningSession =
        widget.backgroundLearningSession ??
        MethodChannelBackgroundLearningSession();
    _backgroundLearningCoordinator = BackgroundLearningCoordinator(
      session: _backgroundLearningSession,
      initialLifecycleState:
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      onDirective: _applyBackgroundLearningDirective,
    );
    unawaited(_loadParentMediaSettings());
    _attachVoiceNavigationHandler();
    widget.controller.addListener(_onConversationControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _backgroundLearningCoordinator.initialize(
          voiceAccessEnabled: widget.voiceAccessEnabled,
        ),
      );
      unawaited(_restoreActiveListeningCheckpoint());
      _scheduleVoiceNavigationListening(
        delay: const Duration(milliseconds: 450),
      );
    });
    if (widget.onboardingStore != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showTutorialOnFirstUse());
      });
    }
  }

  Future<void> _restoreActiveListeningCheckpoint() async {
    final checkpoint = await _backgroundLearningCoordinator
        .takeListeningCheckpoint(voiceAccessEnabled: widget.voiceAccessEnabled);
    if (!mounted || checkpoint == null || _openingTopics) return;
    await _openTopicListening(
      initialVoiceTarget: ListeningVoiceNavigationTarget(
        recognizedText: 'resume active listening session',
        openLesson: true,
        topicNumber: checkpoint.topicNumber,
        lessonNumber: checkpoint.lessonNumber,
        childAge: checkpoint.childAge,
      ),
    );
  }

  @override
  void didUpdateWidget(HomeLearningShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onConversationControllerChanged);
      widget.controller.addListener(_onConversationControllerChanged);
    }
    if (oldWidget.voiceNavigationController !=
        widget.voiceNavigationController) {
      oldWidget.voiceNavigationController?.setIntentHandler(null);
      unawaited(oldWidget.voiceNavigationController?.pause());
      _attachVoiceNavigationHandler();
    }
    if (oldWidget.config.enableVoiceNavigation !=
            widget.config.enableVoiceNavigation ||
        oldWidget.config.autoStartVoiceNavigation !=
            widget.config.autoStartVoiceNavigation) {
      _attachVoiceNavigationHandler();
      if (_continuousVoiceNavigationEnabled) {
        _scheduleVoiceNavigationListening();
      } else {
        _voiceNavigationRestartTimer?.cancel();
        unawaited(widget.voiceNavigationController?.pause());
      }
    }
    if (oldWidget.voiceAccessEnabled != widget.voiceAccessEnabled) {
      if (widget.voiceAccessEnabled) {
        unawaited(_backgroundLearningCoordinator.updateVoiceAccess(true));
        unawaited(_restoreActiveListeningCheckpoint());
      } else {
        unawaited(_backgroundLearningCoordinator.updateVoiceAccess(false));
        unawaited(widget.voiceNavigationController?.pause());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceNavigationRestartTimer?.cancel();
    widget.controller.removeListener(_onConversationControllerChanged);
    widget.voiceNavigationController?.setIntentHandler(null);
    unawaited(widget.voiceNavigationController?.pause());
    _backgroundLearningCoordinator.dispose();
    _vocabularyActivationController.dispose();
    _vocabularyDictionaryProvider.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final generation = ++_lifecycleDecisionGeneration;
    unawaited(_handleAppLifecycleState(state, generation));
  }

  Future<void> _handleAppLifecycleState(
    AppLifecycleState state,
    int generation,
  ) async {
    final directive = _backgroundLearningCoordinator.handleLifecycle(
      state,
      voiceAccessEnabled: widget.voiceAccessEnabled,
      explicitMainSessionActive:
          widget.voiceNavigationController?.isMainButtonSessionActive ?? false,
    );
    if (shouldStopMediaForLifecycle(
      state: state,
      enabled: _stopMediaWhenBackgrounded,
    )) {
      final screenInteractive = await _readAndroidScreenInteractive();
      if (!mounted || generation != _lifecycleDecisionGeneration) {
        return;
      }
      if (screenInteractive == false) {
        // Locking the phone is an intended H20 learning mode. Keep the active
        // lesson/translation and its SCO route; only the always-on foreground
        // wake loop follows the coordinator's normal Android policy.
        _applyBackgroundLearningDirective(directive);
        return;
      }
      _applyBackgroundLearningDirective(
        BackgroundLearningDirective.pauseVoiceNavigation,
      );
      unawaited(_stopMediaForBackgroundOnce());
      return;
    }
    _applyBackgroundLearningDirective(directive);
    if (state == AppLifecycleState.resumed) {
      final activeRegistry = ActiveLearningModuleScope.read(context);
      if (_stopMediaWhenBackgrounded &&
          activeRegistry?.hasActiveModule == true) {
        unawaited(_backgroundLearningCoordinator.setActiveLearning(true));
      }
      unawaited(_restoreActiveListeningCheckpoint());
    }
  }

  Future<bool?> _readAndroidScreenInteractive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final session = _backgroundLearningSession;
    if (session is! DeviceScreenStateBackgroundSessionControl) {
      return null;
    }
    return (session as DeviceScreenStateBackgroundSessionControl)
        .isScreenInteractive();
  }

  Future<void> _loadParentMediaSettings() async {
    final enabled = await widget.parentMediaSettingsStore
        .readStopMediaWhenBackgrounded();
    if (!mounted || enabled == _stopMediaWhenBackgrounded) return;
    setState(() => _stopMediaWhenBackgrounded = enabled);
  }

  void _setStopMediaWhenBackgrounded(bool enabled) {
    if (enabled == _stopMediaWhenBackgrounded) return;
    setState(() => _stopMediaWhenBackgrounded = enabled);
    unawaited(
      widget.parentMediaSettingsStore
          .writeStopMediaWhenBackgrounded(enabled)
          .catchError((Object error) {
            debugPrint('Cannot persist parent media setting: $error');
          }),
    );
  }

  Future<void> _stopMediaForBackground() async {
    _voiceNavigationRestartTimer?.cancel();
    final registry = ActiveLearningModuleScope.read(context);
    await _runBackgroundStopStep(
      'active learning',
      () => registry?.pauseForMainAssistant(),
    );
    await _runBackgroundStopStep(
      'voice navigation',
      () => widget.voiceNavigationController?.pause(stopPrompt: true),
    );
    await _runBackgroundStopStep(
      'MAIN conversation',
      widget.controller.cancelCurrentMainAction,
    );
    await _runBackgroundStopStep(
      'speaking session',
      () async => widget.speakingSessionController?.exit(),
    );
    await _runBackgroundStopStep(
      'background service',
      () => _backgroundLearningCoordinator.setActiveLearning(false),
    );
  }

  Future<void> _runBackgroundStopStep(
    String label,
    Future<void>? Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Cannot stop $label while HOMI is backgrounded: $error');
    }
  }

  Future<void> _stopMediaForBackgroundOnce() async {
    final currentOperation = _backgroundMediaStopOperation;
    if (currentOperation != null) {
      await currentOperation;
      return;
    }
    final operation = _stopMediaForBackground();
    _backgroundMediaStopOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_backgroundMediaStopOperation, operation)) {
        _backgroundMediaStopOperation = null;
      }
    }
  }

  void _applyBackgroundLearningDirective(
    BackgroundLearningDirective directive,
  ) {
    if (!mounted) return;
    if (directive == BackgroundLearningDirective.keepVoiceNavigation) {
      _scheduleVoiceNavigationListening();
      return;
    }
    _voiceNavigationRestartTimer?.cancel();
    unawaited(widget.voiceNavigationController?.pause());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final screenSize = MediaQuery.sizeOf(context);
        final compact = screenSize.height < 900;
        final safeTop = MediaQuery.paddingOf(context).top;
        final railTop = (screenSize.height * (compact ? 0.27 : 0.25))
            .clamp(safeTop + 148, screenSize.height - 238)
            .toDouble();
        final topicRailTop = (railTop + 18)
            .clamp(safeTop + 166, screenSize.height - 220)
            .toDouble();
        return DisplayLanguageScope(
          language: widget.controller.displayLanguage,
          child: PopScope<void>(
            canPop: _page == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _page == 1) {
                unawaited(_handleVocabularyBack());
              }
            },
            child: Stack(
              children: <Widget>[
                PageView(
                  key: const Key('home-learning-page-view'),
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  // Keep the adjacent vocabulary state mounted so a spoken
                  // navigation command can activate its non-visual workflow
                  // while Android has stopped drawing frames for screen lock.
                  allowImplicitScrolling: true,
                  onPageChanged: _handlePageChanged,
                  children: <Widget>[
                    HeroMode(
                      enabled: _page == 0,
                      child: ConversationScreen(
                        controller: widget.controller,
                        speakActionKey: _speakActionKey,
                        resultPanelKey: _resultPanelKey,
                        historyButtonKey: _historyButtonKey,
                        settingsButtonKey: _settingsButtonKey,
                        onOpenHistory: _showHistory,
                        onOpenSettings: _showSettings,
                      ),
                    ),
                    HeroMode(
                      enabled: _page == 1,
                      child: VocabularyHomeScreen(
                        isReady: widget.controller.isInputAvailable,
                        isActive: _page == 1,
                        navigationController: _vocabularyNavigationController,
                        activationController: _vocabularyActivationController,
                        childAge: widget.controller.childAge,
                        audioDependencies: widget.controller,
                        autoStartToday: true,
                        onRequestVoiceChoice:
                            widget.onVocabularyVoiceChoiceRequested,
                        suggestionProvider:
                            widget.vocabularySuggestionProvider ??
                            _authoredVocabularySuggestionProvider.call,
                        curriculumDuplicateChecker:
                            _authoredVocabularySuggestionProvider
                                .containsInCurriculum,
                        dictionaryProvider: _vocabularyDictionaryProvider,
                        translator: (input) async {
                          final translation = await widget.controller
                              .translateVocabulary(input);
                          return VocabularyTranslation(
                            englishText: translation.englishText,
                            vietnameseText: translation.vietnameseText,
                          );
                        },
                        onReturnToConversation: _showConversation,
                        onHistory: _showHistory,
                        onSettings: _showSettings,
                      ),
                    ),
                  ],
                ),
                if (_page == 0) ...<Widget>[
                  PositionedDirectional(
                    top: railTop,
                    start: 0,
                    child: KeyedSubtree(
                      key: _vocabularyTabKey,
                      child: HomeModeRail(
                        key: const Key('vocabulary-edge-tab'),
                        edge: HomeRailEdge.left,
                        label: context.tr('Từ vựng', '词汇'),
                        icon: Icons.menu_book_rounded,
                        color: AppColors.primaryNavy,
                        onPressed: _showVocabulary,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: topicRailTop,
                    end: 0,
                    child: KeyedSubtree(
                      key: _topicTabKey,
                      child: HomeModeRail(
                        key: const Key('topic-listening-edge-tab'),
                        edge: HomeRailEdge.right,
                        label: context.tr('Chủ đề', '主题'),
                        icon: Icons.grid_view_rounded,
                        color: AppColors.primaryNavy,
                        onPressed: _openTopicListening,
                      ),
                    ),
                  ),
                ],
                if (_tutorialActive)
                  Positioned.fill(
                    child: UserOnboardingTour(
                      steps: _tutorialSteps,
                      currentIndex: _tutorialStep,
                      onPrevious: _tutorialStep == 0
                          ? null
                          : _previousTutorialStep,
                      onNext: _nextTutorialStep,
                      onSkip: _skipTutorial,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Duration get _motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  void _attachVoiceNavigationHandler() {
    widget.voiceNavigationController?.setIntentHandler(
      widget.config.enableVoiceNavigation ? _handleVoiceNavigationIntent : null,
    );
  }

  bool get _continuousVoiceNavigationEnabled =>
      widget.config.enableVoiceNavigation &&
      widget.config.autoStartVoiceNavigation &&
      widget.voiceAccessEnabled &&
      widget.voiceNavigationController != null &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  bool get _canStartVoiceNavigationListening =>
      mounted &&
      _continuousVoiceNavigationEnabled &&
      (_backgroundLearningCoordinator.isForeground ||
          _backgroundLearningCoordinator.canKeepMainListeningInBackground(
            voiceAccessEnabled: widget.voiceAccessEnabled,
            explicitMainSessionActive:
                widget.voiceNavigationController?.isMainButtonSessionActive ??
                false,
          )) &&
      !_voiceNavigationPausedForOverlay &&
      !_tutorialActive &&
      !(widget.speakingSessionController?.isActive ?? false) &&
      !widget.controller.isBusy &&
      !widget.controller.isPlaybackPlaying &&
      widget.controller.isInputAvailable;

  void _onConversationControllerChanged() {
    // This listener owns Android's optional, always-on wake-word session only.
    // iOS uses the same VoiceNavigationController for an explicit MAIN turn.
    // Pausing when continuous navigation is disabled therefore cancelled an
    // iOS MAIN turn whenever BLE/HFP diagnostics notified the conversation
    // controller -- often only a few milliseconds after beginMainTurn().
    if (!_continuousVoiceNavigationEnabled) {
      _voiceNavigationRestartTimer?.cancel();
      return;
    }
    if (widget.speakingSessionController?.isActive ?? false) {
      _voiceNavigationRestartTimer?.cancel();
      return;
    }
    if (widget.controller.isBusy || widget.controller.isPlaybackPlaying) {
      _voiceNavigationRestartTimer?.cancel();
      unawaited(widget.voiceNavigationController?.pause());
      return;
    }
    _scheduleVoiceNavigationListening();
  }

  void _scheduleVoiceNavigationListening({
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _voiceNavigationRestartTimer?.cancel();
    if (!_canStartVoiceNavigationListening) {
      return;
    }
    _voiceNavigationRestartTimer = Timer(delay, () {
      _voiceNavigationRestartTimer = null;
      _startVoiceNavigationListening();
    });
  }

  void _startVoiceNavigationListening() {
    if (!_canStartVoiceNavigationListening) {
      return;
    }
    if (!_voiceNavigationHelpShown) {
      _voiceNavigationHelpShown = true;
      _showVoiceNavigationMessage(
        widget.controller.displayLanguage == DisplayLanguage.simplifiedChinese
            ? '请先说：“Hey HOMI”，听到回应后再说想打开的功能。'
            : 'Hãy nói “Hey HOMI”. Khi HOMI trả lời, bạn hãy nói chức năng muốn mở.',
      );
    }
    widget.voiceNavigationController?.startContinuous();
  }

  Future<void> _pauseVoiceNavigation(String reason) async {
    _voiceNavigationPausedForOverlay = true;
    _voiceNavigationRestartTimer?.cancel();
    await widget.voiceNavigationController?.pause();
  }

  void _resumeVoiceNavigation() {
    _voiceNavigationPausedForOverlay = false;
    _scheduleVoiceNavigationListening();
  }

  Future<void> _handleVoiceNavigationIntent(
    VoiceNavigationIntent intent,
  ) async {
    if (!mounted || _tutorialActive) {
      return;
    }
    await _executeVoiceNavigation(intent);
  }

  Future<void> _executeVoiceNavigation(VoiceNavigationIntent intent) async {
    final useChinese =
        widget.controller.displayLanguage == DisplayLanguage.simplifiedChinese;
    final activeKind = ActiveLearningModuleScope.read(context)?.activeKind;
    final leavesActiveModule = switch ((activeKind, intent.destination)) {
      (
        ActiveLearningModuleKind.listeningLesson,
        VoiceNavigationDestination.topics,
      ) =>
        false,
      (
        ActiveLearningModuleKind.vocabulary,
        VoiceNavigationDestination.vocabulary,
      ) =>
        false,
      (null, _) => false,
      _ => true,
    };
    if (leavesActiveModule &&
        activeKind == ActiveLearningModuleKind.listeningLesson) {
      // A listening route is popped during a committed module transfer. Keep
      // its durable lesson pointer in memory before the route cleanup clears
      // the recovery store; sentence/activity progress remains in the regular
      // listening progress store. Returning to Chủ đề can therefore rebuild
      // the exact unfinished unit instead of opening the catalog root.
      _pausedListeningCheckpoint = await const ActiveListeningSessionStore()
          .read();
    }
    if (leavesActiveModule) {
      // MAIN already paused the source owner, which persisted its exact item
      // checkpoint. A committed module transfer must only clear automatic
      // resume ownership; it must not complete, skip, or reset that source.
      widget.onActiveLearningExitCommitted?.call();
    }
    final destinationLabel = intent.openLesson
        ? useChinese
              ? '第 ${intent.lessonNumber ?? 1} 课'
              : 'Bài ${intent.lessonNumber ?? 1}'
        : switch (intent.destination) {
            VoiceNavigationDestination.conversation =>
              useChinese ? '沟通' : 'Giao tiếp',
            VoiceNavigationDestination.vocabulary =>
              useChinese ? '词汇' : 'Từ vựng',
            VoiceNavigationDestination.topics => useChinese ? '主题' : 'Chủ đề',
            VoiceNavigationDestination.history =>
              useChinese ? '历史记录' : 'Lịch sử',
            VoiceNavigationDestination.settings =>
              useChinese ? '设置' : 'Cài đặt',
          };
    if (intent.destination != VoiceNavigationDestination.topics) {
      if (_openingTopics && !leavesActiveModule) {
        // This is a committed feature change, not a temporary MAIN pause.
        // Clear the old module's resume ownership before its route starts
        // closing so no listener can wake that lesson during the transition.
        widget.onActiveLearningExitCommitted?.call();
      }
      await _closeTopicListeningIfNeeded();
      if (!mounted) {
        return;
      }
    }
    _showVoiceNavigationMessage(
      useChinese
          ? '已识别语音指令，正在打开$destinationLabel。'
          : 'Đã nhận lệnh giọng nói. Đang mở $destinationLabel.',
    );

    switch (intent.destination) {
      case VoiceNavigationDestination.conversation:
        _showConversation();
        if (intent.enterMainSpeakingMode) {
          await widget.onMainSpeakingModeStarted?.call();
        }
      case VoiceNavigationDestination.vocabulary:
        _showVocabulary();
      case VoiceNavigationDestination.topics:
        final pausedCheckpoint =
            intent.topicNumber == null &&
                intent.levelNumber == null &&
                !intent.openLesson
            ? _pausedListeningCheckpoint
            : null;
        if (pausedCheckpoint != null) {
          _pausedListeningCheckpoint = null;
        }
        final opensCurrentLevelSelection =
            intent.topicNumber == null &&
            intent.levelNumber == null &&
            !intent.openLesson &&
            pausedCheckpoint == null;
        final fallbackTopicIndex = _activeVoiceTopicIndex;
        final target = ListeningVoiceNavigationTarget(
          recognizedText: intent.recognizedText,
          openLesson: intent.openLesson || pausedCheckpoint != null,
          topicNumber: intent.topicNumber ?? pausedCheckpoint?.topicNumber,
          lessonNumber: intent.lessonNumber ?? pausedCheckpoint?.lessonNumber,
          levelNumber: intent.levelNumber,
          childAge: intent.childAge ?? pausedCheckpoint?.childAge,
          relearnTopic: intent.relearnTopic,
          relearnLesson: intent.relearnLesson,
          relearnLevel: intent.relearnLevel,
          fallbackTopicIndex: fallbackTopicIndex,
        );
        if (_openingTopics) {
          await _closeTopicListeningIfNeeded();
        }
        if (mounted) {
          unawaited(
            _openTopicListening(
              initialVoiceTarget: opensCurrentLevelSelection ? null : target,
            ),
          );
        }
      case VoiceNavigationDestination.history:
        _showHistory();
      case VoiceNavigationDestination.settings:
        _showSettings();
    }
  }

  Future<void> _closeTopicListeningIfNeeded() async {
    if (!_openingTopics || !mounted) {
      return;
    }
    final closed = _topicRouteClosedCompleter?.future;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (closed != null) {
      await closed;
    }
  }

  void _showVoiceNavigationMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<UserOnboardingStep> get _tutorialSteps => <UserOnboardingStep>[
    UserOnboardingStep(
      kind: UserOnboardingStepKind.welcome,
      title: context.tr('Chào mừng đến với HOMI', '欢迎使用 HOMI'),
      description: context.tr(
        'Mình sẽ chỉ cho bạn những khu vực quan trọng để bắt đầu học thật dễ dàng.',
        '接下来带你快速认识几个重要功能，轻松开始学习。',
      ),
      icon: Icons.waving_hand_rounded,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Bắt đầu nói', '开始说话'),
      description: context.tr(
        'Chạm nút micro, nói một câu tiếng Việt và HOMI sẽ giúp chuyển sang tiếng Anh.',
        '点击麦克风，说一句越南语，HOMI 会帮你转换成英语。',
      ),
      icon: Icons.mic_rounded,
      targetKey: _speakActionKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Xem và nghe kết quả', '查看并收听结果'),
      description: context.tr(
        'Câu tiếng Việt, bản dịch tiếng Anh và nút nghe lại đều xuất hiện trong khu vực này.',
        '越南语原句、英语翻译和重播按钮都会显示在这里。',
      ),
      icon: Icons.translate_rounded,
      targetKey: _resultPanelKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Học từ vựng', '学习词汇'),
      description: context.tr(
        'Mở kho từ vựng để lưu từ mới, nghe phát âm và luyện tập lại bất cứ lúc nào.',
        '打开词汇库，保存新词、收听发音，并随时复习。',
      ),
      icon: Icons.chat_bubble_rounded,
      targetKey: _vocabularyTabKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Luyện nghe theo chủ đề', '主题听力练习'),
      description: context.tr(
        'Chọn chủ đề phù hợp với độ tuổi để học câu mẫu, luyện nói và nghe bài hát.',
        '选择适合年龄的主题，学习例句、练习口语并听儿歌。',
      ),
      icon: Icons.headphones_rounded,
      targetKey: _topicTabKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Xem lại lịch sử', '查看历史记录'),
      description: context.tr(
        'Những câu đã luyện gần đây được lưu ở đây để bạn có thể xem và nghe lại.',
        '最近练习过的句子会保存在这里，方便查看和重听。',
      ),
      icon: Icons.history_rounded,
      targetKey: _historyButtonKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Micro và thiết bị INNOTRIK', '麦克风和 INNOTRIK 设备'),
      description: context.tr(
        'Bạn vẫn dùng được micro hiện tại. Mở Cài đặt khi cần đổi giao diện, ngôn ngữ hoặc kết nối micro INNOTRIK qua HFP.',
        '你可以继续使用当前麦克风；需要切换主题、语言或通过 HFP 连接 INNOTRIK 麦克风时，请打开设置。',
      ),
      icon: Icons.settings_outlined,
      targetKey: _settingsButtonKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.complete,
      title: context.tr('Bạn đã sẵn sàng!', '你已经准备好了！'),
      description: context.tr(
        'Hãy thử nói một câu tiếng Việt để bắt đầu nhé.',
        '现在说一句越南语开始体验吧。',
      ),
      icon: Icons.celebration_rounded,
    ),
  ];

  Future<void> _showTutorialOnFirstUse() async {
    final store = widget.onboardingStore;
    if (store == null) {
      return;
    }
    try {
      final shouldShow = await store.shouldShow();
      if (!shouldShow || !mounted) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) {
        _startTutorial();
      }
    } catch (error, stackTrace) {
      debugPrint('Could not read onboarding progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _startTutorial() {
    if (!mounted || _tutorialActive) {
      return;
    }
    unawaited(_pauseVoiceNavigation('onboarding_tutorial'));
    if (_page != 0 && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    setState(() {
      _page = 0;
      _tutorialStep = 0;
      _tutorialActive = true;
    });
  }

  void _previousTutorialStep() {
    if (!_tutorialActive || _tutorialStep <= 0) {
      return;
    }
    setState(() => _tutorialStep -= 1);
    _revealCurrentTutorialTarget();
  }

  void _nextTutorialStep() {
    if (!_tutorialActive) {
      return;
    }
    if (_tutorialStep < _tutorialSteps.length - 1) {
      setState(() => _tutorialStep += 1);
      _revealCurrentTutorialTarget();
      return;
    }
    unawaited(_finishTutorial(startSpeaking: true));
  }

  void _skipTutorial() => unawaited(_finishTutorial());

  void _revealCurrentTutorialTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tutorialActive) {
        return;
      }
      final targetContext =
          _tutorialSteps[_tutorialStep].targetKey?.currentContext;
      if (targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          ),
        );
      }
    });
  }

  Future<void> _finishTutorial({bool startSpeaking = false}) async {
    if (mounted) {
      setState(() {
        _tutorialActive = false;
        _tutorialStep = 0;
      });
    }
    if (startSpeaking) {
      unawaited(widget.controller.onPrimaryAction());
    }
    _resumeVoiceNavigation();
    final store = widget.onboardingStore;
    if (store == null) {
      return;
    }
    try {
      await store.markSeen();
    } catch (error, stackTrace) {
      debugPrint('Could not save onboarding progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _showVocabulary() {
    _vocabularyActivationController.activate();
    if (_page != 1 && mounted) {
      setState(() => _page = 1);
    }
    if (!_pageController.hasClients) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _pageController.jumpToPage(1);
      return;
    }
    unawaited(
      _pageController.animateToPage(
        1,
        duration: _motionDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _showConversation() {
    _vocabularyActivationController.deactivate();
    if (_page == 1) {
      unawaited(_vocabularyNavigationController.leaveForOtherContent());
      ActiveLearningModuleScope.notifyNavigationExit(context);
      unawaited(widget.voiceNavigationController?.pause());
    }
    if (_page != 0 && mounted) {
      setState(() => _page = 0);
    }
    if (!_pageController.hasClients) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _pageController.jumpToPage(0);
      return;
    }
    unawaited(
      _pageController.animateToPage(
        0,
        duration: _motionDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _handleVocabularyBack() async {
    if (await _vocabularyNavigationController.handleBack()) return;
    if (mounted) _showConversation();
  }

  void _handlePageChanged(int page) {
    if (page == 1) {
      _vocabularyActivationController.activate();
    } else {
      _vocabularyActivationController.deactivate();
    }
    if (mounted && _page != page) {
      setState(() => _page = page);
    }
  }

  Future<void> _openTopicListening({
    ListeningVoiceNavigationTarget? initialVoiceTarget,
  }) async {
    if (_openingTopics) {
      return;
    }
    _openingTopics = true;
    final routeClosedCompleter = Completer<void>();
    _topicRouteClosedCompleter = routeClosedCompleter;
    try {
      if (!mounted) {
        return;
      }
      unawaited(
        _backgroundLearningCoordinator.ensureStarted(
          voiceAccessEnabled: widget.voiceAccessEnabled,
        ),
      );
      unawaited(_backgroundLearningCoordinator.setActiveLearning(true));
      final routeDuration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      await pushForActiveLearning<void>(
        context,
        (_) => TopicListeningScreen(
          language: widget.controller.displayLanguage,
          childAge: widget.controller.childAge,
          controller: widget.controller,
          onMainPressed: widget.onScreenMainPressed,
          onVocabularyRequested: _showVocabulary,
          onVoiceNavigationPause: () =>
              _pauseVoiceNavigation('listening_media_opened'),
          onVoiceNavigationResume: _resumeVoiceNavigation,
          initialVoiceTarget: initialVoiceTarget,
          onTopicSelected: (index) => _activeVoiceTopicIndex = index,
          onChildAgeChanged: widget.onChildAgeChanged,
          onRequestParentAccess: _requestTopicAgeAccess,
          onLessonSelectionRequested:
              ({
                required childAge,
                required topicNumber,
                required topicContent,
                required completedLessonNumbers,
              }) async {
                await widget.voiceNavigationController
                    ?.activateLessonSelectionForTopic(
                      childAge: childAge,
                      topicNumber: topicNumber,
                      topicContent: topicContent,
                      completedLessonNumbers: completedLessonNumbers,
                    );
              },
          onLevelTopicSelectionRequested:
              ({
                required childAge,
                required levelNumber,
                required topicNumbers,
                required completedTopicNumbers,
                required announceLevel,
              }) async {
                await widget.voiceNavigationController
                    ?.activateLevelTopicSelection(
                      childAge: childAge,
                      levelNumber: levelNumber,
                      topicNumbers: topicNumbers,
                      completedTopicNumbers: completedTopicNumbers,
                      announceLevel: announceLevel,
                    );
              },
          onCourseRelearnLevelSelectionRequested:
              ({required childAge, required levelNumbers}) async {
                await widget.voiceNavigationController
                    ?.activateCourseRelearnLevelSelection(
                      childAge: childAge,
                      levelNumbers: levelNumbers,
                    );
              },
          contentFuture: widget.listeningContentFuture,
          progressStore: widget.listeningProgressStore,
        ),
        settings: const RouteSettings(name: ListeningRouteNames.topicCatalog),
        foregroundTransitionDuration: routeDuration,
        foregroundReverseTransitionDuration: routeDuration,
        foregroundTransitionsBuilder:
            (_, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: FadeTransition(opacity: curved, child: child),
              );
            },
      );
    } finally {
      await _backgroundLearningCoordinator.clearListeningCheckpoint();
      _openingTopics = false;
      _activeVoiceTopicIndex = null;
      if (identical(_topicRouteClosedCompleter, routeClosedCompleter)) {
        _topicRouteClosedCompleter = null;
      }
      if (!routeClosedCompleter.isCompleted) {
        routeClosedCompleter.complete();
      }
      unawaited(_backgroundLearningCoordinator.setActiveLearning(false));
      if (mounted) {
        _resumeVoiceNavigation();
      }
    }
  }

  void _showSettings() {
    unawaited(_openParentSettings());
  }

  Future<void> _openParentSettings() async {
    if (!await _requestSettingsAccess()) {
      return;
    }
    await _pauseVoiceNavigation('settings_opened');
    await _openSettingsSheet();
  }

  Future<bool> _requestSettingsAccess() {
    final gate = widget.parentAccessGate;
    if (gate != null) {
      return gate(context);
    }
    if (PlatformAccessPolicy.bypassesSettingsAuthentication(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return Future<bool>.value(true);
    }
    return showParentalGate(context);
  }

  Future<void> _openSettingsSheet() async {
    await widget.controller.markParentDiagnosticsOpened();
    if (!mounted) return;
    widget.onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SettingsSheet(
          controller: widget.controller,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onChildAgeChanged: widget.onChildAgeChanged,
          onStartTutorial: _startTutorial,
          config: widget.config,
          privacyConsentGranted: widget.privacyConsentGranted,
          voiceAccessEnabled: widget.voiceAccessEnabled,
          onRequestVoiceAccess: widget.onRequestVoiceAccess,
          onManagePrivacyConsent: widget.onManagePrivacyConsent,
          onRevokePrivacyConsent: widget.onRevokePrivacyConsent,
          stopMediaWhenBackgrounded: _stopMediaWhenBackgrounded,
          onStopMediaWhenBackgroundedChanged: _setStopMediaWhenBackgrounded,
        ),
      );
    } finally {
      widget.onModalVisibilityChanged?.call(false);
    }
    if (mounted && !_tutorialActive) {
      _resumeVoiceNavigation();
    }
  }

  void _showHistory() {
    unawaited(_openParentHistory());
  }

  Future<void> _openParentHistory() async {
    if (!await _requestParentAccess()) {
      return;
    }
    await _pauseVoiceNavigation('history_opened');
    await _openHistorySheet();
  }

  Future<bool> _requestParentAccess() {
    final gate = widget.parentAccessGate;
    return gate == null ? showParentalGate(context) : gate(context);
  }

  Future<bool> _requestTopicAgeAccess() {
    final gate = widget.parentAccessGate;
    if (gate != null) {
      return gate(context);
    }
    if (PlatformAccessPolicy.bypassesTopicAgeAuthentication(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return Future<bool>.value(true);
    }
    return showParentalGate(context);
  }

  Future<void> _openHistorySheet() async {
    widget.onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HistorySheet(controller: widget.controller),
      );
    } finally {
      widget.onModalVisibilityChanged?.call(false);
    }
    if (mounted) {
      _resumeVoiceNavigation();
    }
  }
}
