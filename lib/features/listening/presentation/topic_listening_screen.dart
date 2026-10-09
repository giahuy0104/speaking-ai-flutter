import 'dart:async';
import '../../../core/audio/audio_diagnostics.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../l10n/display_language.dart';
import '../../../app/homi_bottom_navigation.dart';
import '../../../core/navigation/active_learning_navigation.dart';
import '../application/lesson_media_service.dart';
import '../application/listening_voice_navigation_target.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../domain/listening_audio_keys.dart';
import '../domain/listening_curriculum_flow.dart';
import '../domain/v4_completion_flow.dart';
import '../../voice_navigation/domain/main_assistant_audio_keys.dart';
import 'lesson_recording_history_sheet.dart';
import 'listening_route_names.dart';
import 'topic_lesson_list_screen.dart';

typedef TopicLessonSelectionPrompt =
    Future<void> Function({
      required int childAge,
      required int topicNumber,
      required ListeningTopicContent topicContent,
      required List<int> completedLessonNumbers,
    });

/// Returns true only when the assistant has opened the topic response turn.
typedef TopicSelectionPrompt =
    Future<bool> Function({
      required int childAge,
      required List<int> topicNumbers,
      required List<int> completedTopicNumbers,
    });

typedef CourseRelearnTopicSelectionPrompt =
    Future<bool> Function({
      required int childAge,
      required List<int> topicNumbers,
    });

class TopicListeningScreen extends StatefulWidget {
  const TopicListeningScreen({
    required this.language,
    required this.childAge,
    this.controller,
    this.onMainPressed,
    this.onVocabularyRequested,
    this.onVoiceNavigationPause,
    this.onVoiceNavigationResume,
    this.initialVoiceTarget,
    this.initialVoiceActivationGate,
    this.onTopicSelected,
    this.onLessonSelectionRequested,
    this.onTopicSelectionRequested,
    this.iosTopicRecognitionFailureRevision,
    this.onCourseRelearnTopicSelectionRequested,
    this.onChildAgeChanged,
    this.onRequestParentAccess,
    this.onCommunicationRequested,
    this.contentFuture,
    this.progressStore = const ListeningProgressStore(),
    this.mediaService,
    this.voicePromptService,
    super.key,
  });

  final DisplayLanguage language;
  final int childAge;
  final LearningAudioDependencies? controller;
  final Future<void> Function()? onMainPressed;
  final VoidCallback? onVocabularyRequested;
  final Future<void> Function()? onVoiceNavigationPause;
  final VoidCallback? onVoiceNavigationResume;
  final ListeningVoiceNavigationTarget? initialVoiceTarget;

  /// Keeps the catalog visible while an earlier MAIN response owns the audio.
  final Future<void>? initialVoiceActivationGate;
  final ValueChanged<int>? onTopicSelected;
  final TopicLessonSelectionPrompt? onLessonSelectionRequested;
  final TopicSelectionPrompt? onTopicSelectionRequested;

  /// Incremented when an activated iOS topic response turn fails recognition.
  final ValueListenable<int>? iosTopicRecognitionFailureRevision;
  final CourseRelearnTopicSelectionPrompt?
  onCourseRelearnTopicSelectionRequested;
  final ValueChanged<int>? onChildAgeChanged;
  final Future<bool> Function()? onRequestParentAccess;
  final VoidCallback? onCommunicationRequested;
  final Future<ListeningContentCatalog>? contentFuture;
  final ListeningProgressStore progressStore;
  final LessonMediaService? mediaService;
  final VoicePromptService? voicePromptService;

  @override
  State<TopicListeningScreen> createState() => _TopicListeningScreenState();
}

class _TopicListeningScreenState extends State<TopicListeningScreen> {
  static const double _contentMaxWidth = 760;

  late int _selectedCatalogIndex;
  late final Future<ListeningContentCatalog> _contentFuture;
  ListeningContentCatalog? _contentCatalog;
  Map<String, int> _lessonProgress = const <String, int>{};
  Set<String> _completedV4LessonActivities = const <String>{};
  Set<String> _startedLessonIds = const <String>{};
  late final LessonMediaService _historyMediaService;
  late final bool _ownsHistoryMediaService;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  bool _initialVoiceTargetHandled = false;
  ListeningContentAgeGroup? _activeVoiceTopicGroup;
  bool _activeVoiceTopicRelearn = false;
  int? _activeVoiceTopicRevision;
  bool _topicChoiceSheetOpen = false;

  ListeningAgeCatalog get _catalog => listeningCatalogs[_selectedCatalogIndex];

  @override
  void initState() {
    super.initState();
    final requestedAge = widget.initialVoiceTarget?.childAge ?? widget.childAge;
    AudioDiagnostics.event('screen.topics.init');
    if (AudioDiagnostics.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AudioDiagnostics.event('screen.topics.first_frame');
      });
    }
    _selectedCatalogIndex = listeningCatalogs.indexWhere(
      (catalog) =>
          requestedAge >= catalog.startAge && requestedAge <= catalog.endAge,
    );
    if (_selectedCatalogIndex < 0) {
      _selectedCatalogIndex = listeningCatalogs.lastIndexWhere(
        (catalog) => requestedAge >= catalog.startAge,
      );
      if (_selectedCatalogIndex < 0) {
        _selectedCatalogIndex = 0;
      }
    }
    _contentFuture =
        widget.contentFuture ?? AssetListeningContentRepository().load();
    _ownsHistoryMediaService = widget.mediaService == null;
    _historyMediaService =
        widget.mediaService ??
        LessonMediaService(
          hfpAudioControl: widget.controller?.createLearningAudioRouteControl(),
          audioTurnCoordinator: widget.controller?.audioTurnCoordinator,
        );
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ??
        createVoicePromptService(
          coordinator: widget.controller?.audioTurnCoordinator,
          owner: AudioTurnOwner.listeningLesson,
        );
    widget.iosTopicRecognitionFailureRevision?.addListener(
      _onIosTopicRecognitionFailure,
    );
    unawaited(_loadContentAndProgress());
  }

  @override
  void didUpdateWidget(covariant TopicListeningScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iosTopicRecognitionFailureRevision !=
        widget.iosTopicRecognitionFailureRevision) {
      oldWidget.iosTopicRecognitionFailureRevision?.removeListener(
        _onIosTopicRecognitionFailure,
      );
      _activeVoiceTopicGroup = null;
      _activeVoiceTopicRevision = null;
      widget.iosTopicRecognitionFailureRevision?.addListener(
        _onIosTopicRecognitionFailure,
      );
    }
  }

  @override
  void dispose() {
    widget.iosTopicRecognitionFailureRevision?.removeListener(
      _onIosTopicRecognitionFailure,
    );
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    }
    if (_ownsHistoryMediaService) {
      unawaited(_historyMediaService.dispose());
    }
    super.dispose();
  }

  void _onIosTopicRecognitionFailure() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || !mounted) {
      return;
    }
    final revision = widget.iosTopicRecognitionFailureRevision?.value;
    final group = _activeVoiceTopicGroup;
    if (revision == null ||
        group == null ||
        _activeVoiceTopicRevision == null ||
        revision <= _activeVoiceTopicRevision! ||
        _topicChoiceSheetOpen) {
      return;
    }
    _activeVoiceTopicRevision = revision;
    if (ModalRoute.of(context)?.isCurrent != true) {
      _activeVoiceTopicGroup = null;
      return;
    }
    AudioDiagnostics.event('screen.topics.ios_recognition_fallback');
    unawaited(_showTopicChoices(group, relearn: _activeVoiceTopicRelearn));
  }

  Future<void> _speakOnSelectedLessonOutput(
    String text, {
    String locale = 'vi-VN',
    String? audioKey,
  }) async {
    final prompt = _voicePromptService;
    if (!kIsWeb && prompt is SelectedMediaOutputVoicePromptService) {
      await _historyMediaService.prepareSelectedLessonOutput();
      if (!mounted) return;
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
      await (prompt as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
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
    await prompt.speakAndWait(text, locale: locale);
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          imageAlignment: Alignment.topCenter,
          overlayOpacity: 0.36,
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              key: const Key('topic-listening-screen'),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _buildHeader(context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _CurrentLessonGroupCard(
                      catalog: _catalog,
                      canChange:
                          widget.onChildAgeChanged != null &&
                          widget.onRequestParentAccess != null,
                      onChange: _changeLessonGroup,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Text(
                            context.tr('Hành trình của bạn', '孩子的学习旅程'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          flex: 2,
                          child: Text(
                            context.tr(
                              '${_catalog.topics.length} chủ đề',
                              '${_catalog.topics.length} 个主题',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : AppColors.ink.withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w700,
                                  shadows: _journeyTextShadowsFor(context),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 30),
                    child: _TopicJourney(
                      catalogId: _catalog.id,
                      topics: _catalog.topics,
                      englishTitleFor: _topicEnglishTitle,
                      progressFor: _topicProgress,
                      hasSongsFor: _topicHasSongs,
                      onTopicPressed: _openTopic,
                      onSongsPressed: _openTopicSongs,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: KeyedSubtree(
          key: const Key('listening-bottom-navigation'),
          child: HomiBottomNavigation(
            selectedIndex: 1,
            onConversation: () => Navigator.of(context).pop(),
            onTopics: () {},
            onMain: widget.onMainPressed == null
                ? null
                : () => unawaited(widget.onMainPressed!()),
            onVocabulary: _openVocabulary,
            onHistory: _showHistory,
            conversationKey: const Key('listening-conversation-tab'),
            topicsKey: const Key('listening-topics-tab'),
            mainKey: const Key('listening-main-button'),
            vocabularyKey: const Key('listening-vocabulary-tab'),
            historyKey: const Key('listening-history-tab'),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        IconButton.filled(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: context.tr('Quay lại', '返回'),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(52),
            backgroundColor: isDark
                ? colorScheme.surfaceContainerHighest
                : const Color(0xF8FFFDF9),
            foregroundColor: isDark ? colorScheme.primary : AppColors.ink,
            elevation: 3,
            shadowColor: const Color(0x24142451),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.tr('Chủ đề', '主题'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: isDark ? colorScheme.onSurface : AppColors.indigoDark,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest
                : const Color(0xF8FFFDF9),
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            MascotAssets.avatar,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    );
  }

  void _showHistory() => unawaited(_openHistory());

  void _openVocabulary() {
    Navigator.of(context).pop();
    widget.onVocabularyRequested?.call();
  }

  Future<void> _changeLessonGroup() async {
    final requestParentAccess = widget.onRequestParentAccess;
    final onChildAgeChanged = widget.onChildAgeChanged;
    if (requestParentAccess == null || onChildAgeChanged == null) {
      return;
    }

    await widget.onVoiceNavigationPause?.call();
    try {
      if (!await requestParentAccess() || !mounted) {
        return;
      }
      final selectedIndex = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.deepNavy.withValues(alpha: 0.48),
        elevation: 0,
        builder: (_) => _LessonGroupPickerSheet(
          catalogs: listeningCatalogs,
          selectedIndex: _selectedCatalogIndex,
        ),
      );
      if (selectedIndex == null ||
          selectedIndex == _selectedCatalogIndex ||
          !mounted) {
        return;
      }
      final selectedCatalog = listeningCatalogs[selectedIndex];
      setState(() => _selectedCatalogIndex = selectedIndex);
      onChildAgeChanged(selectedCatalog.startAge);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Đã đổi sang nhóm ${selectedCatalog.startAge}–${selectedCatalog.endAge} tuổi.',
              '已切换到 ${selectedCatalog.startAge}–${selectedCatalog.endAge} 岁课程组。',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
  }

  Future<void> _openHistory() async {
    await widget.onVoiceNavigationPause?.call();
    try {
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            LessonRecordingHistorySheet(mediaService: _historyMediaService),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
  }

  Future<void> _loadContentAndProgress() async {
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      final progress = await _readProgressSnapshot(catalog);
      if (!mounted) {
        return;
      }
      setState(() {
        _contentCatalog = catalog;
        _lessonProgress = progress.lessonProgress;
        _completedV4LessonActivities = progress.completedV4LessonActivities;
        _startedLessonIds = progress.startedLessonIds;
      });
      await widget.initialVoiceActivationGate;
      if (!mounted) return;
      if (widget.initialVoiceActivationGate != null &&
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final courseId = '${_catalog.startAge}-${_catalog.endAge}';
      final courseCompleted = await widget.progressStore.isCourseCompleted(
        courseId,
      );
      if (!mounted) return;
      if (courseCompleted && widget.initialVoiceTarget == null) {
        final group = catalog.groups.firstWhere(
          (candidate) =>
              candidate.startAge == _catalog.startAge &&
              candidate.endAge == _catalog.endAge,
        );
        unawaited(_startCourseRelearnTopicSelection(group));
      } else if (widget.initialVoiceTarget != null) {
        unawaited(_openInitialVoiceTarget());
      } else {
        unawaited(_resumeTopicSelectionIfNeeded(catalog));
      }
    } catch (error, stackTrace) {
      debugPrint(
        'HOMI topic content/progress load failed: $error\n$stackTrace',
      );
      // The topic catalog remains usable while lesson content is unavailable.
    }
  }

  Future<_ListeningProgressSnapshot> _readProgressSnapshot(
    ListeningContentCatalog catalog,
  ) async {
    // Start the independent persistence reads together. Native path lookup may
    // be comparatively slow during app resume, and topic navigation should not
    // wait for the same progress file several times in sequence.
    final lessonProgressFuture = widget.progressStore.readAll();
    final completedActivitiesFuture = widget.progressStore
        .readCompletedV4LessonActivities();
    final startedLessonsFuture = widget.progressStore.readStartedLessonCores();
    final lessonProgress = await lessonProgressFuture;
    final completedV4LessonActivities = await completedActivitiesFuture;
    final startedLessonIds = await startedLessonsFuture;
    return _ListeningProgressSnapshot(
      lessonProgress: lessonProgress,
      completedV4LessonActivities: completedV4LessonActivities,
      startedLessonIds: startedLessonIds,
    );
  }

  Future<_ListeningProgressSnapshot> _reloadProgress() async {
    final progress = await _readProgressSnapshot(await _contentFuture);
    if (!mounted) {
      return progress;
    }
    setState(() {
      _lessonProgress = progress.lessonProgress;
      _completedV4LessonActivities = progress.completedV4LessonActivities;
      _startedLessonIds = progress.startedLessonIds;
    });
    return progress;
  }

  _TopicProgress _topicProgress(int topicIndex) {
    try {
      final content = _contentCatalog?.topic(
        startAge: _catalog.startAge,
        endAge: _catalog.endAge,
        topicNumber: topicIndex + 1,
      );
      if (content == null || content.lessons.isEmpty) {
        final topic = _catalog.topics[topicIndex];
        return _TopicProgress(
          completed: topic.completed.clamp(0, topic.total),
          total: topic.total,
        );
      }
      final completed = content.lessons
          .where(
            (lesson) => _isLessonCompleted(
              lesson,
              _lessonProgress,
              _completedV4LessonActivities,
            ),
          )
          .length;
      return _TopicProgress(
        completed: completed,
        total: content.lessons.length,
      );
    } catch (_) {
      final topic = _catalog.topics[topicIndex];
      return _TopicProgress(
        completed: topic.completed.clamp(0, topic.total),
        total: topic.total,
      );
    }
  }

  String _topicEnglishTitle(int topicIndex) {
    try {
      return _contentCatalog
              ?.topic(
                startAge: _catalog.startAge,
                endAge: _catalog.endAge,
                topicNumber: topicIndex + 1,
              )
              .titleEn ??
          '';
    } catch (_) {
      return '';
    }
  }

  bool _topicHasSongs(int topicIndex) {
    try {
      return _contentCatalog
              ?.topic(
                startAge: _catalog.startAge,
                endAge: _catalog.endAge,
                topicNumber: topicIndex + 1,
              )
              .availableSongsForAge(_catalog.startAge)
              .isNotEmpty ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _resumeTopicSelectionIfNeeded(
    ListeningContentCatalog catalog,
  ) async {
    if (!mounted || widget.initialVoiceTarget != null) return;
    final group = catalog.groups.firstWhere(
      (candidate) =>
          candidate.startAge == _catalog.startAge &&
          candidate.endAge == _catalog.endAge,
    );
    await _startTopicSelection(group);
  }

  Future<void> _startCourseRelearnTopicSelection(
    ListeningContentAgeGroup group,
  ) async {
    await _startTopicSelection(group, relearn: true);
  }

  Future<void> _startTopicSelection(
    ListeningContentAgeGroup group, {
    bool relearn = false,
  }) async {
    _activeVoiceTopicGroup = null;
    _activeVoiceTopicRevision = null;
    final topicNumbers = group.topics.map((topic) => topic.number).toList();
    if (topicNumbers.isEmpty || !mounted) return;
    await widget.progressStore.saveTopicSelectionCheckpoint(
      '${_catalog.startAge}-${_catalog.endAge}',
    );
    if (!mounted) return;
    final completedTopics = group.topics
        .where(
          (topic) =>
              ListeningCurriculumFlow.topicState(
                topic,
                _lessonProgress,
                _completedV4LessonActivities,
                startedLessonIds: _startedLessonIds,
              ) ==
              ListeningTopicLearningState.completed,
        )
        .map((topic) => topic.number)
        .toList(growable: false);
    final revisionBeforeActivation =
        widget.iosTopicRecognitionFailureRevision?.value;
    var activated = false;
    try {
      if (relearn) {
        activated =
            await widget.onCourseRelearnTopicSelectionRequested?.call(
              childAge: _catalog.startAge,
              topicNumbers: topicNumbers,
            ) ??
            false;
      } else {
        activated =
            await widget.onTopicSelectionRequested?.call(
              childAge: _catalog.startAge,
              topicNumbers: topicNumbers,
              completedTopicNumbers: completedTopics,
            ) ??
            false;
      }
    } catch (error) {
      debugPrint('HOMI topic selection activation failed: $error');
    }
    if (!mounted) return;
    if (activated) {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          revisionBeforeActivation != null) {
        _activeVoiceTopicGroup = group;
        _activeVoiceTopicRelearn = relearn;
        _activeVoiceTopicRevision = revisionBeforeActivation;
        _onIosTopicRecognitionFailure();
      }
      return;
    }
    try {
      await _speakOnSelectedLessonOutput(
        relearn
            ? v4CompletionPrompt(V4CompletionStage.courseRelearnTopic)
            : 'Có ${topicNumbers.length} Chủ đề. Bạn chọn Chủ đề số mấy?',
        audioKey: relearn
            ? MainAssistantAudioKeys.courseRelearnTopic
            : MainAssistantAudioKeys.chooseTopic(topicNumbers.length),
      );
    } catch (error) {
      debugPrint('HOMI topic selection prompt failed: $error');
    }
    if (!mounted) return;
    if (relearn || widget.onTopicSelectionRequested != null) {
      await _showTopicChoices(group, relearn: relearn);
    }
  }

  Future<void> _showTopicChoices(
    ListeningContentAgeGroup group, {
    bool relearn = false,
  }) async {
    if (!mounted || _topicChoiceSheetOpen) return;
    _topicChoiceSheetOpen = true;
    try {
      final selected = await showModalBottomSheet<int>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    relearn
                        ? v4CompletionPrompt(
                            V4CompletionStage.courseRelearnTopic,
                          )
                        : context.tr('Bạn chọn Chủ đề số mấy?', '请选择主题编号。'),
                    textAlign: TextAlign.center,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  for (final topic in group.topics) ...<Widget>[
                    const SizedBox(height: 10),
                    FilledButton(
                      key: ValueKey<String>(
                        relearn
                            ? 'course-relearn-topic-${topic.number}'
                            : 'topic-choice-${topic.number}',
                      ),
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(topic.number),
                      child: Text(
                        relearn
                            ? 'Học lại Chủ đề ${topic.number}'
                            : context.tr(
                                'Chủ đề ${topic.number}',
                                '主题 ${topic.number}',
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      _activeVoiceTopicGroup = null;
      _activeVoiceTopicRevision = null;
      final topicIndex = selected - 1;
      if (topicIndex < 0 || topicIndex >= _catalog.topics.length) return;
      await _openTopic(
        _catalog.topics[topicIndex],
        topicIndex,
        requestVoiceLessonSelection: false,
        forceRelearnTopic: relearn,
      );
    } finally {
      _topicChoiceSheetOpen = false;
    }
  }

  Future<void> _openInitialVoiceTarget() async {
    final target = widget.initialVoiceTarget;
    if (_initialVoiceTargetHandled || target == null || !mounted) {
      return;
    }
    _initialVoiceTargetHandled = true;
    final topicIndex = target.resolveTopicIndex(_catalog);
    if (topicIndex == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await _openTopic(
      _catalog.topics[topicIndex],
      topicIndex,
      initialLessonNumber: target.openLesson
          ? target.resolvedLessonNumber
          : null,
      requestVoiceLessonSelection: false,
      forceRelearnTopic: target.relearnTopic,
      forceRelearnLesson: target.relearnLesson,
    );
  }

  Future<void> _openTopicSongs(ListeningTopic topic, int topicIndex) async {
    _activeVoiceTopicGroup = null;
    _activeVoiceTopicRevision = null;
    try {
      final catalog = await _contentFuture;
      if (!mounted) return;
      final selectedAgeCatalog = _catalog;
      final content = catalog.topic(
        startAge: selectedAgeCatalog.startAge,
        endAge: selectedAgeCatalog.endAge,
        topicNumber: topicIndex + 1,
      );
      if (content.availableSongsForAge(selectedAgeCatalog.startAge).isEmpty) {
        return;
      }
      final contentGroup = catalog.groups.firstWhere(
        (group) =>
            group.startAge == selectedAgeCatalog.startAge &&
            group.endAge == selectedAgeCatalog.endAge,
      );
      if (!mounted) return;
      widget.onTopicSelected?.call(topicIndex);
      var topicCompletedDuringVisit = false;
      await pushForActiveLearning<void>(
        context,
        (_) => TopicLessonListScreen(
          language: widget.language,
          startAge: selectedAgeCatalog.startAge,
          endAge: selectedAgeCatalog.endAge,
          topic: topic,
          content: content,
          contentGroup: contentGroup,
          controller: widget.controller,
          onMainPressed: widget.onMainPressed,
          onVocabularyRequested: widget.onVocabularyRequested,
          onVoiceNavigationPause: widget.onVoiceNavigationPause,
          onVoiceNavigationResume: widget.onVoiceNavigationResume,
          progressStore: widget.progressStore,
          voicePromptService: _voicePromptService,
          songsOnly: true,
          onTopicCompleted: () => topicCompletedDuringVisit = true,
          onCommunicationRequested: widget.onCommunicationRequested,
        ),
        settings: const RouteSettings(name: ListeningRouteNames.topicLessons),
      );
      await _reloadProgress();
      if (topicCompletedDuringVisit && mounted) {
        await _startTopicSelection(
          contentGroup,
          relearn: await widget.progressStore.isCourseCompleted(
            '${selectedAgeCatalog.startAge}-${selectedAgeCatalog.endAge}',
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa tải được nội dung bài hát. Vui lòng thử lại.',
              '暂时无法加载歌曲内容，请重试。',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openTopic(
    ListeningTopic topic,
    int topicIndex, {
    int? initialLessonNumber,
    bool requestVoiceLessonSelection = true,
    bool forceRelearnTopic = false,
    bool forceRelearnLesson = false,
  }) async {
    _activeVoiceTopicGroup = null;
    _activeVoiceTopicRevision = null;
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      widget.onTopicSelected?.call(topicIndex);
      final selectedAgeCatalog = _catalog;
      final content = catalog.topic(
        startAge: selectedAgeCatalog.startAge,
        endAge: selectedAgeCatalog.endAge,
        topicNumber: topicIndex + 1,
      );
      final contentGroup = catalog.groups.firstWhere(
        (group) =>
            group.startAge == selectedAgeCatalog.startAge &&
            group.endAge == selectedAgeCatalog.endAge,
      );
      final progressBefore = _ListeningProgressSnapshot(
        lessonProgress: _lessonProgress,
        completedV4LessonActivities: _completedV4LessonActivities,
        startedLessonIds: _startedLessonIds,
      );
      final state = ListeningCurriculumFlow.topicState(
        content,
        progressBefore.lessonProgress,
        progressBefore.completedV4LessonActivities,
        startedLessonIds: progressBefore.startedLessonIds,
      );
      var lessonNumber = initialLessonNumber;
      var relearnTopicSequence = forceRelearnTopic;
      Future<void>? resumePrompt;
      if (forceRelearnTopic) {
        await widget.progressStore.resetLessonsForRelearn(
          content.lessons.map((lesson) => lesson.id),
        );
        lessonNumber = content.lessons.first.number;
      } else if (lessonNumber == null) {
        if (state == ListeningTopicLearningState.completed) {
          final relearn = await _askCompletedTopicAction(content.number);
          if (relearn == null) return;
          if (!relearn) {
            await _startTopicSelection(contentGroup);
            return;
          }
          await widget.progressStore.resetLessonsForRelearn(
            content.lessons.map((lesson) => lesson.id),
          );
          lessonNumber = content.lessons.first.number;
          relearnTopicSequence = true;
        } else {
          final firstIncomplete = ListeningCurriculumFlow.firstIncompleteLesson(
            content,
            progressBefore.lessonProgress,
            progressBefore.completedV4LessonActivities,
          );
          lessonNumber =
              firstIncomplete?.number ?? content.lessons.first.number;
          if (state == ListeningTopicLearningState.inProgress) {
            // Open the lesson while this line plays; the lesson intro waits
            // for it, so the two prompts never overlap.
            resumePrompt =
                _speakOnSelectedLessonOutput(
                  'Mình học tiếp Chủ đề ${content.number} nhé.',
                  audioKey: ListeningAudioKeys.topicResume(content.number),
                ).catchError((Object error) {
                  debugPrint('HOMI topic resume prompt failed: $error');
                });
          }
        }
      }
      await widget.progressStore.clearTopicSelectionCheckpoint(
        '${_catalog.startAge}-${_catalog.endAge}',
      );
      if (!mounted) return;
      var topicCompletedDuringVisit = false;
      final route = pushForActiveLearning<void>(
        context,
        (_) => TopicLessonListScreen(
          language: widget.language,
          startAge: selectedAgeCatalog.startAge,
          endAge: selectedAgeCatalog.endAge,
          topic: topic,
          content: content,
          contentGroup: contentGroup,
          controller: widget.controller,
          onMainPressed: widget.onMainPressed,
          onVocabularyRequested: widget.onVocabularyRequested,
          onVoiceNavigationPause: widget.onVoiceNavigationPause,
          onVoiceNavigationResume: widget.onVoiceNavigationResume,
          progressStore: widget.progressStore,
          voicePromptService: _voicePromptService,
          initialLessonNumber: lessonNumber,
          initialLessonLeadPrompt: resumePrompt,
          relearnInitialLesson: forceRelearnLesson || relearnTopicSequence,
          relearnTopicSequence: relearnTopicSequence,
          onTopicCompleted: () => topicCompletedDuringVisit = true,
          onCommunicationRequested: widget.onCommunicationRequested,
        ),
        settings: const RouteSettings(name: ListeningRouteNames.topicLessons),
      );
      await route;
      await _reloadProgress();
      final checkpoint = await widget.progressStore
          .readTopicSelectionCheckpoint(
            '${selectedAgeCatalog.startAge}-${selectedAgeCatalog.endAge}',
          );
      if ((checkpoint != null || topicCompletedDuringVisit) && mounted) {
        await _startTopicSelection(
          contentGroup,
          relearn: await widget.progressStore.isCourseCompleted(
            '${selectedAgeCatalog.startAge}-${selectedAgeCatalog.endAge}',
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa tải được nội dung bài học. Vui lòng thử lại.',
              '暂时无法加载课程内容，请重试。',
            ),
          ),
        ),
      );
    }
  }

  Future<bool?> _askCompletedTopicAction(int topicNumber) async {
    final message =
        'Chủ đề $topicNumber bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề $topicNumber?';
    await _speakOnSelectedLessonOutput(
      message,
      audioKey: MainAssistantAudioKeys.replayTopic(topicNumber),
    );
    if (!mounted) return null;
    return showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: const Text('Chủ đề khác'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('Học lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isLessonCompleted(
    ListeningLessonContent lesson,
    Map<String, int> progress,
    Set<String> completedV4LessonActivities,
  ) {
    final completedCore = (progress[lesson.id] ?? 0) >= lesson.sentences.length;
    return completedCore &&
        (!lesson.usesV4Flow || completedV4LessonActivities.contains(lesson.id));
  }
}

class _ListeningProgressSnapshot {
  const _ListeningProgressSnapshot({
    required this.lessonProgress,
    required this.completedV4LessonActivities,
    required this.startedLessonIds,
  });

  final Map<String, int> lessonProgress;
  final Set<String> completedV4LessonActivities;
  final Set<String> startedLessonIds;
}

class _CenteredSection extends StatelessWidget {
  const _CenteredSection({
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _CurrentLessonGroupCard extends StatelessWidget {
  const _CurrentLessonGroupCard({
    required this.catalog,
    required this.canChange,
    required this.onChange,
  });

  final ListeningAgeCatalog catalog;
  final bool canChange;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: const Key('current-lesson-group-card'),
      color: isDark
          ? colorScheme.surface.withValues(alpha: 0.96)
          : Colors.white.withValues(alpha: 0.96),
      elevation: isDark ? 0 : 4,
      shadowColor: AppColors.mint.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.7)
              : AppColors.mintBorder,
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.tertiaryContainer
                    : AppColors.mintSoft,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? colorScheme.tertiary.withValues(alpha: 0.45)
                      : AppColors.mintBorder,
                ),
              ),
              child: Icon(
                Icons.school_rounded,
                color: isDark ? colorScheme.tertiary : AppColors.indigo,
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('Nhóm bài học hiện tại', '当前课程组'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? colorScheme.primary : AppColors.indigo,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.tr(
                      '${catalog.startAge}–${catalog.endAge} tuổi',
                      '${catalog.startAge}–${catalog.endAge} 岁',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isDark
                          ? colorScheme.onSurface
                          : AppColors.deepNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: isDark ? colorScheme.outlineVariant : AppColors.mintBorder,
            ),
            Semantics(
              button: true,
              enabled: canChange,
              label: context.tr('Phụ huynh thay đổi nhóm bài học', '家长更改课程组'),
              child: OutlinedButton.icon(
                key: const Key('topic-age-selector'),
                onPressed: canChange ? onChange : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(76, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  foregroundColor: isDark
                      ? colorScheme.primary
                      : AppColors.indigo,
                  disabledForegroundColor: colorScheme.onSurfaceVariant,
                  backgroundColor: isDark
                      ? colorScheme.surfaceContainerHighest
                      : AppColors.mintWash,
                  side: BorderSide(
                    color: canChange
                        ? (isDark
                              ? colorScheme.primary.withValues(alpha: 0.55)
                              : AppColors.mint.withValues(alpha: 0.55))
                        : colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: Text(context.tr('Đổi', '更改')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonGroupPickerSheet extends StatefulWidget {
  const _LessonGroupPickerSheet({
    required this.catalogs,
    required this.selectedIndex,
  });

  final List<ListeningAgeCatalog> catalogs;
  final int selectedIndex;

  @override
  State<_LessonGroupPickerSheet> createState() =>
      _LessonGroupPickerSheetState();
}

class _LessonGroupPickerSheetState extends State<_LessonGroupPickerSheet> {
  late int _selectedIndex = widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      key: const Key('lesson-group-picker-sheet'),
      color: isDark ? AppColors.darkSurfaceRaised : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.tr('Chọn nhóm bài học', '选择课程组'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: isDark
                            ? colorScheme.onSurface
                            : AppColors.deepNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.sunshine.withValues(alpha: 0.18)
                          : AppColors.sunshineSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.sunshine,
                      size: 21,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                context.tr(
                  'Phụ huynh chọn nội dung phù hợp với khả năng hiện tại của trẻ. Lựa chọn này sẽ áp dụng cho Chủ đề và trợ lý MAIN.',
                  '家长请选择适合孩子当前能力的内容。此选择将同时应用于主题课程和 MAIN 助手。',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.catalogs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final catalog = widget.catalogs[index];
                    final selected = index == _selectedIndex;
                    return Material(
                      color: selected
                          ? (isDark
                                ? colorScheme.tertiaryContainer
                                : AppColors.mintSoft)
                          : (isDark
                                ? colorScheme.surfaceContainer
                                : AppColors.mintWash),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: selected
                              ? (isDark ? colorScheme.tertiary : AppColors.mint)
                              : (isDark
                                    ? colorScheme.outlineVariant
                                    : AppColors.mintBorder),
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey(
                          'age-${catalog.startAge}-${catalog.endAge}',
                        ),
                        onTap: () => setState(() => _selectedIndex = index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          child: Row(
                            children: <Widget>[
                              _LessonGroupRadio(selected: selected),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.tr(
                                    '${catalog.startAge}–${catalog.endAge} tuổi',
                                    '${catalog.startAge}–${catalog.endAge} 岁',
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: isDark
                                        ? colorScheme.onSurface
                                        : AppColors.deepNavy,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                context.tr(
                                  '${catalog.topics.length} chủ đề',
                                  '${catalog.topics.length} 个主题',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.verified_user_outlined,
                    size: 22,
                    color: isDark ? colorScheme.tertiary : AppColors.mint,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      context.tr('Đã xác thực khu vực phụ huynh', '已验证家长区域'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.mint.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FilledButton(
                  key: const Key('apply-topic-age'),
                  onPressed: () => Navigator.of(context).pop(_selectedIndex),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: isDark
                        ? colorScheme.primary
                        : AppColors.primaryNavy,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(context.tr('Áp dụng', '应用')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonGroupRadio extends StatelessWidget {
  const _LessonGroupRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryNavy : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? AppColors.primaryNavy
              : colorScheme.onSurfaceVariant,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: selected ? 9 : 0,
        height: selected ? 9 : 0,
        decoration: const BoxDecoration(
          color: AppColors.sunshine,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

typedef _TopicProgressResolver = _TopicProgress Function(int index);
typedef _TopicHasSongsResolver = bool Function(int index);
typedef _TopicEnglishTitleResolver = String Function(int index);
typedef _TopicPressed = Future<void> Function(ListeningTopic topic, int index);

class _TopicJourney extends StatelessWidget {
  const _TopicJourney({
    required this.catalogId,
    required this.topics,
    required this.englishTitleFor,
    required this.progressFor,
    required this.hasSongsFor,
    required this.onTopicPressed,
    required this.onSongsPressed,
  });

  final String catalogId;
  final List<ListeningTopic> topics;
  final _TopicEnglishTitleResolver englishTitleFor;
  final _TopicProgressResolver progressFor;
  final _TopicHasSongsResolver hasSongsFor;
  final _TopicPressed onTopicPressed;
  final _TopicPressed onSongsPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
        final rowHeight = 204.0 + ((textScale - 1) * 180);
        final sideWidth = (width * 0.34).clamp(110.0, 190.0).toDouble();
        final imageSize = (sideWidth - 16).clamp(88.0, 124.0).toDouble();
        const checkpointWidth = 40.0;

        return SizedBox(
          height: rowHeight * topics.length,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('topic-journey-path'),
                    painter: _JourneyPathPainter(
                      itemCount: topics.length,
                      rowHeight: rowHeight,
                      checkpointInset: sideWidth + (checkpointWidth / 2),
                    ),
                  ),
                ),
              ),
              Column(
                children: List<Widget>.generate(topics.length, (index) {
                  final topic = topics[index];
                  final progress = progressFor(index);
                  final hasSongs = hasSongsFor(index);
                  return SizedBox(
                    height: rowHeight,
                    child: _JourneyTopicStop(
                      topicKey: ValueKey('topic-$catalogId-$index'),
                      actionKey: ValueKey('topic-action-$catalogId-$index'),
                      songActionKey: ValueKey('topic-songs-$catalogId-$index'),
                      topic: topic,
                      titleEn: englishTitleFor(index),
                      progress: progress,
                      hasSongs: hasSongs,
                      imageSize: imageSize,
                      sideWidth: sideWidth,
                      checkpointWidth: checkpointWidth,
                      imageOnLeft: index.isEven,
                      onPressed: () => onTopicPressed(topic, index),
                      onSongsPressed: () => onSongsPressed(topic, index),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JourneyTopicStop extends StatelessWidget {
  const _JourneyTopicStop({
    required this.topicKey,
    required this.actionKey,
    required this.songActionKey,
    required this.topic,
    required this.titleEn,
    required this.progress,
    required this.hasSongs,
    required this.imageSize,
    required this.sideWidth,
    required this.checkpointWidth,
    required this.imageOnLeft,
    required this.onPressed,
    required this.onSongsPressed,
  });

  final Key topicKey;
  final Key actionKey;
  final Key songActionKey;
  final ListeningTopic topic;
  final String titleEn;
  final _TopicProgress progress;
  final bool hasSongs;
  final double imageSize;
  final double sideWidth;
  final double checkpointWidth;
  final bool imageOnLeft;
  final VoidCallback onPressed;
  final VoidCallback onSongsPressed;

  @override
  Widget build(BuildContext context) {
    final title = context.tr(topic.titleVi, topic.titleZh);
    final englishTitle = titleEn.trim();
    final image = SizedBox(
      width: sideWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Align(
            alignment: imageOnLeft
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Opacity(
                  opacity: 1,
                  child: _TopicCircleImage(
                    key: topicKey,
                    topic: topic,
                    size: imageSize,
                  ),
                ),
              ],
            ),
          ),
          if (hasSongs) ...<Widget>[
            const SizedBox(height: 5),
            OutlinedButton.icon(
              key: songActionKey,
              onPressed: onSongsPressed,
              icon: const Icon(Icons.music_note_rounded, size: 18),
              label: Text(context.tr('Bài hát', '歌曲')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.coral,
                side: BorderSide(
                  color: AppColors.coral.withValues(alpha: 0.55),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final checkpoint = SizedBox(
      width: checkpointWidth,
      child: _JourneyCheckpoint(completed: progress.fraction >= 1),
    );
    final details = Expanded(
      child: _TopicDetails(
        title: title,
        titleEn: titleEn,
        progress: progress,
        alignRight: !imageOnLeft,
        actionKey: actionKey,
        onPressed: onPressed,
      ),
    );

    return Semantics(
      button: true,
      label:
          '${englishTitle.isEmpty ? title : '$englishTitle, $title'}, '
          '${progress.completed}/${progress.total}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(32),
          splashColor: AppColors.indigo.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: imageOnLeft
                  ? <Widget>[image, checkpoint, details]
                  : <Widget>[details, checkpoint, image],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCircleImage extends StatelessWidget {
  const _TopicCircleImage({required this.topic, required this.size, super.key});

  final ListeningTopic topic;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.13),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: topic.background,
          child: topic.imagePath == null
              ? Icon(topic.icon, size: size * 0.48, color: topic.foreground)
              : Image.asset(
                  topic.imagePath!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
        ),
      ),
    );
  }
}

class _JourneyCheckpoint extends StatelessWidget {
  const _JourneyCheckpoint({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: completed ? AppColors.success : AppColors.indigo,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? colorScheme.surface : Colors.white,
            width: 3,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.indigo.withValues(alpha: 0.22),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(
          completed ? Icons.check_rounded : Icons.star_rounded,
          color: Colors.white,
          size: 19,
        ),
      ),
    );
  }
}

class _TopicDetails extends StatelessWidget {
  const _TopicDetails({
    required this.title,
    required this.titleEn,
    required this.progress,
    required this.alignRight,
    required this.actionKey,
    required this.onPressed,
  });

  final String title;
  final String titleEn;
  final _TopicProgress progress;
  final bool alignRight;
  final Key actionKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alignment = alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlignment = alignRight ? TextAlign.right : TextAlign.left;
    final englishTitle = titleEn.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment,
        children: <Widget>[
          Text(
            englishTitle.isEmpty ? title : englishTitle,
            key: englishTitle.isEmpty
                ? null
                : ValueKey('topic-english-title-$titleEn'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlignment,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? colorScheme.onSurface : AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              shadows: _journeyTextShadowsFor(context),
            ),
          ),
          if (englishTitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlignment,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? colorScheme.onSurfaceVariant
                    : AppColors.ink.withValues(alpha: 0.72),
                fontSize: 13.5,
                height: 1.18,
                fontWeight: FontWeight.w600,
                shadows: _journeyTextShadowsFor(context),
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            context.tr(
              '${progress.total} bài học · ${progress.completed}/${progress.total}',
              '${progress.total} 课 · ${progress.completed}/${progress.total}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlignment,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? colorScheme.onSurfaceVariant
                  : AppColors.ink.withValues(alpha: 0.78),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              shadows: _journeyTextShadowsFor(context),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: actionKey,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(92, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(
              context.tr(
                progress.completed == 0
                    ? 'Bắt đầu'
                    : progress.fraction >= 1
                    ? 'Học lại'
                    : 'Tiếp tục',
                progress.completed == 0
                    ? '开始'
                    : progress.fraction >= 1
                    ? '重学'
                    : '继续',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _journeyTextShadows = <Shadow>[
  Shadow(color: Colors.white, blurRadius: 2),
  Shadow(color: Colors.white, blurRadius: 7),
  Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 3),
];

List<Shadow> _journeyTextShadowsFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const <Shadow>[
        Shadow(color: Colors.black54, blurRadius: 3),
        Shadow(color: Colors.black38, blurRadius: 7),
      ]
    : _journeyTextShadows;

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({
    required this.itemCount,
    required this.rowHeight,
    required this.checkpointInset,
  });

  final int itemCount;
  final double rowHeight;
  final double checkpointInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount < 2) {
      return;
    }

    Offset pointFor(int index) => Offset(
      index.isEven ? checkpointInset : size.width - checkpointInset,
      rowHeight * (index + 0.5),
    );

    final path = Path();
    var current = pointFor(0);
    path.moveTo(current.dx, current.dy);
    for (var index = 1; index < itemCount; index++) {
      final next = pointFor(index);
      final middleY = (current.dy + next.dy) / 2;
      path.cubicTo(current.dx, middleY, next.dx, middleY, next.dx, next.dy);
      current = next;
    }

    final haloPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.74)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, haloPaint);

    final dashPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.coral,
          AppColors.coral,
          Color(0xFF31C7B0),
          Color(0xFF31C7B0),
        ],
        stops: <double>[0, 0.10, 0.15, 1],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 8).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), dashPaint);
        distance += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_JourneyPathPainter oldDelegate) {
    return itemCount != oldDelegate.itemCount ||
        rowHeight != oldDelegate.rowHeight ||
        checkpointInset != oldDelegate.checkpointInset;
  }
}

class _TopicProgress {
  const _TopicProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total == 0 ? 0 : completed / total;
}
