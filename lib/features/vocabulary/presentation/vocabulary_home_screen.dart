import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/audio_gain.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../core/navigation/active_learning_navigation.dart';
import '../../../l10n/display_language.dart';
import '../../listening/application/lesson_media_service.dart';
import '../../listening/domain/lesson_guide_flow.dart';
import '../../voice_navigation/application/voice_navigation_intent_resolver.dart';
import '../../voice_navigation/domain/master_navigation_contract.dart';
import '../application/vocabulary_audio_service.dart';
import '../application/local_vocabulary_suggestion_provider.dart';
import '../application/vocabulary_fixed_prompt_audio_service.dart';
import '../data/vocabulary_session_store.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_dictionary.dart';
import '../domain/vocabulary_audio_keys.dart';
import '../domain/vocabulary_entry.dart';
import '../domain/vocabulary_flow_v3.dart';
import '../domain/vocabulary_journey_index.dart';
import 'vocabulary_practice_screen.dart';

const _familyAsset = 'assets/images/topics/my-family.jpg';
const _starAsset = 'assets/images/vocabulary/golden-star.png';
const _reviewAsset = 'assets/images/vocabulary/review-book.png';
const _avatarAsset = 'assets/images/mascot/penguin-avatar.png';

/// Activates the vocabulary state machine immediately, even when Android has
/// stopped producing UI frames because the display is locked. The visual page
/// still follows [VocabularyHomeScreen.isActive] when frames resume.
class VocabularyActivationController extends ChangeNotifier {
  bool _active = false;

  bool get isActive => _active;

  void activate() => _setActive(true);

  void deactivate() => _setActive(false);

  void _setActive(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }
}

class VocabularyHomeNavigationController {
  Object? _owner;
  Future<bool> Function()? _handleBack;
  Future<void> Function()? _leaveForOtherContent;
  Future<void> Function(VoiceVocabularyTarget target)? _openVoiceTarget;

  Future<bool> handleBack() async => await _handleBack?.call() ?? false;

  Future<void> leaveForOtherContent() async {
    await _leaveForOtherContent?.call();
  }

  Future<void> openVoiceTarget(VoiceVocabularyTarget target) async {
    await _openVoiceTarget?.call(target);
  }

  void _attach(
    Object owner, {
    required Future<bool> Function() handleBack,
    required Future<void> Function() leaveForOtherContent,
    required Future<void> Function(VoiceVocabularyTarget target)
    openVoiceTarget,
  }) {
    _owner = owner;
    _handleBack = handleBack;
    _leaveForOtherContent = leaveForOtherContent;
    _openVoiceTarget = openVoiceTarget;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handleBack = null;
    _leaveForOtherContent = null;
    _openVoiceTarget = null;
  }
}

class VocabularyHomeScreen extends StatefulWidget {
  const VocabularyHomeScreen({
    required this.isReady,
    required this.onReturnToConversation,
    required this.onHistory,
    required this.onSettings,
    this.isActive = true,
    this.store = const VocabularyStore(),
    this.sessionStore = const VocabularySessionStore(),
    this.voicePromptService,
    this.mediaService,
    this.audioDependencies,
    this.translator,
    this.suggestionProvider,
    this.curriculumDuplicateChecker,
    this.dictionaryProvider,
    this.vocabularyAudioService,
    this.fixedPromptAudioService,
    this.activationController,
    this.childAge = 5,
    this.autoStartToday = false,
    this.onRequestVoiceChoice,
    this.navigationController,
    super.key,
  });

  final bool isReady;
  final VoidCallback onReturnToConversation;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final bool isActive;
  final VocabularyStore store;
  final VocabularySessionStore sessionStore;
  final VoicePromptService? voicePromptService;
  final LessonMediaService? mediaService;
  final LearningAudioDependencies? audioDependencies;
  final VocabularyTranslator? translator;
  final VocabularySuggestionProvider? suggestionProvider;
  final VocabularyCurriculumDuplicateChecker? curriculumDuplicateChecker;
  final VocabularyDictionaryProvider? dictionaryProvider;
  final VocabularyContentAudioService? vocabularyAudioService;
  final VocabularyFixedPromptAudioService? fixedPromptAudioService;
  final VocabularyActivationController? activationController;
  final int childAge;
  final bool autoStartToday;
  final VocabularyHomeNavigationController? navigationController;
  final Future<void> Function({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  })?
  onRequestVoiceChoice;

  @override
  State<VocabularyHomeScreen> createState() => _VocabularyHomeScreenState();
}

class _VocabularyHomeScreenState extends State<VocabularyHomeScreen>
    implements ActiveLearningModuleController, ActiveLearningVoiceContext {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _journeyScrollController = ScrollController();
  final Map<String, GlobalKey> _entryKeys = <String, GlobalKey>{};
  StreamSubscription<void>? _storeSubscription;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  late final LessonMediaService _mediaService;
  late final bool _ownsMediaService;
  late final VocabularyFixedPromptAudioService _fixedPromptAudioService;
  VocabularyContentAudioService? _vocabularyAudioService;
  late final bool _ownsVocabularyAudioService;
  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  VocabularyJourneyIndex _journeyIndex = VocabularyJourneyIndex.empty();
  _VocabularyJourney? _selectedJourney;
  bool _loading = true;
  bool _translating = false;
  bool _pausedForMainAssistant = false;
  bool _openingPractice = false;
  bool _startingToday = false;
  bool _todayOffered = false;
  bool _playingCollection = false;
  int _playbackGeneration = 0;
  int _audioCommandGeneration = 0;
  Future<void>? _playbackNavigationCleanup;
  Timer? _playbackNavigationCleanupTimer;
  Completer<void>? _playbackNavigationCleanupCompleter;
  bool _playbackInterrupted = false;
  List<VocabularyEntry> _playbackQueue = const <VocabularyEntry>[];
  int _playbackIndex = 0;
  int _playbackBlockStartIndex = 0;
  int _playbackBlockEndExclusive = 0;
  String? _playbackBranch;
  int _nextPlaybackIndex = 0;
  bool _waitingForPlaybackContinuation = false;
  bool _awaitingPlaybackEndChoice = false;
  bool _userIsScrollingJourney = false;
  String? _activePlaybackEntryId;
  int _autoScrollGeneration = 0;
  String _lastVoiceChoicePrompt = VocabularyFlowV3.menu;
  ActiveLearningModuleRegistry? _activeLearningRegistry;
  Object? _activeLearningRegistration;
  late bool _wasEffectivelyActive;

  bool get _isEffectivelyActive =>
      widget.isActive || (widget.activationController?.isActive ?? false);

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ??
        createVoicePromptService(
          coordinator: widget.audioDependencies?.audioTurnCoordinator,
          owner: AudioTurnOwner.vocabulary,
        );
    _ownsMediaService = widget.mediaService == null;
    _mediaService =
        widget.mediaService ??
        LessonMediaService(
          hfpAudioControl: widget.audioDependencies
              ?.createLearningAudioRouteControl(),
          audioTurnCoordinator: widget.audioDependencies?.audioTurnCoordinator,
          audioTurnOwner: AudioTurnOwner.vocabulary,
        );
    _fixedPromptAudioService =
        widget.fixedPromptAudioService ??
        AssetFirstVocabularyFixedPromptAudioService(
          mediaService: _mediaService,
          registryService: _voicePromptService,
        );
    _ownsVocabularyAudioService =
        widget.vocabularyAudioService == null &&
        widget.dictionaryProvider != null;
    _vocabularyAudioService = widget.vocabularyAudioService;
    if (_vocabularyAudioService == null && widget.dictionaryProvider != null) {
      _vocabularyAudioService = VocabularyAudioService(
        dictionaryProvider: widget.dictionaryProvider!,
        playToCompletion: _mediaService.playToCompletion,
        nativeSpeakAndWait: (text, locale) => _speakOnSelectedOutput(
          text,
          locale: locale,
          allowFixedPrompt: false,
        ),
        stopPlayback: () async {
          await Future.wait<void>(<Future<void>>[
            _mediaService.stopPlayback().catchError((Object _) {}),
            _voicePromptService.stop().catchError((Object _) {}),
          ]);
        },
      );
    }
    _searchController.addListener(_refreshSearch);
    _storeSubscription = widget.store.changes.listen((_) => unawaited(_load()));
    _wasEffectivelyActive = _isEffectivelyActive;
    widget.activationController?.addListener(_handleActivationChanged);
    _attachNavigationController();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (!identical(registry, _activeLearningRegistry)) {
      _unregisterActiveLearningModule();
      _activeLearningRegistry = registry;
    }
    _syncActiveLearningRegistration();
  }

  @override
  void didUpdateWidget(VocabularyHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activationController != widget.activationController) {
      oldWidget.activationController?.removeListener(_handleActivationChanged);
      widget.activationController?.addListener(_handleActivationChanged);
    }
    if (!identical(
      oldWidget.navigationController,
      widget.navigationController,
    )) {
      oldWidget.navigationController?._detach(this);
      _attachNavigationController();
    }
    _handleActivationChanged();
  }

  void _handleActivationChanged() {
    final active = _isEffectivelyActive;
    if (_wasEffectivelyActive == active) return;
    _wasEffectivelyActive = active;
    if (!active) {
      _cancelHiddenPlayback();
    } else {
      _pausedForMainAssistant = false;
    }
    _syncActiveLearningRegistration();
    if (active && widget.autoStartToday) {
      unawaited(_maybeStartToday());
    }
  }

  void _cancelHiddenPlayback() {
    _cancelPendingFixedPrompt();
    _playbackGeneration++;
    _pausedForMainAssistant = true;
    _playbackInterrupted = false;
    _playingCollection = false;
    _waitingForPlaybackContinuation = false;
    _awaitingPlaybackEndChoice = false;
    _playbackQueue = const <VocabularyEntry>[];
    _activePlaybackEntryId = null;
    _autoScrollGeneration += 1;
    _selectedJourney = null;
    for (final operation in <Future<void> Function()>[
      _voicePromptService.stop,
      _mediaService.stopPlayback,
      if (_vocabularyAudioService != null) _vocabularyAudioService!.stop,
    ]) {
      unawaited(Future<void>.sync(operation).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    _finishPlaybackNavigationCleanup();
    widget.activationController?.removeListener(_handleActivationChanged);
    widget.navigationController?._detach(this);
    _unregisterActiveLearningModule();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    _searchFocusNode.dispose();
    _journeyScrollController.dispose();
    _storeSubscription?.cancel();
    if (_ownsVocabularyAudioService) {
      _vocabularyAudioService?.dispose();
    }
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    }
    if (_ownsMediaService) {
      unawaited(_mediaService.dispose());
    }
    super.dispose();
  }

  void _attachNavigationController() {
    widget.navigationController?._attach(
      this,
      handleBack: _handleNavigationBack,
      leaveForOtherContent: () => _leavePlaybackForOtherContent(
        announceMenu: false,
        notifyNavigationExit: false,
      ),
      openVoiceTarget: _openVoiceTarget,
    );
  }

  Future<void> _openVoiceTarget(VoiceVocabularyTarget target) async {
    _pausedForMainAssistant = false;
    switch (target) {
      case VoiceVocabularyTarget.parent:
        _openJourney(_VocabularyJourney.family);
        await _playJourney(_VocabularyJourney.family);
        return;
      case VoiceVocabularyTarget.star:
        _openJourney(_VocabularyJourney.stars);
        await _playJourney(_VocabularyJourney.stars);
        return;
      case VoiceVocabularyTarget.review:
        await _startReview();
        return;
    }
  }

  Future<bool> _handleNavigationBack() async {
    if (_selectedJourney == null) return false;
    unawaited(_leavePlaybackForOtherContent());
    return true;
  }

  void _syncActiveLearningRegistration() {
    final registry = _activeLearningRegistry;
    if (!_isEffectivelyActive || registry == null) {
      _unregisterActiveLearningModule();
      return;
    }
    _activeLearningRegistration ??= registry.register(this);
  }

  void _unregisterActiveLearningModule() {
    final registration = _activeLearningRegistration;
    if (registration == null) {
      return;
    }
    _activeLearningRegistry?.unregister(registration);
    _activeLearningRegistration = null;
  }

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.vocabulary;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  @override
  ActiveLearningVoiceNode get mainVoiceNode {
    if (_waitingForPlaybackContinuation) {
      return ActiveLearningVoiceNode.blockEnd;
    }
    if (_awaitingPlaybackEndChoice) return ActiveLearningVoiceNode.listEnd;
    if (_playingCollection || _playbackInterrupted) {
      return _selectedJourney == _VocabularyJourney.stars
          ? ActiveLearningVoiceNode.star
          : ActiveLearningVoiceNode.parent;
    }
    return switch (_lastVoiceChoicePrompt) {
      VocabularyFlowV3.parentEmpty || VocabularyFlowV3.parentOtherMenu =>
        ActiveLearningVoiceNode.parentAlternatives,
      VocabularyFlowV3.starEmpty || VocabularyFlowV3.starOtherMenu =>
        ActiveLearningVoiceNode.starAlternatives,
      VocabularyFlowV3.reviewEmpty ||
      VocabularyFlowV3.reviewOtherMenu ||
      VocabularyFlowV3.reviewCycleFinished =>
        ActiveLearningVoiceNode.reviewAlternatives,
      _ => ActiveLearningVoiceNode.vocabularyMenu,
    };
  }

  @override
  String get mainVoicePrompt => switch (mainVoiceNode) {
    ActiveLearningVoiceNode.blockEnd => VocabularyFlowV3.parentGroupCompletion,
    ActiveLearningVoiceNode.listEnd =>
      _selectedJourney == _VocabularyJourney.stars
          ? VocabularyFlowV3.starFinished
          : VocabularyFlowV3.parentFinished,
    ActiveLearningVoiceNode.parent ||
    ActiveLearningVoiceNode.star => MasterNavigationContract.coreControlPrompt,
    _ => _lastVoiceChoicePrompt,
  };

  @override
  Future<void> pauseForMainAssistant() async {
    _audioCommandGeneration += 1;
    _cancelPendingFixedPrompt();
    _pausedForMainAssistant = true;
    _playbackInterrupted = _playingCollection;
    _setActivePlaybackEntry(null);
    await Future.wait<void>(<Future<void>>[
      _voicePromptService.stop().catchError((Object _) {}),
      _mediaService.stopPlayback().catchError((Object _) {}),
      if (_vocabularyAudioService != null)
        _vocabularyAudioService!.stop().catchError((Object _) {}),
    ]);
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted || !_isEffectivelyActive) {
      return const ActiveLearningCommandResult.unavailable();
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.resume:
        _pausedForMainAssistant = false;
        if (_playbackInterrupted) {
          unawaited(
            _runAudioCommand(() => _resumePlayback(announceResume: true)),
          );
        } else if (_waitingForPlaybackContinuation) {
          unawaited(_runAudioCommand(_continuePlayback));
        }
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyParentAdded:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.family);
        unawaited(_playJourney(_VocabularyJourney.family));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyPracticeAgain:
        if (_awaitingPlaybackEndChoice && _selectedJourney != null) {
          _pausedForMainAssistant = false;
          unawaited(_runAudioCommand(_restartCompletedPlayback));
          return const ActiveLearningCommandResult.handled();
        }
        _pausedForMainAssistant = false;
        unawaited(_runAudioCommand(_startReview));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyStars:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.stars);
        unawaited(_playJourney(_VocabularyJourney.stars));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable();
      case ActiveLearningCommand.replayCurrent:
        if (_playbackQueue.isEmpty ||
            _waitingForPlaybackContinuation ||
            _awaitingPlaybackEndChoice) {
          return const ActiveLearningCommandResult.unavailable();
        }
        _pausedForMainAssistant = false;
        _playbackInterrupted = true;
        unawaited(_runAudioCommand(() => _resumePlayback()));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.exitToHome:
        if (!_waitingForPlaybackContinuation && !_awaitingPlaybackEndChoice) {
          return const ActiveLearningCommandResult.unavailable();
        }
        _pausedForMainAssistant = false;
        unawaited(_runAudioCommand(_leavePlaybackForOtherContent));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
        _pausedForMainAssistant = false;
        if (_waitingForPlaybackContinuation) {
          unawaited(_runAudioCommand(_continuePlayback));
          return const ActiveLearningCommandResult.handled();
        }
        if (_playbackQueue.isEmpty || _awaitingPlaybackEndChoice) {
          return const ActiveLearningCommandResult.unavailable();
        }
        unawaited(_runAudioCommand(_moveToNextPlaybackItem));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
        if (_playbackQueue.isEmpty ||
            _waitingForPlaybackContinuation ||
            _awaitingPlaybackEndChoice) {
          return const ActiveLearningCommandResult.unavailable();
        }
        _pausedForMainAssistant = false;
        unawaited(_runAudioCommand(_moveToPreviousPlaybackItem));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
        return const ActiveLearningCommandResult.unavailable();
      case ActiveLearningCommand.restart:
        if (_awaitingPlaybackEndChoice && _selectedJourney != null) {
          _pausedForMainAssistant = false;
          unawaited(_runAudioCommand(_restartCompletedPlayback));
          return const ActiveLearningCommandResult.handled();
        }
        return const ActiveLearningCommandResult.unavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        overlayOpacity: 0.025,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _VocabularyHeader(
                isReady: widget.isReady,
                onBrandPressed: _selectedJourney == null
                    ? widget.onReturnToConversation
                    : () => unawaited(
                        _leavePlaybackForOtherContent(announceMenu: false),
                      ),
                backTooltip: _selectedJourney == null
                    ? context.tr('Về trang chủ', '返回主页')
                    : context.tr('Quay lại danh sách từ vựng', '返回词汇列表'),
                onAddPressed: _translating ? null : _showAddDialog,
                adding: _translating,
                showAddAction:
                    _selectedJourney == null ||
                    _selectedJourney == _VocabularyJourney.family,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _selectedJourney == null
                      ? _buildJourneyLanding(context)
                      : _buildJourneyDetail(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyLanding(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark
        ? Theme.of(context).colorScheme.primary
        : AppColors.deepNavy;
    final savedCount = _entriesForJourney(_VocabularyJourney.family).length;
    final starCount = _entriesForJourney(_VocabularyJourney.stars).length;
    final reviewCount = _entriesForJourney(_VocabularyJourney.review).length;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth <= 380;
    final horizontalPadding = screenWidth <= 360 ? 16.0 : 20.0;
    final cardHeight = compact ? 110.0 : 116.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final usableBodyHeight =
            constraints.maxHeight - MediaQuery.viewPaddingOf(context).bottom;
        final journeyGap = (12 + (usableBodyHeight - 560) * 0.1)
            .clamp(12.0, 28.0)
            .toDouble();
        return Align(
          alignment: Alignment.topCenter,
          key: const ValueKey<String>('vocabulary-journey-landing'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              key: const Key('vocabulary-home-scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 36 : 56,
                horizontalPadding,
                24 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    context.tr('Từ vựng của bạn', '你的词汇'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: titleColor,
                      fontSize: compact ? 27 : 29,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                      shadows: isDark
                          ? const <Shadow>[
                              Shadow(color: Colors.black54, blurRadius: 12),
                            ]
                          : const <Shadow>[
                              Shadow(color: Colors.white, blurRadius: 9),
                            ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr('Chọn hành trình của bạn', '选择你的学习旅程'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDark
                          ? theme.colorScheme.onSurfaceVariant
                          : AppColors.muted,
                      fontSize: compact ? 16 : 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  _JourneyCard(
                    key: const Key('vocabulary-family-card'),
                    height: cardHeight,
                    onPressed: () => _openJourney(_VocabularyJourney.family),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                _familyAsset,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: _JourneyCopy(
                            title: context.tr('Ba mẹ đã thêm', '家长添加'),
                            count: context.tr(
                              '$savedCount nội dung',
                              '$savedCount 项内容',
                            ),
                            countColor: AppColors.accentPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: journeyGap),
                  _JourneyCard(
                    key: const Key('vocabulary-stars-card'),
                    height: cardHeight,
                    onPressed: () => _openJourney(_VocabularyJourney.stars),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 2, 6),
                            child: Image.asset(
                              _starAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: _JourneyCopy(
                            title: context.tr('Ngôi sao', '小星星'),
                            count: context.tr(
                              '$starCount nội dung yêu thích',
                              '$starCount 项收藏内容',
                            ),
                            countColor: AppColors.accentPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: journeyGap),
                  _JourneyCard(
                    key: const Key('vocabulary-review-card'),
                    height: cardHeight,
                    onPressed: () => _openJourney(_VocabularyJourney.review),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
                            child: Image.asset(
                              _reviewAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: _JourneyCopy(
                            title: context.tr('Luyện lại', '复习'),
                            count: context.tr(
                              '$reviewCount nội dung cần ôn',
                              '$reviewCount 项待复习内容',
                            ),
                            countColor: AppColors.accentPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 18 : 24),
                  Semantics(
                    image: true,
                    label: context.tr('HOMI đồng hành cùng bạn', 'HOMI 陪伴你学习'),
                    child: Image.asset(
                      MascotAssets.wave,
                      key: const Key('vocabulary-landing-homi'),
                      height: compact ? 86 : 104,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJourneyDetail(BuildContext context) {
    final journey = _selectedJourney!;
    final visibleEntries = _filteredEntries;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isFamilyJourney = journey == _VocabularyJourney.family;
    final horizontalPadding = MediaQuery.sizeOf(context).width <= 430
        ? 16.0
        : 52.0;
    final headerCountLabel = switch (journey) {
      _VocabularyJourney.family => null,
      _VocabularyJourney.stars => context.tr(
        '${visibleEntries.length} từ yêu thích',
        '${visibleEntries.length} 个收藏',
      ),
      _VocabularyJourney.review => context.tr(
        '${visibleEntries.length} từ cần luyện',
        '${visibleEntries.length} 个待复习',
      ),
    };

    return Center(
      key: ValueKey<_VocabularyJourney>(journey),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleJourneyScrollNotification,
          child: SingleChildScrollView(
            controller: _journeyScrollController,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              110,
            ),
            child: Column(
              children: <Widget>[
                _JourneyDetailHeader(
                  title: _journeyTitle(context, journey),
                  countLabel: headerCountLabel,
                ),
                const SizedBox(height: 18),
                if (!isFamilyJourney) ...<Widget>[
                  _buildSearchField(context),
                  const SizedBox(height: 18),
                ],
                if (isFamilyJourney) ...<Widget>[
                  _buildParentWaitingQueue(context),
                  const SizedBox(height: 16),
                  _buildSearchField(context),
                  const SizedBox(height: 22),
                  Text(
                    context.tr(
                      '${visibleEntries.length} nội dung đã lưu',
                      '已保存 ${visibleEntries.length} 项内容',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigoDark,
                      fontWeight: FontWeight.w800,
                      shadows: isDark
                          ? const <Shadow>[
                              Shadow(color: Colors.black54, blurRadius: 10),
                            ]
                          : const <Shadow>[
                              Shadow(color: Colors.white, blurRadius: 8),
                            ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _buildJourneyAction(context, journey, visibleEntries),
                const SizedBox(height: 16),
                _buildVocabularyCard(context, visibleEntries),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyAction(
    BuildContext context,
    _VocabularyJourney journey,
    List<VocabularyEntry> visibleEntries,
  ) {
    final mascotAsset = switch (journey) {
      _VocabularyJourney.family => MascotAssets.wave,
      _VocabularyJourney.stars => MascotAssets.sing,
      _VocabularyJourney.review => MascotAssets.listen,
    };
    final mascotLabel = switch (journey) {
      _VocabularyJourney.family => context.tr(
        'HOMI chào đón nội dung ba mẹ đã thêm',
        'HOMI 欢迎家长添加的内容',
      ),
      _VocabularyJourney.stars => context.tr(
        'HOMI vui cùng những nội dung yêu thích',
        'HOMI 陪你听喜爱的内容',
      ),
      _VocabularyJourney.review => context.tr(
        'HOMI sẵn sàng luyện lại cùng bạn',
        'HOMI 准备陪你复习',
      ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Row(
        children: <Widget>[
          Semantics(
            image: true,
            label: mascotLabel,
            child: Image.asset(
              mascotAsset,
              key: ValueKey<String>('vocabulary-${journey.name}-homi'),
              width: 76,
              height: 76,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: ValueKey<String>('vocabulary-${journey.name}-action'),
                onPressed: visibleEntries.isEmpty || _playingCollection
                    ? null
                    : () => unawaited(
                        journey == _VocabularyJourney.review
                            ? _startReview()
                            : _playJourney(journey),
                      ),
                icon: _playingCollection
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        journey == _VocabularyJourney.review
                            ? Icons.mic_rounded
                            : Icons.play_arrow_rounded,
                      ),
                label: Text(
                  journey == _VocabularyJourney.review
                      ? context.tr('Bắt đầu luyện', '开始练习')
                      : context.tr('Bắt đầu nghe', '开始播放'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _searchController.text.trim();
    return TextField(
      key: const Key('vocabulary-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _searchFocusNode.unfocus(),
      decoration: InputDecoration(
        hintText: context.tr('Tìm trong bộ từ vựng…', '在词汇中搜索…'),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                key: const Key('clear-vocabulary-search'),
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded),
                tooltip: context.tr('Xóa nội dung tìm kiếm', '清除搜索内容'),
              ),
        filled: true,
        fillColor: isDark
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.88),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
      ),
    );
  }

  Widget _buildParentWaitingQueue(BuildContext context) {
    final waiting = _entries.where((entry) => entry.isWaitingParent).toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: const Key('vocabulary-waiting-queue'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceRaised : AppColors.mintSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? AppColors.darkMint.withValues(alpha: 0.48)
              : AppColors.success.withValues(alpha: 0.34),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.18)
                : AppColors.deepNavy.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkPrimary : AppColors.primaryNavy,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: isDark ? AppColors.darkCanvas : Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('Danh sách chờ', '等待列表'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isDark ? AppColors.darkText : AppColors.deepNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                key: const Key('vocabulary-waiting-count-chip'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkPink.withValues(alpha: 0.18)
                      : AppColors.accentPinkSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkPink.withValues(alpha: 0.32)
                        : AppColors.accentPink.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  '(${waiting.length})',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.darkPink : AppColors.accentPink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (waiting.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 8, 8, 4),
              child: Text(
                context.tr('Chưa có nội dung đang chờ.', '暂无等待内容。'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.darkMuted : AppColors.muted,
                ),
              ),
            )
          else ...<Widget>[
            const SizedBox(height: 12),
            for (var index = 0; index < waiting.length; index++)
              Container(
                key: ValueKey<String>(
                  'vocabulary-waiting-item-${waiting[index].id}',
                ),
                margin: EdgeInsets.only(
                  bottom: index == waiting.length - 1 ? 0 : 9,
                ),
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceStrong.withValues(alpha: 0.82)
                      : Colors.white.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkOutline
                        : AppColors.mintBorder,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.12)
                          : AppColors.primaryNavy.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      key: ValueKey<String>(
                        'vocabulary-waiting-order-${waiting[index].id}',
                      ),
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkPrimary
                            : AppColors.primaryNavy,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color:
                                (isDark
                                        ? AppColors.darkPrimary
                                        : AppColors.primaryNavy)
                                    .withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isDark ? AppColors.darkCanvas : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            waiting[index].word,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: isDark
                                  ? AppColors.darkText
                                  : AppColors.deepNavy,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            waiting[index].meaning,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? AppColors.darkMuted
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (waiting[index].canParentEdit)
                      IconButton.filledTonal(
                        key: ValueKey<String>(
                          'edit-waiting-${waiting[index].id}',
                        ),
                        onPressed: () =>
                            unawaited(_editParentEntry(waiting[index])),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        tooltip: context.tr('Sửa', '编辑'),
                      ),
                    if (waiting[index].canParentDelete)
                      IconButton.filledTonal(
                        key: ValueKey<String>(
                          'delete-queued-${waiting[index].id}',
                        ),
                        onPressed: () => unawaited(_delete(waiting[index])),
                        style: IconButton.styleFrom(
                          foregroundColor: isDark
                              ? AppColors.darkPink
                              : AppColors.accentPink,
                          backgroundColor: isDark
                              ? AppColors.darkPink.withValues(alpha: 0.14)
                              : AppColors.accentPinkSoft,
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        tooltip: context.tr('Xóa', '删除'),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildVocabularyCard(
    BuildContext context,
    List<VocabularyEntry> entries,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return const SizedBox(
        height: 330,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final journey = _selectedJourney ?? _VocabularyJourney.family;
    if (journey != _VocabularyJourney.family && entries.isNotEmpty) {
      final statusLabel = journey == _VocabularyJourney.review
          ? context.tr('Cần luyện', '待复习')
          : context.tr('Yêu thích', '收藏');
      return Column(
        children: <Widget>[
          for (var index = 0; index < entries.length; index++)
            KeyedSubtree(
              key: _entryKey(journey, entries[index].id),
              child: Container(
                key: ValueKey<String>(
                  'vocabulary-entry-card-${entries[index].id}',
                ),
                width: double.infinity,
                margin: EdgeInsets.only(
                  bottom: index == entries.length - 1 ? 0 : 10,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark
                      ? Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.94)
                      : const Color(0xF7FFFDF9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.55)
                        : const Color(0x80FFFFFF),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.2)
                          : AppColors.deepNavy.withValues(alpha: 0.1),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _VocabularyRow(
                  entry: entries[index],
                  order: index + 1,
                  canPlay:
                      !entries[index].isParentAdded ||
                      entries[index].isLearnedWell,
                  isActive: _activePlaybackEntryId == entries[index].id,
                  statusLabel: statusLabel,
                  onPlay: () => unawaited(_playEntry(entries[index])),
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      key: ValueKey<String>('vocabulary-${journey.name}-saved-content'),
      width: double.infinity,
      constraints: BoxConstraints(minHeight: entries.isEmpty ? 330 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: scenicPanelDecoration(
        radius: 28,
        color: isDark
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.94)
            : const Color(0xEFFFFDF9),
        borderColor: isDark
            ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)
            : const Color(0x66FFFFFF),
      ),
      child: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 70),
                child: Text(
                  journey == _VocabularyJourney.family
                      ? context.tr(
                          'Chưa có nội dung phù hợp. Bạn thử tìm nội dung khác nhé.',
                          '没有匹配的内容，请尝试其他关键词。',
                        )
                      : journey == _VocabularyJourney.stars
                      ? context.tr(
                          'Bạn chưa có nội dung yêu thích.',
                          '还没有收藏内容。',
                        )
                      : context.tr(
                          'Hiện chưa có nội dung cần luyện lại.',
                          '目前没有需要复习的内容。',
                        ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (
                  var index = 0;
                  index < entries.length;
                  index++
                ) ...<Widget>[
                  KeyedSubtree(
                    key: _entryKey(journey, entries[index].id),
                    child: _VocabularyRow(
                      entry: entries[index],
                      order: index + 1,
                      canPlay:
                          !entries[index].isParentAdded ||
                          entries[index].isLearnedWell,
                      isActive: _activePlaybackEntryId == entries[index].id,
                      onPlay: () => unawaited(_playEntry(entries[index])),
                    ),
                  ),
                  if (index != entries.length - 1)
                    Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      height: 1,
                    ),
                ],
              ],
            ),
    );
  }

  void _openJourney(_VocabularyJourney journey) {
    setState(() {
      _selectedJourney = journey;
      _activePlaybackEntryId = null;
      _searchController.clear();
    });
  }

  void _closeJourney() {
    _searchFocusNode.unfocus();
    setState(() {
      _selectedJourney = null;
      _activePlaybackEntryId = null;
      _autoScrollGeneration += 1;
      _lastVoiceChoicePrompt = VocabularyFlowV3.menu;
      _searchController.clear();
    });
  }

  bool _handleJourneyScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userIsScrollingJourney = true;
    } else if (notification is ScrollEndNotification &&
        _userIsScrollingJourney) {
      _userIsScrollingJourney = false;
    }
    return false;
  }

  GlobalKey _entryKey(_VocabularyJourney journey, String entryId) =>
      _entryKeys.putIfAbsent('${journey.name}:$entryId', GlobalKey.new);

  void _setActivePlaybackEntry(String? entryId) {
    if (_activePlaybackEntryId == entryId) {
      if (entryId != null) _scheduleActiveEntryVisibility();
      return;
    }
    if (!mounted) {
      _activePlaybackEntryId = entryId;
      return;
    }
    setState(() => _activePlaybackEntryId = entryId);
    if (entryId == null) {
      _autoScrollGeneration += 1;
    } else {
      _scheduleActiveEntryVisibility();
    }
  }

  void _scheduleActiveEntryVisibility() {
    final entryId = _activePlaybackEntryId;
    final journey = _selectedJourney;
    if (entryId == null || journey == null || _userIsScrollingJourney) return;
    final generation = ++_autoScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _autoScrollGeneration ||
          _userIsScrollingJourney ||
          _activePlaybackEntryId != entryId ||
          _selectedJourney != journey) {
        return;
      }
      unawaited(_ensureActiveEntryVisible(journey, entryId));
    });
  }

  Future<void> _ensureActiveEntryVisible(
    _VocabularyJourney journey,
    String entryId,
  ) async {
    final itemContext = _entryKey(journey, entryId).currentContext;
    if (itemContext == null || !_journeyScrollController.hasClients) return;
    final itemBox = itemContext.findRenderObject();
    final scrollable = Scrollable.maybeOf(itemContext);
    final viewportBox = scrollable?.context.findRenderObject();
    if (itemBox is! RenderBox || viewportBox is! RenderBox) return;
    final itemTop = itemBox
        .localToGlobal(Offset.zero, ancestor: viewportBox)
        .dy;
    final itemBottom = itemTop + itemBox.size.height;
    final viewportHeight = viewportBox.size.height;
    if (itemTop >= 0 && itemBottom <= viewportHeight) return;
    await Scrollable.ensureVisible(
      itemContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: itemTop < 0 ? 0 : 1,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  String _journeyTitle(BuildContext context, _VocabularyJourney journey) {
    return switch (journey) {
      _VocabularyJourney.family => context.tr('Ba mẹ đã thêm', '家长添加'),
      _VocabularyJourney.stars => context.tr('Ngôi sao của bạn', '我的星星'),
      _VocabularyJourney.review => context.tr('Luyện lại', '复习'),
    };
  }

  List<VocabularyEntry> get _filteredEntries {
    final journey = _selectedJourney ?? _VocabularyJourney.family;
    final journeyEntries = _entriesForJourney(journey);
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return journeyEntries;
    }
    return journeyEntries
        .where((entry) {
          return entry.word.toLowerCase().contains(query) ||
              entry.meaning.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<VocabularyEntry> _entriesForJourney(_VocabularyJourney journey) {
    return switch (journey) {
      _VocabularyJourney.family => _journeyIndex.family,
      _VocabularyJourney.stars => _journeyIndex.stars,
      _VocabularyJourney.review => _journeyIndex.review,
    };
  }

  Future<void> _load() async {
    final entries = await widget.store.read();
    final journeyIndex = VocabularyJourneyIndex.fromEntries(entries);
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _journeyIndex = journeyIndex;
      _loading = false;
    });
    if (_isEffectivelyActive && widget.autoStartToday && !_todayOffered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeStartToday());
      });
    }
  }

  Future<void> _delete(VocabularyEntry entry) async {
    try {
      await widget.store.deleteParentEntry(entry.id);
      await _releaseParentAudio(entry);
      await _load();
    } on VocabularyValidationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _editParentEntry(VocabularyEntry entry) async {
    final input = await showDialog<VocabularyTranslation>(
      context: context,
      builder: (_) => _EditVocabularyDialog(entry: entry),
    );
    if (input == null) return;
    setState(() => _translating = true);
    try {
      await widget.store.updateParentEntry(entryId: entry.id, value: input);
      await _releaseParentAudio(entry);
      await _load();
    } on VocabularyValidationException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Chưa sửa được nội dung này. Ba mẹ thử lại nhé.');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _refreshSearch() => setState(() {});

  Future<void> _showAddDialog() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _AddVocabularyDialog(),
    );
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }

    await _addVocabulary(normalized);
  }

  Future<void> _addVocabulary(String normalized) async {
    setState(() => _translating = true);
    try {
      final waitingCount = await widget.store.parentWaitingCount();
      final remaining = VocabularyStore.parentWaitingLimit - waitingCount;
      if (remaining <= 0) {
        throw const VocabularyDailyLimitException(remaining: 0);
      }
      final resolution = await _translateVocabulary(normalized);
      final selections = await _prepareParentChoices(
        input: normalized,
        translated: resolution.primary,
        initialSuggestions: resolution.alternatives,
        partOfSpeech: resolution.partOfSpeech,
        maxSelections: remaining.clamp(1, 3),
      );
      if (selections == null || selections.isEmpty) return;
      final curriculumDuplicateChecker = widget.curriculumDuplicateChecker;
      if (curriculumDuplicateChecker != null) {
        for (final selection in selections) {
          if (await curriculumDuplicateChecker(selection)) {
            throw const VocabularyTopicDuplicateException();
          }
        }
      }
      final entries = await widget.store.addParentEntries(
        selections,
        childAge: widget.childAge,
      );
      final journeyIndex = VocabularyJourneyIndex.fromEntries(entries);
      _prefetchParentAudio(selections);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _journeyIndex = journeyIndex;
        _selectedJourney = _VocabularyJourney.family;
        _searchController.clear();
      });
    } on VocabularyValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa xử lý được nội dung này. Ba mẹ thử lại nhé.',
              '暂时无法处理此内容，请重试。',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _translating = false);
      }
    }
  }

  void _prefetchParentAudio(List<VocabularyTranslation> selections) {
    final audioService = _vocabularyAudioService;
    if (audioService == null) return;
    unawaited(() async {
      for (final selection in selections) {
        await Future.wait<void>(<Future<void>>[
          audioService.prefetch(selection.englishText, locale: 'en-US'),
          audioService.prefetch(selection.vietnameseText, locale: 'vi-VN'),
        ]);
      }
    }());
  }

  Future<void> _maybeStartToday() async {
    if (!mounted ||
        !_isEffectivelyActive ||
        _openingPractice ||
        _startingToday ||
        _pausedForMainAssistant) {
      return;
    }
    _startingToday = true;
    try {
      final firstEntryToday = await widget.sessionStore
          .markAndCheckFirstEntryToday(DateTime.now());
      final activeBeforeEntry = await widget.sessionStore.readActive();
      final session = await widget.sessionStore.prepareToday(widget.store);
      _todayOffered = true;
      if (session == null) {
        if (mounted && _isEffectivelyActive) {
          await _speakAndRequestChoice(
            firstEntryToday
                ? VocabularyFlowV3.todayEmptyMenu
                : VocabularyFlowV3.menu,
          );
        }
        return;
      }
      if (!mounted || !_isEffectivelyActive) return;
      await _runPracticeSession(
        session,
        announceInitialIntro: activeBeforeEntry?.id != session.id,
        announceInitialResume: activeBeforeEntry?.id == session.id,
      );
    } finally {
      _startingToday = false;
    }
  }

  Future<void> _startReview() async {
    if (_openingPractice || !mounted) return;
    _openJourney(_VocabularyJourney.review);
    final active = await widget.sessionStore.readActive();
    if (active?.mode == VocabularyPracticeMode.today) {
      await _speakOnSelectedOutput(VocabularyFlowV3.finishActiveGroupFirst);
      await _runPracticeSession(active!, announceInitialIntro: false);
      return;
    }
    final session = active?.mode == VocabularyPracticeMode.review
        ? active
        : await widget.sessionStore.prepareReview(widget.store);
    if (session == null || !mounted) {
      await _speakAndRequestChoice(VocabularyFlowV3.reviewEmpty);
      return;
    }
    await _runPracticeSession(
      session,
      announceInitialIntro: active?.id != session.id,
      announceInitialResume: active?.id == session.id,
    );
  }

  Future<void> _runPracticeSession(
    VocabularyPracticeSession first, {
    bool announceInitialIntro = true,
    bool announceInitialResume = false,
  }) async {
    if (_openingPractice || !mounted) return;
    _openingPractice = true;
    var session = first;
    var announceIntro = announceInitialIntro;
    var announceResume = announceInitialResume;
    try {
      while (true) {
        if (!mounted) return;
        final language = DisplayLanguageScope.of(context);
        final result = await pushForActiveLearning<VocabularyPracticeResult>(
          context,
          (_) => VocabularyPracticeScreen(
            language: language,
            childAge: widget.childAge,
            session: session,
            store: widget.store,
            sessionStore: widget.sessionStore,
            mediaService: _mediaService,
            audioDependencies: widget.audioDependencies,
            voicePromptService: _voicePromptService,
            vocabularyAudioService: _vocabularyAudioService,
            fixedPromptAudioService: _fixedPromptAudioService,
            onRequestVoiceChoice: widget.onRequestVoiceChoice,
            announceIntro: announceIntro,
            announceResume: announceResume,
          ),
        );
        if (!mounted) return;
        await _load();
        if (result == null) {
          return; // Back preserves the active checkpoint silently.
        }
        if (result == VocabularyPracticeResult.parentAdded ||
            result == VocabularyPracticeResult.stars) {
          final active = await widget.sessionStore.readActive();
          if (session.mode == VocabularyPracticeMode.today && active == null) {
            await widget.sessionStore.suppressToday(DateTime.now());
          } else if (session.mode == VocabularyPracticeMode.review &&
              active == null) {
            await widget.sessionStore.endReviewSession();
          }
          final journey = result == VocabularyPracticeResult.stars
              ? _VocabularyJourney.stars
              : _VocabularyJourney.family;
          _openJourney(journey);
          await _playJourney(journey);
          return;
        }
        if (result != VocabularyPracticeResult.continueLearning) {
          final active = await widget.sessionStore.readActive();
          if (session.mode == VocabularyPracticeMode.today && active == null) {
            await widget.sessionStore.suppressToday(DateTime.now());
            await _speakAndRequestChoice(VocabularyFlowV3.menu);
          } else if (session.mode == VocabularyPracticeMode.review &&
              active == null) {
            await widget.sessionStore.endReviewSession();
            await _speakAndRequestChoice(VocabularyFlowV3.reviewOtherMenu);
          }
          return;
        }
        final next = switch (session.mode) {
          VocabularyPracticeMode.today =>
            await widget.sessionStore.prepareTodayReplay(widget.store),
          VocabularyPracticeMode.review =>
            await widget.sessionStore.prepareReview(
              widget.store,
              forceNextGroup: true,
            ),
        };
        if (next == null) {
          final prompt = session.mode == VocabularyPracticeMode.today
              ? VocabularyFlowV3.todayQueueEmpty
              : VocabularyFlowV3.reviewCycleFinished;
          await _speakAndRequestChoice(prompt);
          return;
        }
        session = next;
        announceIntro = false;
        announceResume = false;
      }
    } finally {
      _openingPractice = false;
    }
  }

  Future<void> _runAudioCommand(Future<void> Function() action) async {
    final generation = ++_audioCommandGeneration;
    try {
      await action();
    } catch (error) {
      if (!mounted ||
          !_isEffectivelyActive ||
          _pausedForMainAssistant ||
          generation != _audioCommandGeneration) {
        return;
      }
      _showMessage(_friendlyPlaybackError(error));
    }
  }

  Future<void> _playJourney(_VocabularyJourney journey) =>
      _runAudioCommand(() => _playJourneyWithOutput(journey));

  Future<void> _playJourneyWithOutput(_VocabularyJourney journey) async {
    final generation = _playbackGeneration;
    await _playbackNavigationCleanup;
    if (!mounted || generation != _playbackGeneration) return;
    if (_playingCollection || !mounted) return;
    if (await _resumeBlockingPracticeIfNeeded()) return;
    if (!mounted || generation != _playbackGeneration) return;

    _openJourney(journey);
    final entries = _entriesForJourney(journey);
    if (entries.isEmpty) {
      await _speakAndRequestChoice(
        journey == _VocabularyJourney.family
            ? VocabularyFlowV3.parentEmpty
            : VocabularyFlowV3.starEmpty,
      );
      return;
    }

    final flowJourney = journey == _VocabularyJourney.family
        ? VocabularyJourneyKind.parentAdded
        : VocabularyJourneyKind.stars;
    final queue = VocabularyFlowV3.orderedForPlayback(
      entries,
      journey: flowJourney,
    );
    final branch = '${journey.name}:ordered';
    final start = VocabularyFlowV3.playbackStartIndex(
      checkpoint: await widget.sessionStore.readPlaybackCheckpoint(branch),
      total: queue.length,
    );

    if (start > 0) {
      await _speakOnSelectedOutput(VocabularyFlowV3.resumeStars);
    } else {
      await _speakOnSelectedOutput(
        journey == _VocabularyJourney.family
            ? VocabularyFlowV3.parentSmallIntro
            : VocabularyFlowV3.starIntro,
      );
    }

    _waitingForPlaybackContinuation = false;
    _awaitingPlaybackEndChoice = false;
    if (!mounted || generation != _playbackGeneration) return;
    await _playQueue(
      queue,
      startIndex: start,
      branch: branch,
      checkpoint: true,
      journey: journey,
      announceStarVoice: journey == _VocabularyJourney.stars,
    );
  }

  Future<void> _playEntry(VocabularyEntry entry) async {
    if (entry.isLearnedWell || entry.isStar) {
      await _playQueue(
        <VocabularyEntry>[entry],
        branch: 'single:${entry.id}',
        checkpoint: false,
        journey: entry.isStar
            ? _VocabularyJourney.stars
            : _VocabularyJourney.family,
      );
      return;
    }
    _showMessage('Nội dung này cần được học xong trước khi nghe lại.');
  }

  Future<void> _playQueue(
    List<VocabularyEntry> entries, {
    required String branch,
    required bool checkpoint,
    required _VocabularyJourney journey,
    int startIndex = 0,
    bool announceStarVoice = false,
    int? blockStartIndex,
  }) async {
    final pendingGeneration = _playbackGeneration;
    await _playbackNavigationCleanup;
    if (!mounted || pendingGeneration != _playbackGeneration) return;
    if (_playingCollection || entries.isEmpty) return;
    final generation = ++_playbackGeneration;
    _playbackQueue = entries;
    _playbackIndex = startIndex;
    _playbackBlockStartIndex = blockStartIndex ?? startIndex;
    _playbackBlockEndExclusive = VocabularyFlowV3.playbackBlockEnd(
      start: _playbackBlockStartIndex,
      total: entries.length,
    );
    _playbackBranch = branch;
    _nextPlaybackIndex = startIndex;
    _playbackInterrupted = false;
    _waitingForPlaybackContinuation = false;
    _awaitingPlaybackEndChoice = false;
    if (mounted) setState(() => _playingCollection = true);
    try {
      for (
        var index = startIndex;
        index < _playbackBlockEndExclusive;
        index++
      ) {
        _playbackIndex = index;
        if (generation != _playbackGeneration) return;
        if (_pausedForMainAssistant) {
          _playbackInterrupted = true;
          return;
        }
        _setActivePlaybackEntry(entries[index].id);
        final played = await _speakVocabularyEntry(
          entries[index],
          journey: journey,
          announceStarVoice: announceStarVoice && index == startIndex,
          generation: generation,
        );
        if (generation != _playbackGeneration) return;
        if (_pausedForMainAssistant) {
          _playbackInterrupted = true;
          return;
        }
        if (checkpoint) {
          await widget.sessionStore.savePlaybackCheckpoint(branch, index + 1);
        }
        _nextPlaybackIndex = index + 1;
        if (!played) continue;
      }
      _setActivePlaybackEntry(null);
      _playbackInterrupted = false;
      if (_playbackBlockEndExclusive < entries.length) {
        _nextPlaybackIndex = _playbackBlockEndExclusive;
        _waitingForPlaybackContinuation = true;
        await _speakAndRequestChoice(
          journey == _VocabularyJourney.stars
              ? VocabularyFlowV3.starGroupCompletion
              : VocabularyFlowV3.parentGroupCompletion,
        );
        return;
      }
      if (checkpoint) {
        await widget.sessionStore.savePlaybackCheckpoint(
          branch,
          entries.length,
        );
      }
      _waitingForPlaybackContinuation = false;
      _awaitingPlaybackEndChoice = !branch.startsWith('single:');
      if (!branch.startsWith('single:')) {
        await _speakAndRequestChoice(
          journey == _VocabularyJourney.stars
              ? VocabularyFlowV3.starFinished
              : VocabularyFlowV3.parentFinished,
        );
      }
    } catch (error) {
      if (generation != _playbackGeneration) return;
      if (_pausedForMainAssistant) {
        _playbackInterrupted = true;
      } else {
        _showMessage(_friendlyPlaybackError(error));
      }
    } finally {
      if (mounted && generation == _playbackGeneration) {
        setState(() {
          _playingCollection = false;
          _activePlaybackEntryId = null;
        });
        _autoScrollGeneration += 1;
      }
    }
  }

  Future<bool> _speakVocabularyEntry(
    VocabularyEntry entry, {
    required _VocabularyJourney journey,
    bool announceStarVoice = false,
    required int generation,
  }) async {
    final path = journey == _VocabularyJourney.stars
        ? entry.correctAudioPath?.trim()
        : null;
    if (journey == _VocabularyJourney.stars && (path == null || path.isEmpty)) {
      debugPrint('VOCABULARY_STAR_AUDIO_MISSING slot=${entry.starSlotId}');
      return false;
    }
    await _mediaService.prepareSelectedLessonOutput();
    if (generation != _playbackGeneration || _pausedForMainAssistant) {
      return false;
    }
    await _speakVocabularyText(entry, entry.word, locale: 'en-US');
    if (generation != _playbackGeneration || _pausedForMainAssistant) {
      return false;
    }
    await _speakVocabularyText(entry, entry.meaning, locale: 'vi-VN');
    if (generation != _playbackGeneration || _pausedForMainAssistant) {
      return false;
    }
    if (path == null || path.isEmpty) return true;
    if (announceStarVoice) {
      await _speakOnSelectedOutput(VocabularyFlowV3.starMyVoice);
      if (generation != _playbackGeneration || _pausedForMainAssistant) {
        return false;
      }
    }
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.file(path);
    try {
      await _mediaService.playToCompletion(
        uri,
        playbackGainDb: lessonRecordingPlaybackGainDb,
      );
    } catch (error) {
      if (journey == _VocabularyJourney.stars) {
        debugPrint(
          'VOCABULARY_STAR_AUDIO_FAILED slot=${entry.starSlotId} error=$error',
        );
        return false;
      }
      rethrow;
    }
    return true;
  }

  Future<void> _resumePlayback({bool announceResume = false}) async {
    await _waitForPlaybackToSettle();
    if (!_playbackInterrupted || _playbackQueue.isEmpty || _playingCollection) {
      return;
    }
    final queue = _playbackQueue;
    final branch = _playbackBranch ?? 'resume';
    _playbackInterrupted = false;
    if (announceResume) {
      await _speakOnSelectedOutput(VocabularyFlowV3.resumeStars);
      if (_pausedForMainAssistant) return;
    }
    await _playQueue(
      queue,
      startIndex: _playbackIndex,
      branch: branch,
      checkpoint: !branch.startsWith('single:'),
      blockStartIndex: _playbackBlockStartIndex,
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
    );
  }

  Future<void> _continuePlayback() async {
    if (_playingCollection || _playbackQueue.isEmpty) return;
    final branch = _playbackBranch ?? '';
    final start = _nextPlaybackIndex.clamp(0, _playbackQueue.length);
    if (start >= _playbackQueue.length) return;
    _waitingForPlaybackContinuation = false;
    await _playQueue(
      _playbackQueue,
      startIndex: start,
      branch: branch,
      checkpoint: !branch.startsWith('single:'),
      blockStartIndex: start,
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
      announceStarVoice: branch.startsWith('stars:'),
    );
  }

  Future<void> _moveToPreviousPlaybackItem() async {
    final generation = _audioCommandGeneration;
    await _waitForPlaybackToSettle();
    if (!mounted ||
        !_isEffectivelyActive ||
        generation != _audioCommandGeneration ||
        _playingCollection ||
        _playbackQueue.isEmpty) {
      return;
    }
    final branch = _playbackBranch ?? '';
    final atBlockStart = _playbackIndex <= _playbackBlockStartIndex;
    final target = atBlockStart ? _playbackBlockStartIndex : _playbackIndex - 1;
    _playbackInterrupted = false;
    if (atBlockStart) {
      const firstPrevious = LessonGuidePrompt(
        audioCode: 'CORE_FIRST_PREVIOUS',
        text: 'Đây là câu đầu tiên. Mình nghe lại nhé.',
      );
      final authored = await _fixedPromptAudioService.playAudioCodeIfAvailable(
        firstPrevious.audioCode,
      );
      if (!authored) {
        await _speakOnSelectedOutput(
          firstPrevious.text,
          allowFixedPrompt: false,
        );
      }
    }
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        generation != _audioCommandGeneration) {
      return;
    }
    if (!branch.startsWith('single:')) {
      await widget.sessionStore.savePlaybackCheckpoint(branch, target);
    }
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        generation != _audioCommandGeneration) {
      return;
    }
    await _playQueue(
      _playbackQueue,
      startIndex: target,
      branch: branch,
      checkpoint: !branch.startsWith('single:'),
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
      blockStartIndex: _playbackBlockStartIndex,
    );
  }

  Future<void> _moveToNextPlaybackItem() async {
    final generation = _audioCommandGeneration;
    await _waitForPlaybackToSettle();
    if (!mounted ||
        !_isEffectivelyActive ||
        generation != _audioCommandGeneration ||
        _playingCollection ||
        _playbackQueue.isEmpty) {
      return;
    }
    final branch = _playbackBranch ?? '';
    final next = (_playbackIndex + 1).clamp(0, _playbackQueue.length);
    _playbackInterrupted = false;
    if (!branch.startsWith('single:')) {
      await widget.sessionStore.savePlaybackCheckpoint(branch, next);
    }
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        generation != _audioCommandGeneration) {
      return;
    }
    if (next >= _playbackBlockEndExclusive) {
      await _completePlaybackBlockFromCommand(next);
      return;
    }
    await _speakOnSelectedOutput(MasterNavigationContract.nextItemPrompt);
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        generation != _audioCommandGeneration) {
      return;
    }
    await _playQueue(
      _playbackQueue,
      startIndex: next,
      branch: branch,
      checkpoint: !branch.startsWith('single:'),
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
      blockStartIndex: _playbackBlockStartIndex,
    );
  }

  Future<void> _completePlaybackBlockFromCommand(int nextIndex) async {
    final journey = (_playbackBranch ?? '').startsWith('stars:')
        ? _VocabularyJourney.stars
        : _VocabularyJourney.family;
    _playbackIndex = nextIndex.clamp(0, _playbackQueue.length);
    _nextPlaybackIndex = _playbackIndex;
    _waitingForPlaybackContinuation = _playbackIndex < _playbackQueue.length;
    _awaitingPlaybackEndChoice = !_waitingForPlaybackContinuation;
    await _speakAndRequestChoice(
      _waitingForPlaybackContinuation
          ? (journey == _VocabularyJourney.stars
                ? VocabularyFlowV3.starGroupCompletion
                : VocabularyFlowV3.parentGroupCompletion)
          : (journey == _VocabularyJourney.stars
                ? VocabularyFlowV3.starFinished
                : VocabularyFlowV3.parentFinished),
    );
  }

  Future<void> _restartCompletedPlayback() async {
    final journey = _selectedJourney;
    if (journey == null || _playbackQueue.isEmpty) return;
    _awaitingPlaybackEndChoice = false;
    _waitingForPlaybackContinuation = false;
    final branch = _playbackBranch ?? '${journey.name}:ordered';
    if (!branch.startsWith('single:')) {
      await widget.sessionStore.savePlaybackCheckpoint(branch, 0);
    }
    await _playQueue(
      _playbackQueue,
      startIndex: 0,
      branch: branch,
      checkpoint: !branch.startsWith('single:'),
      journey: journey,
      blockStartIndex: 0,
      announceStarVoice: journey == _VocabularyJourney.stars,
    );
  }

  Future<void> _waitForPlaybackToSettle() async {
    for (var attempt = 0; attempt < 100 && _playingCollection; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<bool> _resumeBlockingPracticeIfNeeded() async {
    final active = await widget.sessionStore.readActive();
    if (active == null) return false;
    if (active.mode == VocabularyPracticeMode.today) {
      await _speakOnSelectedOutput(VocabularyFlowV3.finishActiveGroupFirst);
    }
    await _runPracticeSession(
      active,
      announceInitialIntro: false,
      announceInitialResume: true,
    );
    return true;
  }

  Future<void> _leavePlaybackForOtherContent({
    bool announceMenu = true,
    bool notifyNavigationExit = true,
  }) async {
    if (_playbackNavigationCleanup != null && announceMenu) return;
    _cancelPendingFixedPrompt();
    if (!announceMenu && notifyNavigationExit) {
      ActiveLearningModuleScope.notifyNavigationExit(context);
    }
    final journey = _selectedJourney;
    // Touch and MAIN use the same cancellation boundary. Update the screen
    // immediately, while an old audio callback can no longer advance its queue.
    _playbackGeneration++;
    _playbackInterrupted = false;
    _waitingForPlaybackContinuation = false;
    _awaitingPlaybackEndChoice = false;
    _playingCollection = false;
    _closeJourney();
    final cleanup = _boundPlaybackNavigationCleanup(
      Future.wait<void>(<Future<void>>[
        _voicePromptService.stop().catchError((Object _) {}),
        _mediaService.stopPlayback().catchError((Object _) {}),
        if (_vocabularyAudioService != null)
          _vocabularyAudioService!.stop().catchError((Object _) {}),
      ]).then<void>((_) {}),
    );
    _playbackNavigationCleanup = cleanup;
    try {
      await cleanup;
    } finally {
      if (identical(_playbackNavigationCleanup, cleanup)) {
        _playbackNavigationCleanup = null;
      }
    }
    if (!announceMenu ||
        !mounted ||
        !_isEffectivelyActive ||
        _selectedJourney != null) {
      return;
    }
    await _speakAndRequestChoice(
      journey == _VocabularyJourney.family
          ? VocabularyFlowV3.parentOtherMenu
          : journey == _VocabularyJourney.stars
          ? VocabularyFlowV3.starOtherMenu
          : VocabularyFlowV3.menu,
    );
  }

  Future<void> _boundPlaybackNavigationCleanup(Future<void> operation) {
    _finishPlaybackNavigationCleanup();
    final completer = Completer<void>();
    _playbackNavigationCleanupCompleter = completer;
    void finishThisCleanup() {
      if (identical(_playbackNavigationCleanupCompleter, completer)) {
        _finishPlaybackNavigationCleanup();
      }
    }

    _playbackNavigationCleanupTimer = Timer(const Duration(seconds: 2), () {
      finishThisCleanup();
    });
    unawaited(
      operation.then(
        (_) => finishThisCleanup(),
        onError: (Object _, StackTrace _) => finishThisCleanup(),
      ),
    );
    return completer.future;
  }

  void _finishPlaybackNavigationCleanup() {
    _playbackNavigationCleanupTimer?.cancel();
    _playbackNavigationCleanupTimer = null;
    final completer = _playbackNavigationCleanupCompleter;
    _playbackNavigationCleanupCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> _speakAndRequestChoice(String prompt) async {
    final generation = _playbackGeneration;
    _lastVoiceChoicePrompt = prompt;
    await _speakOnSelectedOutput(prompt);
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        generation != _playbackGeneration) {
      return;
    }
    if (_playingCollection) setState(() => _playingCollection = false);
    await _requestVoiceChoice(
      noSpeechRetryPrompt: prompt,
      noSpeechExitPrompt: VocabularyFlowV3.pauseAfterNoResponse,
    );
  }

  Future<void> _requestVoiceChoice({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  }) async {
    if (!mounted ||
        !_isEffectivelyActive ||
        _pausedForMainAssistant ||
        widget.onRequestVoiceChoice == null) {
      return;
    }
    await widget.onRequestVoiceChoice!.call(
      noSpeechRetryPrompt: noSpeechRetryPrompt,
      noSpeechExitPrompt: noSpeechExitPrompt,
    );
  }

  Future<List<VocabularyTranslation>?> _prepareParentChoices({
    required String input,
    required VocabularyTranslation translated,
    List<VocabularyTranslation> initialSuggestions =
        const <VocabularyTranslation>[],
    String? partOfSpeech,
    required int maxSelections,
  }) async {
    VocabularyValidationException? originalError;
    var originalAccepted = true;
    try {
      await widget.store.validateParentCandidate(
        translated,
        childAge: widget.childAge,
      );
      final curriculumDuplicateChecker = widget.curriculumDuplicateChecker;
      if (curriculumDuplicateChecker != null &&
          await curriculumDuplicateChecker(translated)) {
        throw const VocabularyTopicDuplicateException();
      }
    } on VocabularyDuplicateException {
      rethrow;
    } on VocabularyTopicDuplicateException {
      rethrow;
    } on VocabularyValidationException catch (error) {
      originalAccepted = false;
      originalError = error;
    }

    final candidates = <VocabularyTranslation>[
      if (originalAccepted) translated,
      ...initialSuggestions,
      ..._approvedSuggestionsFor(translated),
    ];
    const targetOptionCount = 3;
    var options = await _filterParentSuggestions(
      candidates,
      limit: targetOptionCount,
      childAge: widget.childAge,
    );
    final provider = widget.suggestionProvider;
    if (provider != null && options.length < targetOptionCount) {
      try {
        final authoredSuggestions = await provider(input, widget.childAge);
        options = await _filterParentSuggestions(
          <VocabularyTranslation>[...options, ...authoredSuggestions],
          limit: targetOptionCount,
          childAge: widget.childAge,
        );
      } catch (error) {
        debugPrint('VOCABULARY_SUGGESTION_FALLBACK_FAILED error=$error');
      }
    }
    if (options.length < targetOptionCount) {
      const localProvider = LocalVocabularySuggestionProvider();
      final localSuggestions = <VocabularyTranslation>[
        ...localProvider.suggest(base: translated, partOfSpeech: partOfSpeech),
        if (partOfSpeech?.trim().isNotEmpty ?? false)
          ...localProvider.suggest(base: translated),
      ];
      options = await _filterParentSuggestions(
        <VocabularyTranslation>[...options, ...localSuggestions],
        limit: targetOptionCount,
        childAge: widget.childAge,
      );
    }
    if (options.length < targetOptionCount) {
      if (originalError != null) throw originalError;
      throw const VocabularyValidationException(
        'Chưa tạo đủ 3 phương án phù hợp. Ba mẹ thử nội dung khác nhé.',
      );
    }
    if (!mounted) return null;
    return showDialog<List<VocabularyTranslation>>(
      context: context,
      builder: (_) => _VocabularySuggestionDialog(
        options: options,
        maxSelections: maxSelections,
      ),
    );
  }

  Future<List<VocabularyTranslation>> _filterParentSuggestions(
    Iterable<VocabularyTranslation> candidates, {
    required int limit,
    required int childAge,
  }) async {
    final candidateList = candidates.toList(growable: false);
    final locallyValid = await widget.store.filterParentSuggestions(
      candidateList,
      limit: candidateList.length,
      childAge: childAge,
    );
    final curriculumDuplicateChecker = widget.curriculumDuplicateChecker;
    if (curriculumDuplicateChecker == null) {
      return locallyValid.take(limit).toList(growable: false);
    }
    final result = <VocabularyTranslation>[];
    for (final candidate in locallyValid) {
      if (!await curriculumDuplicateChecker(candidate)) {
        result.add(candidate);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  List<VocabularyTranslation> _approvedSuggestionsFor(
    VocabularyTranslation translated,
  ) {
    const catalog = <String, List<VocabularyTranslation>>{
      'apple': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Red apple',
          vietnameseText: 'Quả táo đỏ',
        ),
        VocabularyTranslation(
          englishText: 'Green apple',
          vietnameseText: 'Quả táo xanh',
        ),
        VocabularyTranslation(
          englishText: 'I like apples',
          vietnameseText: 'Con thích táo',
        ),
      ],
      'family': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'My family',
          vietnameseText: 'Gia đình của con',
        ),
        VocabularyTranslation(
          englishText: 'This is my mother',
          vietnameseText: 'Đây là mẹ của con',
        ),
        VocabularyTranslation(
          englishText: 'This is my father',
          vietnameseText: 'Đây là bố của con',
        ),
      ],
      'school': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'My school',
          vietnameseText: 'Trường của con',
        ),
        VocabularyTranslation(
          englishText: 'I go to school',
          vietnameseText: 'Con đi học',
        ),
        VocabularyTranslation(
          englishText: 'This is my classroom',
          vietnameseText: 'Đây là lớp học của con',
        ),
      ],
      'happy': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'I am happy',
          vietnameseText: 'Con vui',
        ),
        VocabularyTranslation(
          englishText: 'A happy day',
          vietnameseText: 'Một ngày vui',
        ),
        VocabularyTranslation(
          englishText: 'You make me happy',
          vietnameseText: 'Bạn làm con vui',
        ),
      ],
      'hello': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Hello, Mom',
          vietnameseText: 'Con chào mẹ',
        ),
        VocabularyTranslation(
          englishText: 'Hello, Dad',
          vietnameseText: 'Con chào bố',
        ),
        VocabularyTranslation(
          englishText: 'Hello, my friend',
          vietnameseText: 'Chào bạn của mình',
        ),
      ],
      'thank you': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Thank you, Mom',
          vietnameseText: 'Con cảm ơn mẹ',
        ),
        VocabularyTranslation(
          englishText: 'Thank you, Dad',
          vietnameseText: 'Con cảm ơn bố',
        ),
        VocabularyTranslation(
          englishText: 'Thank you for helping me',
          vietnameseText: 'Cảm ơn bạn đã giúp con',
        ),
      ],
    };
    return catalog[_normalizedVocabularyText(translated.englishText)] ??
        const <VocabularyTranslation>[];
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyPlaybackError(Object error) {
    if (error is PlatformException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }

  Future<void> _speakOnSelectedOutput(
    String text, {
    String locale = 'vi-VN',
    bool allowFixedPrompt = true,
  }) async {
    final generation = _playbackGeneration;
    if (!mounted || !_isEffectivelyActive) return;
    if (allowFixedPrompt &&
        locale.toLowerCase().startsWith('vi') &&
        await _fixedPromptAudioService.playPromptIfAvailable(text)) {
      return;
    }
    if (!mounted ||
        !_isEffectivelyActive ||
        generation != _playbackGeneration) {
      return;
    }
    final promptService = _voicePromptService;
    if (promptService is SelectedMediaOutputVoicePromptService) {
      await _mediaService.prepareSelectedLessonOutput();
      if (!mounted ||
          !_isEffectivelyActive ||
          generation != _playbackGeneration) {
        return;
      }
      await (promptService as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
      return;
    }
    await promptService.speakAndWait(text, locale: locale);
  }

  void _cancelPendingFixedPrompt() {
    final fixedPrompt = _fixedPromptAudioService;
    if (fixedPrompt is CancellableVocabularyFixedPromptAudioService) {
      (fixedPrompt as CancellableVocabularyFixedPromptAudioService)
          .cancelPending();
    }
  }

  Future<void> _speakVocabularyText(
    VocabularyEntry entry,
    String text, {
    required String locale,
  }) async {
    final audio = _vocabularyAudioService;
    if (entry.isParentAdded && audio != null) {
      await audio.speakAndWait(text, locale: locale);
      return;
    }
    final audioKey = VocabularyAudioKeys.builtInEntry(entry, locale);
    final prompt = _voicePromptService;
    if (audioKey != null &&
        prompt is KeyedSelectedMediaOutputVoicePromptService) {
      await (prompt as KeyedSelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutputWithAudioKey(
            audioKey,
            text,
            locale: locale,
          );
      return;
    }
    if (audioKey != null && prompt is KeyedVoicePromptService) {
      await (prompt as KeyedVoicePromptService).speakAndWaitWithAudioKey(
        audioKey,
        text,
        locale: locale,
      );
      return;
    }
    await _speakOnSelectedOutput(text, locale: locale, allowFixedPrompt: false);
  }

  Future<void> _releaseParentAudio(VocabularyEntry entry) async {
    final audio = _vocabularyAudioService;
    if (audio is! VocabularyAudioCacheMaintenance) return;
    await Future.wait<void>(
      <Future<void>>[
        (audio as VocabularyAudioCacheMaintenance).release(
          entry.word,
          locale: 'en-US',
        ),
        (audio as VocabularyAudioCacheMaintenance).release(
          entry.meaning,
          locale: 'vi-VN',
        ),
      ].map((operation) => operation.catchError((Object _) {})),
    );
  }

  Future<_VocabularyTranslationResolution> _translateVocabulary(
    String input,
  ) async {
    const pairs = <String, VocabularyTranslation>{
      'apple': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'quả táo': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'family': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'gia đình': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'school': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'trường học': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'happy': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'vui vẻ': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'hello': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'xin chào': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'thank you': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
      'cảm ơn': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
    };
    final normalized = input.toLowerCase();
    final known = pairs[normalized];
    if (known != null) {
      return _VocabularyTranslationResolution(primary: known);
    }

    if (!_containsVietnameseCharacters(input)) {
      final dictionary = widget.dictionaryProvider;
      if (dictionary != null) {
        try {
          final result = await dictionary.lookupEnglish(input);
          if (result != null && result.definitions.isNotEmpty) {
            final seenMeanings = <String>{};
            final meanings = result.definitions
                .map(
                  (definition) => VocabularyTranslation(
                    englishText: _capitalize(result.english),
                    vietnameseText: _capitalize(definition.vietnamese),
                  ),
                )
                .where(
                  (translation) => seenMeanings.add(
                    _normalizedVocabularyText(translation.vietnameseText),
                  ),
                )
                .take(2)
                .toList(growable: false);
            if (meanings.isNotEmpty) {
              return _VocabularyTranslationResolution(
                primary: meanings.first,
                alternatives: meanings.skip(1).toList(growable: false),
                partOfSpeech: result.definitions.first.partOfSpeech,
              );
            }
          }
        } catch (error) {
          debugPrint('VOCABULARY_DICTIONARY_LOOKUP_FAILED error=$error');
        }
      }
    }

    final translator = widget.translator;
    if (translator == null) {
      throw StateError('Không có dịch vụ dịch từ vựng.');
    }
    final translated = await translator(input);
    final englishText = _capitalize(translated.englishText.trim());
    final vietnameseText = _capitalize(
      translated.vietnameseText.trim().isEmpty
          ? input
          : translated.vietnameseText.trim(),
    );
    if (englishText.isEmpty || _containsVietnameseCharacters(englishText)) {
      throw StateError('Bản dịch tiếng Anh không hợp lệ.');
    }
    return _VocabularyTranslationResolution(
      primary: VocabularyTranslation(
        englishText: englishText,
        vietnameseText: vietnameseText,
      ),
    );
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  bool _containsVietnameseCharacters(String value) => RegExp(
    r'[ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]',
    caseSensitive: false,
  ).hasMatch(value);

  String _normalizedVocabularyText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[\s.,!?;:…_-]+"), ' ')
      .trim();
}

class _VocabularyTranslationResolution {
  const _VocabularyTranslationResolution({
    required this.primary,
    this.alternatives = const <VocabularyTranslation>[],
    this.partOfSpeech,
  });

  final VocabularyTranslation primary;
  final List<VocabularyTranslation> alternatives;
  final String? partOfSpeech;
}

enum _VocabularyJourney { family, stars, review }

class _JourneyDetailHeader extends StatelessWidget {
  const _JourneyDetailHeader({required this.title, required this.countLabel});

  final String title;
  final String? countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleFontSize = constraints.maxWidth <= 330 ? 22.0 : 24.0;

        return Container(
          key: const Key('vocabulary-journey-detail-header'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceStrong : AppColors.primaryNavy,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark ? AppColors.darkOutline : AppColors.primaryNavy,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.22)
                    : AppColors.deepNavy.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    title,
                    key: const Key('vocabulary-journey-title'),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: isDark ? AppColors.darkText : Colors.white,
                      fontSize: titleFontSize,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                    ),
                  ),
                ),
              ),
              if (countLabel != null) ...<Widget>[
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.center,
                  child: _buildCountChip(context),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCountChip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      key: const Key('vocabulary-journey-count-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkMint.withValues(alpha: 0.16)
            : AppColors.mintSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        countLabel!,
        maxLines: 1,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isDark ? AppColors.darkMint : AppColors.success,
          fontSize: 13,
          height: 1.15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _VocabularyHeader extends StatelessWidget {
  const _VocabularyHeader({
    required this.isReady,
    required this.onBrandPressed,
    required this.backTooltip,
    required this.onAddPressed,
    required this.adding,
    required this.showAddAction,
  });

  final bool isReady;
  final VoidCallback onBrandPressed;
  final String backTooltip;
  final VoidCallback? onAddPressed;
  final bool adding;
  final bool showAddAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = isDark ? colorScheme.primary : AppColors.deepNavy;
    final readyColor = isDark ? colorScheme.tertiary : AppColors.success;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 4),
          child: Row(
            children: <Widget>[
              KeyedSubtree(
                key: const Key('vocabulary-practice-button'),
                child: _VocabularyHeaderButton(
                  key: const Key('vocabulary-home-back-button'),
                  icon: Icons.arrow_back_rounded,
                  tooltip: backTooltip,
                  onPressed: onBrandPressed,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: null,
                  borderRadius: BorderRadius.circular(36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 56,
                          height: 56,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest
                                : Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? Theme.of(context).colorScheme.outline
                                  : Colors.white.withValues(alpha: 0.95),
                              width: 2.5,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x24142451),
                                blurRadius: 15,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Transform.scale(
                            scale: 1.14,
                            child: Image.asset(
                              _avatarAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'HOMI',
                                  maxLines: 1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: foreground,
                                        fontSize: 23,
                                        letterSpacing: -0.35,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isReady
                                          ? readyColor
                                          : AppColors.muted,
                                      shape: BoxShape.circle,
                                      boxShadow: isReady
                                          ? const <BoxShadow>[
                                              BoxShadow(
                                                color: Color(0x3323A05A),
                                                blurRadius: 5,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      isReady
                                          ? context.tr('Sẵn sàng', '已就绪')
                                          : context.tr('Chưa kết nối', '未连接'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: isReady
                                                ? readyColor
                                                : AppColors.muted,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (showAddAction) ...<Widget>[
                const SizedBox(width: 8),
                _VocabularyHeaderButton(
                  key: const Key('add-vocabulary-button'),
                  icon: Icons.add_rounded,
                  tooltip: context.tr('Thêm nội dung', '添加内容'),
                  onPressed: onAddPressed,
                  loading: adding,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VocabularyHeaderButton extends StatelessWidget {
  const _VocabularyHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Icon(icon, size: 30),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        maximumSize: const Size.square(48),
        backgroundColor: isDark
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.9),
        foregroundColor: isDark
            ? Theme.of(context).colorScheme.primary
            : AppColors.primaryNavy,
        side: BorderSide(
          color: isDark
              ? Theme.of(context).colorScheme.outline
              : AppColors.mintBorder,
          width: 1.4,
        ),
        elevation: 0,
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.height,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final double height;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.surface.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? theme.colorScheme.outlineVariant
                  : Colors.white.withValues(alpha: 0.95),
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.18)
                    : AppColors.deepNavy.withValues(alpha: 0.09),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Padding(padding: const EdgeInsets.only(right: 58), child: child),
              Positioned(
                right: 13,
                top: (height - 46) / 2,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.primary
                        : AppColors.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: isDark ? theme.colorScheme.onPrimary : Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCopy extends StatelessWidget {
  const _JourneyCopy({
    required this.title,
    required this.count,
    required this.countColor,
  });

  final String title;
  final String count;
  final Color countColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 8, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: isDark
                    ? theme.colorScheme.onSurface
                    : AppColors.deepNavy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            count,
            maxLines: 2,
            overflow: TextOverflow.fade,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? theme.colorScheme.secondary : countColor,
              fontSize: 15.5,
              height: 1.12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VocabularyRow extends StatelessWidget {
  const _VocabularyRow({
    required this.entry,
    required this.order,
    required this.canPlay,
    required this.isActive,
    required this.onPlay,
    this.statusLabel,
  });

  final VocabularyEntry entry;
  final int order;
  final bool canPlay;
  final bool isActive;
  final VoidCallback onPlay;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Semantics(
      selected: isActive,
      child: AnimatedContainer(
        key: ValueKey<String>('vocabulary-entry-highlight-${entry.id}'),
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : AppColors.mintSoft)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isActive
              ? Border.all(
                  color: isDark ? theme.colorScheme.primary : AppColors.indigo,
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: <Widget>[
            Semantics(
              label: context.tr('Mục số $order', '第 $order 项'),
              child: ExcludeSemantics(
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.surfaceContainerHighest
                        : AppColors.lavender,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$order',
                        key: ValueKey<String>('vocabulary-order-${entry.id}'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: isDark
                              ? theme.colorScheme.primary
                              : AppColors.indigo,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: statusLabel == null ? null : 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.meaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (statusLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.tertiaryContainer
                            : AppColors.mintSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? theme.colorScheme.onTertiaryContainer
                              : AppColors.success,
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    Text(
                      entry.isStar
                          ? '${context.tr('Ngôi sao', '星星')} • ${_dateLabel(context)}'
                          : _dateLabel(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey<String>('vocabulary-action-${entry.id}'),
              onPressed: canPlay ? onPlay : null,
              icon: const Icon(Icons.volume_up_rounded),
              tooltip: context.tr('Nghe phát âm', '播放发音'),
              color: isDark ? theme.colorScheme.primary : AppColors.indigo,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(44),
                backgroundColor: isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : AppColors.lavenderSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(BuildContext context) {
    final days = DateTime.now().difference(entry.addedAt).inDays;
    if (days <= 0) {
      return context.tr('Đã lưu hôm nay', '今天保存');
    }
    if (days == 1) {
      return context.tr('Đã lưu hôm qua', '昨天保存');
    }
    return context.tr('Đã lưu $days ngày trước', '$days 天前保存');
  }
}

class _VocabularySuggestionDialog extends StatefulWidget {
  const _VocabularySuggestionDialog({
    required this.options,
    required this.maxSelections,
  });

  final List<VocabularyTranslation> options;
  final int maxSelections;

  @override
  State<_VocabularySuggestionDialog> createState() =>
      _VocabularySuggestionDialogState();
}

class _VocabularySuggestionDialogState
    extends State<_VocabularySuggestionDialog> {
  final Set<int> _selectedIndexes = <int>{0};
  late final List<TextEditingController> _englishControllers;
  late final List<TextEditingController> _vietnameseControllers;
  late final List<FocusNode> _englishFocusNodes;
  late final List<FocusNode> _vietnameseFocusNodes;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _englishControllers = <TextEditingController>[
      for (final option in widget.options)
        TextEditingController(text: option.englishText),
    ];
    _vietnameseControllers = <TextEditingController>[
      for (final option in widget.options)
        TextEditingController(text: option.vietnameseText),
    ];
    _englishFocusNodes = <FocusNode>[
      for (var index = 0; index < widget.options.length; index++) FocusNode(),
    ];
    _vietnameseFocusNodes = <FocusNode>[
      for (var index = 0; index < widget.options.length; index++) FocusNode(),
    ];
    for (final controller in <TextEditingController>[
      ..._englishControllers,
      ..._vietnameseControllers,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      ..._englishControllers,
      ..._vietnameseControllers,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    for (final focusNode in <FocusNode>[
      ..._englishFocusNodes,
      ..._vietnameseFocusNodes,
    ]) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final maxSelections = widget.maxSelections.clamp(1, 3);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.vertical - 48;
    final maxDialogHeight = availableHeight.clamp(320.0, 720.0).toDouble();

    return Dialog(
      key: const Key('vocabulary-suggestion-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.playlist_add_check_circle_rounded,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr('Chọn nội dung phù hợp', '选择合适的内容'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('close-vocabulary-suggestions'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.tr('Đóng', '关闭'),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var index = 0; index < widget.options.length; index++)
                      if (_editingIndex == null || _editingIndex == index)
                        _buildSuggestionCard(context, index),
                    if (_editingIndex == null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('vocabulary-minhqnd-attribution'),
                          onPressed: () => unawaited(
                            launchUrl(
                              Uri.parse('https://dict.minhqnd.com/'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            alignment: Alignment.centerLeft,
                          ),
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            context.tr(
                              'Nguồn từ điển và phát âm: @minhqnd '
                                  '(CC BY-SA 4.0)',
                              '词典及发音来源：@minhqnd (CC BY-SA 4.0)',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(color: colorScheme.outlineVariant),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        context.tr(
                          '${_selectedIndexes.length}/$maxSelections đã chọn',
                          '已选 ${_selectedIndexes.length}/$maxSelections',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('Hủy', '取消')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('confirm-vocabulary-suggestions'),
                      onPressed: !_canSubmit || _editingIndex != null
                          ? null
                          : () => Navigator.of(context)
                                .pop(<VocabularyTranslation>[
                                  for (final index
                                      in _selectedIndexes.toList()..sort())
                                    VocabularyTranslation(
                                      englishText: _englishControllers[index]
                                          .text
                                          .trim(),
                                      vietnameseText:
                                          _vietnameseControllers[index].text
                                              .trim(),
                                    ),
                                ]),
                      icon: const Icon(Icons.add_task_rounded, size: 20),
                      label: Text(context.tr('Thêm', '添加')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = _selectedIndexes.contains(index);
    final isEditing = _editingIndex == index;
    return Container(
      key: ValueKey<String>('vocabulary-suggestion-$index'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Checkbox(
                key: ValueKey<String>('select-vocabulary-suggestion-$index'),
                value: selected,
                onChanged: isEditing
                    ? null
                    : (value) => _toggleSelection(index, value),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: isEditing
                      ? null
                      : () => _toggleSelection(index, !selected),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      context.tr('Gợi ý ${index + 1}', '建议 ${index + 1}'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isEditing)
                IconButton.filledTonal(
                  key: ValueKey<String>('edit-vocabulary-suggestion-$index'),
                  onPressed: () => _editSuggestion(index),
                  icon: const Icon(Icons.edit_rounded, size: 21),
                  tooltip: context.tr(
                    'Chỉnh sửa gợi ý ${index + 1}',
                    '编辑建议 ${index + 1}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            key: ValueKey<String>('vocabulary-suggestion-english-$index'),
            controller: _englishControllers[index],
            focusNode: _englishFocusNodes[index],
            readOnly: !isEditing,
            showCursor: isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: 2,
            onSubmitted: isEditing
                ? (_) => _vietnameseFocusNodes[index].requestFocus()
                : null,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: context.tr('Tiếng Anh', '英语'),
              prefixIcon: const Icon(Icons.translate_rounded, size: 21),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey<String>('vocabulary-suggestion-vietnamese-$index'),
            controller: _vietnameseControllers[index],
            focusNode: _vietnameseFocusNodes[index],
            readOnly: !isEditing,
            showCursor: isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            maxLines: 2,
            onSubmitted: isEditing ? (_) => _saveSuggestion(index) : null,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              labelText: context.tr('Tiếng Việt', '越南语'),
              prefixIcon: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 21,
              ),
            ),
          ),
          if (isEditing) ...<Widget>[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey<String>('save-vocabulary-suggestion-$index'),
                onPressed: _canSave(index)
                    ? () => _saveSuggestion(index)
                    : null,
                icon: const Icon(Icons.check_rounded, size: 21),
                label: Text(context.tr('Lưu chỉnh sửa', '保存修改')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canSubmit =>
      _selectedIndexes.isNotEmpty &&
      _selectedIndexes.every(
        (index) =>
            _englishControllers[index].text.trim().isNotEmpty &&
            _vietnameseControllers[index].text.trim().isNotEmpty,
      );

  void _toggleSelection(int index, bool? selected) {
    if (selected == true &&
        !_selectedIndexes.contains(index) &&
        _selectedIndexes.length >= widget.maxSelections.clamp(1, 3)) {
      return;
    }
    setState(() {
      if (selected == true) {
        _selectedIndexes.add(index);
      } else {
        _selectedIndexes.remove(index);
      }
    });
  }

  void _editSuggestion(int index) {
    setState(() => _editingIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _englishFocusNodes[index].requestFocus();
    });
  }

  bool _canSave(int index) =>
      _englishControllers[index].text.trim().isNotEmpty &&
      _vietnameseControllers[index].text.trim().isNotEmpty;

  void _saveSuggestion(int index) {
    if (!_canSave(index)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      final maxSelections = widget.maxSelections.clamp(1, 3);
      if (!_selectedIndexes.contains(index) &&
          _selectedIndexes.length >= maxSelections) {
        _selectedIndexes.remove(_selectedIndexes.first);
      }
      _selectedIndexes.add(index);
      _editingIndex = null;
    });
  }

  void _refresh() => setState(() {});
}

class _AddVocabularyDialog extends StatefulWidget {
  const _AddVocabularyDialog();

  @override
  State<_AddVocabularyDialog> createState() => _AddVocabularyDialogState();
}

class _AddVocabularyDialogState extends State<_AddVocabularyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  context.tr('Thêm nội dung học', '添加学习内容'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 23,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('add-vocabulary-field'),
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: context.tr(
                    'Nhập từ, cụm từ hoặc câu ngắn',
                    '输入单词、短语或短句',
                  ),
                  filled: true,
                  fillColor: isDark
                      ? theme.colorScheme.surfaceContainer
                      : AppColors.lavenderSoft,
                  hintStyle: const TextStyle(fontSize: 15),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.outline
                          : AppColors.indigo,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.secondary
                          : AppColors.indigo,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Có thể nhập bằng tiếng Anh hoặc tiếng Việt.',
                  '可以输入英文或越南文。',
                ),
                maxLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Hủy', '取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('confirm-add-vocabulary'),
                    onPressed: enabled
                        ? () => Navigator.of(context).pop(_controller.text)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.tr('Thêm', '添加')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 46),
                      backgroundColor: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigo,
                      foregroundColor: isDark
                          ? theme.colorScheme.onPrimary
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh() => setState(() {});
}

class _EditVocabularyDialog extends StatefulWidget {
  const _EditVocabularyDialog({required this.entry});

  final VocabularyEntry entry;

  @override
  State<_EditVocabularyDialog> createState() => _EditVocabularyDialogState();
}

class _EditVocabularyDialogState extends State<_EditVocabularyDialog> {
  late final TextEditingController _englishController;
  late final TextEditingController _vietnameseController;

  @override
  void initState() {
    super.initState();
    _englishController = TextEditingController(text: widget.entry.word)
      ..addListener(_refresh);
    _vietnameseController = TextEditingController(text: widget.entry.meaning)
      ..addListener(_refresh);
  }

  @override
  void dispose() {
    _englishController
      ..removeListener(_refresh)
      ..dispose();
    _vietnameseController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled =
        _englishController.text.trim().isNotEmpty &&
        _vietnameseController.text.trim().isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  context.tr('Sửa nội dung', '编辑内容'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 23,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  context.tr(
                    'Có thể nhập bằng tiếng Anh hoặc tiếng Việt.',
                    '可以输入英文或越南文。',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _EditVocabularyField(
                fieldKey: const Key('edit-vocabulary-english-field'),
                controller: _englishController,
                label: context.tr('Tiếng Anh', '英文'),
                hint: context.tr('Nhập nội dung tiếng Anh', '输入英文内容'),
                autofocus: true,
                textInputAction: TextInputAction.next,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _EditVocabularyField(
                fieldKey: const Key('edit-vocabulary-vietnamese-field'),
                controller: _vietnameseController,
                label: context.tr('Tiếng Việt', '越南文'),
                hint: context.tr('Nhập nghĩa tiếng Việt', '输入越南文释义'),
                textInputAction: TextInputAction.done,
                isDark: isDark,
                onSubmitted: enabled ? (_) => _save() : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr(
                        'Chỉnh đúng cả hai phần trước khi lưu.',
                        '保存前请确认两种语言的内容。',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Hủy', '取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('confirm-edit-vocabulary'),
                    onPressed: enabled ? _save : null,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(context.tr('Lưu', '保存')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 46),
                      backgroundColor: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigo,
                      foregroundColor: isDark
                          ? theme.colorScheme.onPrimary
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(
      VocabularyTranslation(
        englishText: _englishController.text.trim(),
        vietnameseText: _vietnameseController.text.trim(),
      ),
    );
  }

  void _refresh() => setState(() {});
}

class _EditVocabularyField extends StatelessWidget {
  const _EditVocabularyField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    required this.textInputAction,
    required this.isDark,
    this.autofocus = false,
    this.onSubmitted,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputAction textInputAction;
  final bool isDark;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          minLines: 1,
          maxLines: 3,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: isDark
                ? theme.colorScheme.surfaceContainer
                : AppColors.lavenderSoft,
            hintStyle: const TextStyle(fontSize: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: isDark ? theme.colorScheme.outline : AppColors.indigo,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: isDark ? theme.colorScheme.secondary : AppColors.indigo,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }
}
