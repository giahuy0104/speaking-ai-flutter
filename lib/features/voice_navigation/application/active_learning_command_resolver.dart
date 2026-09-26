import '../../../core/device/active_learning_module.dart';
import '../domain/controlled_speech_lexicon.dart';
import '../domain/master_navigation_contract.dart';

/// Small deterministic grammar for commands spoken after MAIN is pressed
/// while a lesson is active. It deliberately does not interpret lesson
/// content; it only maps navigation/control phrases to the shared adapter.
class ActiveLearningCommandResolver {
  const ActiveLearningCommandResolver();

  static const ControlledSpeechLexicon _controlledLexicon =
      ControlledSpeechLexicon();

  ActiveLearningCommand? resolve(
    String transcript, {
    ControlledSpeechState state = ControlledSpeechState.course,
    ActiveLearningVoiceNode? node,
  }) {
    if (node != null) return _resolveNode(transcript, node, state);
    final controlled = _controlledLexicon.resolve(transcript, state: state);
    final controlledCommand = switch (controlled?.intent) {
      ControlledSpeechIntent.globalStop => ActiveLearningCommand.stop,
      ControlledSpeechIntent.courseContinue => ActiveLearningCommand.resume,
      ControlledSpeechIntent.courseNextSentence =>
        ActiveLearningCommand.nextItem,
      ControlledSpeechIntent.coursePreviousSentence =>
        ActiveLearningCommand.previousItem,
      ControlledSpeechIntent.courseReplayCurrent =>
        ActiveLearningCommand.replayCurrent,
      ControlledSpeechIntent.courseRestartCurrent =>
        ActiveLearningCommand.restart,
      ControlledSpeechIntent.courseNextLesson =>
        ActiveLearningCommand.nextLesson,
      ControlledSpeechIntent.coursePreviousLesson => null,
      ControlledSpeechIntent.vocabularyParentAdded =>
        ActiveLearningCommand.vocabularyParentAdded,
      ControlledSpeechIntent.vocabularyPracticeAgain =>
        ActiveLearningCommand.vocabularyPracticeAgain,
      ControlledSpeechIntent.vocabularyStars =>
        ActiveLearningCommand.vocabularyStars,
      ControlledSpeechIntent.vocabularyLatest =>
        ActiveLearningCommand.vocabularyLatest,
      ControlledSpeechIntent.vocabularyAll =>
        ActiveLearningCommand.vocabularyAll,
      ControlledSpeechIntent.vocabularyOtherContent =>
        ActiveLearningCommand.exitToHome,
      _ => null,
    };
    if (controlledCommand != null) {
      return controlledCommand;
    }

    // Preserve a small set of already-shipped aliases while the controlled
    // V0.1 table becomes the primary grammar.
    final value = _normalize(transcript);
    if (value.isEmpty) {
      return null;
    }
    if (state == ControlledSpeechState.vocabulary &&
        (_has(value, 'bo qua') || _has(value, 'qua noi dung nay'))) {
      return ActiveLearningCommand.nextItem;
    }
    if (_has(value, 'dung lai') || _has(value, 'tam dung') || value == 'dung') {
      return ActiveLearningCommand.stop;
    }
    if (_has(value, 'tiep tuc') ||
        _has(value, 'hoc tiep') ||
        _has(value, 'lam tiep')) {
      return ActiveLearningCommand.resume;
    }
    if (_has(value, 'luyen lai tu dau') ||
        _has(value, 'hoc lai tu dau') ||
        _has(value, 'lam lai tu dau')) {
      return ActiveLearningCommand.restart;
    }
    if (_has(value, 'bai tiep theo') || _has(value, 'bai ke tiep')) {
      return ActiveLearningCommand.nextLesson;
    }
    if (_has(value, 'bai truoc') || _has(value, 'bai vua roi')) {
      return null;
    }
    if (_has(value, 'cau tiep theo') ||
        _has(value, 'dong tiep theo') ||
        _has(value, 'hoc cau tiep') ||
        _has(value, 'qua cau tiep') ||
        _has(value, 'tiep theo')) {
      return ActiveLearningCommand.nextItem;
    }
    if (_has(value, 'cau truoc') ||
        _has(value, 'dong truoc') ||
        _has(value, 'nghe cau truoc') ||
        _has(value, 'quay lai cau truoc') ||
        _has(value, 'cau vua roi') ||
        value == 'quay lai') {
      return ActiveLearningCommand.previousItem;
    }
    if (_has(value, 'nghe lai') ||
        _has(value, 'doc lai') ||
        _has(value, 'lap lai')) {
      return ActiveLearningCommand.replayCurrent;
    }
    return null;
  }

  ActiveLearningCommand? _resolveNode(
    String text,
    ActiveLearningVoiceNode node,
    ControlledSpeechState state,
  ) {
    final isVocabularyReview =
        node == ActiveLearningVoiceNode.review &&
        state == ControlledSpeechState.vocabulary;
    bool matches(String intent) =>
        MasterNavigationContract.matches(intent, text);
    if (matches('STOP_GLOBAL') ||
        MasterNavigationContract.legacy('INT-001', text)) {
      return ActiveLearningCommand.stop;
    }
    // The 22/09 patch makes the three vocabulary destinations and Continue
    // global while a Subject/Vocabulary activity is active. Resolve them
    // before the node-local grammar so the question currently being spoken
    // never narrows the global command surface.
    if (matches('OPEN_PARENT')) {
      return ActiveLearningCommand.vocabularyParentAdded;
    }
    if (matches('OPEN_STAR')) {
      return ActiveLearningCommand.vocabularyStars;
    }
    if (matches('OPEN_REVIEW')) {
      return ActiveLearningCommand.vocabularyPracticeAgain;
    }
    if (matches('CONTINUE_GLOBAL') &&
        node != ActiveLearningVoiceNode.vocabularyMenu &&
        node != ActiveLearningVoiceNode.parentAlternatives &&
        node != ActiveLearningVoiceNode.starAlternatives &&
        node != ActiveLearningVoiceNode.reviewAlternatives &&
        node != ActiveLearningVoiceNode.todayEnd &&
        node != ActiveLearningVoiceNode.blockEnd &&
        node != ActiveLearningVoiceNode.listEnd) {
      return ActiveLearningCommand.resume;
    }
    final choices = switch (node) {
      ActiveLearningVoiceNode.vocabularyMenu => <String, ActiveLearningCommand>{
        'OPEN_PARENT': ActiveLearningCommand.vocabularyParentAdded,
        'OPEN_STAR': ActiveLearningCommand.vocabularyStars,
        'OPEN_REVIEW': ActiveLearningCommand.vocabularyPracticeAgain,
      },
      ActiveLearningVoiceNode.parentAlternatives =>
        <String, ActiveLearningCommand>{
          'OPEN_STAR': ActiveLearningCommand.vocabularyStars,
          'OPEN_REVIEW': ActiveLearningCommand.vocabularyPracticeAgain,
        },
      ActiveLearningVoiceNode.starAlternatives =>
        <String, ActiveLearningCommand>{
          'OPEN_PARENT': ActiveLearningCommand.vocabularyParentAdded,
          'OPEN_REVIEW': ActiveLearningCommand.vocabularyPracticeAgain,
        },
      ActiveLearningVoiceNode.reviewAlternatives =>
        <String, ActiveLearningCommand>{
          'OPEN_PARENT': ActiveLearningCommand.vocabularyParentAdded,
          'OPEN_STAR': ActiveLearningCommand.vocabularyStars,
        },
      ActiveLearningVoiceNode.song => <String, ActiveLearningCommand>{
        'SKIP_SONG': ActiveLearningCommand.nextItem,
        'REPLAY_SONG': ActiveLearningCommand.replayCurrent,
      },
      ActiveLearningVoiceNode.todayEnd => <String, ActiveLearningCommand>{
        'OTHER_CONTENT': ActiveLearningCommand.exitToHome,
        'REPLAY_TODAY': ActiveLearningCommand.restart,
      },
      ActiveLearningVoiceNode.todayAfterEnVi => <String, ActiveLearningCommand>{
        'PREVIOUS_ITEM': ActiveLearningCommand.previousItem,
        'NEXT_ITEM': ActiveLearningCommand.nextItem,
        'LISTEN_AGAIN': ActiveLearningCommand.replayCurrent,
      },
      ActiveLearningVoiceNode.listEnd => <String, ActiveLearningCommand>{
        'OTHER_CONTENT': ActiveLearningCommand.exitToHome,
        'REPLAY_LIST': ActiveLearningCommand.restart,
      },
      ActiveLearningVoiceNode.blockEnd => <String, ActiveLearningCommand>{
        'OTHER_CONTENT': ActiveLearningCommand.exitToHome,
        'CONTINUE_BLOCK': ActiveLearningCommand.resume,
      },
      _ => <String, ActiveLearningCommand>{
        // "Tiếp theo" exists in both NEXT_ITEM and ACTIVE_RESUME in the
        // authored catalog. In Core/Parent/Star it means the next item; only a
        // paused node without next-item support may interpret it as resume.
        if (node != ActiveLearningVoiceNode.challenge &&
            (node != ActiveLearningVoiceNode.review || isVocabularyReview))
          'PREVIOUS_ITEM': ActiveLearningCommand.previousItem,
        if (node == ActiveLearningVoiceNode.core ||
            isVocabularyReview ||
            node == ActiveLearningVoiceNode.parent ||
            node == ActiveLearningVoiceNode.star)
          'NEXT_ITEM': ActiveLearningCommand.nextItem,
        if (node == ActiveLearningVoiceNode.core ||
            node == ActiveLearningVoiceNode.parent ||
            node == ActiveLearningVoiceNode.star)
          'SKIP_ITEM': ActiveLearningCommand.nextItem,
        'LISTEN_AGAIN': ActiveLearningCommand.replayCurrent,
        if (node != ActiveLearningVoiceNode.challenge &&
            node != ActiveLearningVoiceNode.review)
          'RESUME_ACTIVITY': ActiveLearningCommand.resume,
      },
    };
    for (final entry in choices.entries) {
      if (matches(entry.key)) return entry.value;
    }
    return null;
  }

  static bool _has(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

  static String _normalize(String value) {
    var normalized = value.trim().toLowerCase();
    const replacements = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
