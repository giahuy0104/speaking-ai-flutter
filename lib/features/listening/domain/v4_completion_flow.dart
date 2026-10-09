import '../../voice_navigation/domain/master_navigation_contract.dart';

enum V4CompletionStage {
  lessonEnd,
  topicEnd,
  topicEndOneRemaining,
  courseRelearnTopic,
}

enum V4CompletionAction {
  nextLesson,
  relearnCurrentLesson,
  stop,
  nextTopic,
  relearnTopic,
}

String v4CompletionPrompt(
  V4CompletionStage stage, {
  int? currentLesson,
  int? nextLesson,
  int? topicNumber,
}) {
  return switch (stage) {
    V4CompletionStage.lessonEnd =>
      currentLesson != null && nextLesson != null
          ? 'Bạn muốn học Bài $nextLesson hay học lại Bài $currentLesson?'
          : 'Bạn muốn học bài tiếp theo hay học lại bài này?',
    V4CompletionStage.topicEnd =>
      topicNumber != null
          ? 'Bạn muốn chọn Chủ đề khác hay học lại Chủ đề $topicNumber?'
          : 'Bạn muốn học chủ đề khác hay học lại?',
    V4CompletionStage.topicEndOneRemaining =>
      'Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?',
    V4CompletionStage.courseRelearnTopic =>
      'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy?',
  };
}

String v4CompletionActionLabel(V4CompletionAction action) {
  return switch (action) {
    V4CompletionAction.nextLesson => 'Bài tiếp theo',
    V4CompletionAction.relearnCurrentLesson => 'Học lại bài này',
    V4CompletionAction.stop => 'Dừng lại',
    V4CompletionAction.nextTopic => 'Chủ đề khác',
    V4CompletionAction.relearnTopic => 'Học lại chủ đề',
  };
}

class V4CompletionChoiceResolver {
  const V4CompletionChoiceResolver();

  V4CompletionAction? resolve(
    String transcript, {
    required V4CompletionStage stage,
    Iterable<V4CompletionAction> allowedActions = V4CompletionAction.values,
    int? currentLesson,
    int? nextLesson,
  }) {
    final value = _normalize(transcript);
    if (value.isEmpty) return null;
    if (value.contains(' hay ') || value.contains(' hoac ')) return null;
    final allowed = allowedActions.toSet();
    V4CompletionAction? result;
    if (MasterNavigationContract.matches('STOP_GLOBAL', transcript) ||
        MasterNavigationContract.legacy('INT-001', transcript) ||
        const <String>[
          'dung lai',
          'ket thuc',
          'thoi',
          'stop',
          'finish',
        ].contains(value)) {
      return V4CompletionAction.stop;
    } else {
      result = switch (stage) {
        V4CompletionStage.lessonEnd => _lessonAction(
          value,
          currentLesson: currentLesson,
          nextLesson: nextLesson,
        ),
        V4CompletionStage.topicEnd || V4CompletionStage.topicEndOneRemaining =>
          MasterNavigationContract.matches('OTHER_TOPIC', transcript) ||
                  _hasAny(value, const <String>[
                    'chu de tiep theo',
                    'hoc tiep chu de',
                    'chu de moi',
                    'chu de khac',
                    'hoc tiep',
                    'di tiep',
                    'tiep tuc',
                    'next topic',
                    'another topic',
                    'continue',
                  ])
              ? V4CompletionAction.nextTopic
              : MasterNavigationContract.matches('RELEARN_TOPIC', transcript) ||
                    _hasAny(value, const <String>[
                      'hoc lai',
                      'luyen lai',
                      'learn again',
                      'practice again',
                      'restart',
                      'start over',
                    ])
              ? V4CompletionAction.relearnTopic
              : null,
        V4CompletionStage.courseRelearnTopic => null,
      };
    }
    return result != null && allowed.contains(result) ? result : null;
  }

  static V4CompletionAction? _lessonAction(
    String value, {
    int? currentLesson,
    int? nextLesson,
  }) {
    if (value.contains('chu de') || value.contains('level')) return null;
    // FINAL T09 explicitly requires repair for this ambiguous short answer.
    if (value == 'hoc tiep') return null;
    final selected = _numberedChoice(value, 'bai');
    if (selected != null) {
      final replay =
          _commandCore(value).startsWith('hoc lai ') ||
          _commandCore(value).startsWith('lam lai ');
      if (selected == currentLesson) {
        return V4CompletionAction.relearnCurrentLesson;
      }
      if (selected == nextLesson && !replay) {
        return V4CompletionAction.nextLesson;
      }
      return null;
    }
    final next =
        MasterNavigationContract.matches('NEXT_LESSON', _commandCore(value)) ||
        _hasAny(value, const <String>[
          'hoc bai tiep theo',
          'bai tiep theo',
          'hoc tiep',
          'tiep theo',
          'di tiep',
          'tiep tuc',
          'bai sau',
          'next lesson',
          'next one',
          'continue',
        ]);
    final replay =
        MasterNavigationContract.matches(
          'RELEARN_LESSON',
          _commandCore(value),
        ) ||
        _hasAny(value, const <String>[
          'hoc lai',
          'luyen lai',
          'bai nay',
          'learn again',
          'practice again',
          'relearn',
          'restart',
          'start over',
        ]);
    if (next && replay) return null;
    if (replay) return V4CompletionAction.relearnCurrentLesson;
    if (next) return V4CompletionAction.nextLesson;
    return null;
  }

  static String _commandCore(String value) => value
      .replaceFirst(
        RegExp(
          r'^(?:con muon|minh muon|toi muon|cho con|cho minh|i want to|the) ',
        ),
        '',
      )
      .replaceFirst(RegExp(r' (?:a|nhe|di)$'), '');

  static int? _numberedChoice(String value, String scope) {
    final core = _commandCore(value);
    final match = RegExp(
      '^(?:(?:hoc lai|lam lai|hoc|bat dau|mo|chon) )?'
      '(?:$scope(?: so)? )?'
      r'(\d+|mot|hai|ba|bon|nam|sau|bay|tam|chin|muoi)$',
    ).firstMatch(core);
    if (match == null) return null;
    const spoken = {
      'mot': 1,
      'hai': 2,
      'ba': 3,
      'bon': 4,
      'nam': 5,
      'sau': 6,
      'bay': 7,
      'tam': 8,
      'chin': 9,
      'muoi': 10,
    };
    return int.tryParse(match.group(1)!) ?? spoken[match.group(1)!];
  }

  static bool _hasAny(String value, Iterable<String> phrases) =>
      phrases.contains(_commandCore(value));

  static String _normalize(String input) {
    const accented =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const plain =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      final index = accented.indexOf(character);
      buffer.write(index < 0 ? character : plain[index]);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
