enum V4CompletionStage {
  lessonEnd,
  topicEnd,
  topicEndOneRemaining,
  nextLevel,
  courseRelearnLevel,
}

enum V4CompletionAction {
  nextLesson,
  relearnCurrentLesson,
  stop,
  nextTopic,
  relearnTopic,
  startNextLevel,
  relearnLevel1,
  relearnLevel2,
  relearnLevel3,
}

String v4CompletionPrompt(
  V4CompletionStage stage, {
  int? currentLesson,
  int? nextLesson,
  int? topicNumber,
  int? nextLevel,
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
    V4CompletionStage.nextLevel =>
      'Bạn muốn bắt đầu Level ${nextLevel ?? ''} hay dừng lại?'.replaceAll(
        'Level  ',
        'Level ',
      ),
    V4CompletionStage.courseRelearnLevel =>
      'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?',
  };
}

String v4CompletionActionLabel(V4CompletionAction action) {
  return switch (action) {
    V4CompletionAction.nextLesson => 'Bài tiếp theo',
    V4CompletionAction.relearnCurrentLesson => 'Học lại bài này',
    V4CompletionAction.stop => 'Dừng lại',
    V4CompletionAction.nextTopic => 'Chủ đề khác',
    V4CompletionAction.relearnTopic => 'Học lại chủ đề',
    V4CompletionAction.startNextLevel => 'Bắt đầu Level tiếp theo',
    V4CompletionAction.relearnLevel1 => 'Học lại Level 1',
    V4CompletionAction.relearnLevel2 => 'Học lại Level 2',
    V4CompletionAction.relearnLevel3 => 'Học lại Level 3',
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
    final allowed = allowedActions.toSet();

    V4CompletionAction? result;
    if (_hasAny(value, const <String>[
      'dung lai',
      'ket thuc',
      'thoi',
      'stop',
      'finish',
    ])) {
      result = V4CompletionAction.stop;
    } else {
      result = switch (stage) {
        V4CompletionStage.lessonEnd => _lessonAction(
          value,
          currentLesson: currentLesson,
          nextLesson: nextLesson,
        ),
        V4CompletionStage.topicEnd || V4CompletionStage.topicEndOneRemaining =>
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
              : _hasAny(value, const <String>[
                  'hoc lai',
                  'luyen lai',
                  'learn again',
                  'practice again',
                  'restart',
                  'start over',
                ])
              ? V4CompletionAction.relearnTopic
              : null,
        V4CompletionStage.nextLevel =>
          _hasAny(value, const <String>[
                'level tiep theo',
                'bat dau level',
                'hoc level',
                'hoc tiep',
                'di tiep',
                'tiep tuc',
                'next level',
                'start level',
                'continue',
              ])
              ? V4CompletionAction.startNextLevel
              : null,
        V4CompletionStage.courseRelearnLevel => _levelAction(value),
      };
    }
    return result != null && allowed.contains(result) ? result : null;
  }

  static V4CompletionAction? _lessonAction(
    String value, {
    int? currentLesson,
    int? nextLesson,
  }) {
    final namesCurrent = _mentionsLesson(value, currentLesson);
    final namesNext = _mentionsLesson(value, nextLesson);
    final next = _hasAny(value, const <String>[
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
    final replay = _hasAny(value, const <String>[
      'hoc lai',
      'luyen lai',
      'bai nay',
      'learn again',
      'practice again',
      'relearn',
      'restart',
      'start over',
    ]);
    // Never choose the first option when ASR picked up the whole question.
    // An explicit replay must also not turn "học lại Bài 2" into nextLesson.
    if ((namesCurrent && namesNext) || (next && replay)) return null;
    if (replay) {
      return namesNext ? null : V4CompletionAction.relearnCurrentLesson;
    }
    if (next || namesNext) return V4CompletionAction.nextLesson;
    if (namesCurrent) return V4CompletionAction.relearnCurrentLesson;
    return null;
  }

  static bool _mentionsLesson(String value, int? number) {
    if (number == null) return false;
    const spokenNumbers = <int, String>{
      1: 'mot',
      2: 'hai',
      3: 'ba',
      4: 'bon',
      5: 'nam',
      6: 'sau',
      7: 'bay',
      8: 'tam',
      9: 'chin',
      10: 'muoi',
    };
    return _hasAny(value, <String>[
      'bai $number',
      'bai so $number',
      'lesson $number',
      if (spokenNumbers[number] case final spoken?) 'bai $spoken',
      if (spokenNumbers[number] case final spoken?) 'bai so $spoken',
    ]);
  }

  static V4CompletionAction? _levelAction(String value) {
    if (_hasAny(value, const <String>['level 1', 'level mot', 'cap 1'])) {
      return V4CompletionAction.relearnLevel1;
    }
    if (_hasAny(value, const <String>['level 2', 'level hai', 'cap 2'])) {
      return V4CompletionAction.relearnLevel2;
    }
    if (_hasAny(value, const <String>['level 3', 'level ba', 'cap 3'])) {
      return V4CompletionAction.relearnLevel3;
    }
    return null;
  }

  static bool _hasAny(String value, Iterable<String> phrases) =>
      phrases.any((phrase) => ' $value '.contains(' $phrase '));

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
