import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../../voice_navigation/domain/master_navigation_contract.dart';
import '../application/lesson_media_service.dart';
import '../domain/lesson_guide_flow.dart';

enum V4SongStageAction { skipped, continued }

/// A V4 song placement is deliberately separate from the older standalone
/// song-lesson player. The five approved recordings are joined through
/// [songAudioUri] without treating them as legacy lessons again.
class V4SongStageScreen extends StatefulWidget {
  const V4SongStageScreen({
    required this.language,
    required this.songTitle,
    required this.mediaService,
    this.songAudioId,
    this.songAudioUri,
    this.voicePromptService,
    super.key,
  });

  final DisplayLanguage language;
  final String songTitle;
  final LessonMediaService mediaService;
  final String? songAudioId;
  final Uri? songAudioUri;
  final VoicePromptService? voicePromptService;

  @override
  State<V4SongStageScreen> createState() => _V4SongStageScreenState();
}

class _V4SongStageScreenState extends State<V4SongStageScreen>
    implements ActiveLearningModuleController, ActiveLearningVoiceContext {
  VoicePromptService? _voicePromptService;
  late final bool _ownsVoicePromptService;
  bool _announcing = true;
  bool _playing = false;
  bool _pausedForMainAssistant = false;
  bool _resumeSongAfterMain = false;
  bool _resumeAnnouncementAfterMain = false;
  bool _leaving = false;
  String? _message;
  int _request = 0;
  ActiveLearningModuleRegistry? _activeModuleRegistry;
  Object? _activeModuleRegistration;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  @override
  ActiveLearningVoiceNode get mainVoiceNode => ActiveLearningVoiceNode.song;

  @override
  String get mainVoicePrompt => MasterNavigationContract.songControlPrompt;

  VoicePromptService get _prompt {
    final current = _voicePromptService;
    if (current != null) return current;
    return _voicePromptService = createVoicePromptService();
  }

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService = widget.voicePromptService;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_announceAndPlaySong()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (identical(registry, _activeModuleRegistry)) return;
    final oldRegistry = _activeModuleRegistry;
    final oldRegistration = _activeModuleRegistration;
    if (oldRegistry != null && oldRegistration != null) {
      oldRegistry.unregister(oldRegistration);
    }
    _activeModuleRegistry = registry;
    _activeModuleRegistration = registry?.register(this);
  }

  @override
  void dispose() {
    final registration = _activeModuleRegistration;
    if (registration != null) {
      _activeModuleRegistry?.unregister(registration);
    }
    _request += 1;
    if (!_leaving) {
      unawaited(widget.mediaService.stopPlayback());
      final prompt = _voicePromptService;
      if (prompt != null) {
        if (_ownsVoicePromptService) {
          unawaited(prompt.dispose());
        } else {
          unawaited(prompt.stop());
        }
      }
    }
    super.dispose();
  }

  Future<void> _announceAndPlaySong() async {
    if (!mounted || _pausedForMainAssistant || _leaving) return;
    final request = ++_request;
    setState(() {
      _announcing = true;
      _message = null;
    });
    try {
      await widget.mediaService.prepareSelectedLessonOutput();
      if (!mounted || request != _request) return;
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _announcing = false;
        _message = 'Chưa xác nhận được loa và mic H20. Bạn thử lại nhé.';
      });
      return;
    }
    try {
      final prompt = _prompt;
      final cue = v4SongStartCue(widget.songTitle);
      if (!kIsWeb && prompt is SelectedMediaOutputVoicePromptService) {
        await (prompt as SelectedMediaOutputVoicePromptService)
            .speakAndWaitOnSelectedMediaOutput(cue, locale: 'vi-VN');
      } else {
        await prompt.speakAndWait(cue, locale: 'vi-VN');
      }
    } catch (_) {
      // The approved song still starts if a device TTS voice is unavailable.
    }
    if (!mounted || request != _request) return;
    setState(() => _announcing = false);

    if (widget.songAudioUri == null) {
      setState(() => _message = 'Chưa tìm thấy file audio của bài hát.');
      return;
    }
    await _playSongAndContinue(request: request);
  }

  Future<void> _playSongAndContinue({int? request}) async {
    final uri = widget.songAudioUri;
    if (uri == null ||
        _playing ||
        !mounted ||
        _pausedForMainAssistant ||
        _leaving) {
      return;
    }
    final playRequest = request ?? ++_request;
    if (playRequest != _request) return;
    setState(() {
      _playing = true;
      _message = null;
    });
    try {
      await _prompt.stop();
      if (!mounted || playRequest != _request) return;
      await widget.mediaService.playToCompletion(
        uri,
        timeout: const Duration(minutes: 5),
      );
      if (!mounted || playRequest != _request) return;
      await _finish(V4SongStageAction.continued);
    } catch (_) {
      if (mounted && playRequest == _request) {
        setState(() => _message = 'Chưa thể phát bài hát. Bạn thử lại nhé.');
      }
    } finally {
      if (mounted && playRequest == _request) {
        setState(() => _playing = false);
      }
    }
  }

  Future<void> _finish(V4SongStageAction action) async {
    if (_leaving) return;
    _leaving = true;
    _pausedForMainAssistant = false;
    _request += 1;
    await _prompt.stop().catchError((Object _) {});
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    if (_ownsVoicePromptService) {
      await _prompt.dispose().catchError((Object _) {});
    }
    if (mounted) Navigator.of(context).pop(action);
  }

  @override
  Future<void> pauseForMainAssistant() async {
    if (_pausedForMainAssistant || _leaving) return;
    _resumeSongAfterMain = _playing;
    _resumeAnnouncementAfterMain = _announcing;
    _pausedForMainAssistant = true;
    _request += 1;
    if (mounted) {
      setState(() {
        _playing = false;
        _announcing = false;
        _message = 'Bài hát đang tạm dừng.';
      });
    }
    await Future.wait<void>(<Future<void>>[
      _prompt.stop().catchError((Object _) {}),
      widget.mediaService.stopPlayback().catchError((Object _) {}),
    ]);
  }

  Future<void> _resumeFromMain({required bool replay}) async {
    if (!mounted || _leaving) return;
    final resumeSong = replay || _resumeSongAfterMain;
    final resumeAnnouncement = !replay && _resumeAnnouncementAfterMain;
    _pausedForMainAssistant = false;
    _resumeSongAfterMain = false;
    _resumeAnnouncementAfterMain = false;
    setState(() => _message = null);
    if (replay) {
      await widget.mediaService.rewindPlayback();
    }
    if (resumeAnnouncement) {
      unawaited(_announceAndPlaySong());
    } else if (resumeSong) {
      unawaited(_playSongAndContinue());
    }
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted || _leaving) {
      return const ActiveLearningCommandResult.unavailable();
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng.',
        );
      case ActiveLearningCommand.resume:
        await _resumeFromMain(replay: false);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
      case ActiveLearningCommand.restart:
        await _resumeFromMain(replay: true);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
        await _finish(V4SongStageAction.skipped);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.exitToHome:
        await pauseForMainAssistant();
        if (!mounted) {
          return const ActiveLearningCommandResult.unavailable();
        }
        _leaving = true;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.vocabularyParentAdded:
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSongAudio = widget.songAudioUri != null;
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('v4-song-stage-screen'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                  child: Column(
                    children: <Widget>[
                      const Spacer(),
                      Image.asset(
                        MascotAssets.sing,
                        width: 142,
                        height: 142,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                      Text('Bài hát', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 10),
                      Text(
                        widget.songTitle,
                        key: const Key('v4-song-stage-title'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: AppColors.indigoDark,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.lavenderBorder),
                        ),
                        child: Text(
                          v4SongStartCue(widget.songTitle),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (hasSongAudio)
                        FilledButton.tonalIcon(
                          key: const Key('v4-song-stage-play'),
                          onPressed: _announcing || _playing
                              ? null
                              : _playSongAndContinue,
                          icon: Icon(
                            _playing
                                ? Icons.graphic_eq_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(
                            _announcing
                                ? 'Chuẩn bị bài hát'
                                : _playing
                                ? 'Đang phát bài hát'
                                : 'Thử phát lại',
                          ),
                        )
                      else
                        Text(
                          _announcing
                              ? 'Đang chuẩn bị bài hát.'
                              : 'Chưa tìm thấy file audio của bài hát.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      if (_message != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                      const Spacer(),
                      TextButton.icon(
                        key: const Key('v4-song-stage-skip'),
                        onPressed: () => _finish(V4SongStageAction.skipped),
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Bỏ qua bài hát'),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('v4-song-stage-continue'),
                          onPressed: _announcing || _playing
                              ? null
                              : () => _finish(V4SongStageAction.continued),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _announcing ? 'Tiếp tục' : 'Tiếp tục học',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
