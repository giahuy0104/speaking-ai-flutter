import '../domain/homi_fallback_catalog.dart';
import '../domain/master_navigation_contract.dart';

enum VoiceNavigationDestination {
  conversation,
  vocabulary,
  topics,
  history,
  settings,
}

/// Optional direct entry inside the Vocabulary module.
enum VoiceVocabularyTarget { parent, star, review }

class VoiceNavigationIntent {
  const VoiceNavigationIntent({
    required this.destination,
    required this.recognizedText,
    required this.matchedPhrase,
    this.topicNumber,
    this.lessonNumber,
    this.childAge,
    this.openLesson = false,
    this.relearnTopic = false,
    this.relearnLesson = false,
    this.enterMainSpeakingMode = false,
    this.prepareOnly = false,
    this.vocabularyTarget,
  });

  final VoiceNavigationDestination destination;
  final String recognizedText;
  final String matchedPhrase;
  final int? topicNumber;
  final int? lessonNumber;
  final int? childAge;
  final bool openLesson;
  final bool relearnTopic;
  final bool relearnLesson;
  final bool enterMainSpeakingMode;

  /// Shows the destination before its acknowledgement, without starting its mic.
  final bool prepareOnly;
  final VoiceVocabularyTarget? vocabularyTarget;
}

class VoiceNavigationIntentResolver {
  const VoiceNavigationIntentResolver();

  static const spokenNumberPattern =
      r'\d{1,2}|muoi(?: (?:mot|hai|ba|bon|tu|lam))?|dau tien|mot|hai|ba|bon|tu|nam|sau|bay|tam|chin|first|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen';

  static int? parseSpokenNumber(String token) =>
      int.tryParse(token) ??
      const <String, int>{
        'mot': 1,
        'dau tien': 1,
        'hai': 2,
        'ba': 3,
        'bon': 4,
        'tu': 4,
        'nam': 5,
        'sau': 6,
        'bay': 7,
        'tam': 8,
        'chin': 9,
        'muoi': 10,
        'muoi mot': 11,
        'muoi hai': 12,
        'muoi ba': 13,
        'muoi bon': 14,
        'muoi tu': 14,
        'muoi lam': 15,
        'first': 1,
        'one': 1,
        'two': 2,
        'three': 3,
        'four': 4,
        'five': 5,
        'six': 6,
        'seven': 7,
        'eight': 8,
        'nine': 9,
        'ten': 10,
        'eleven': 11,
        'twelve': 12,
        'thirteen': 13,
        'fourteen': 14,
        'fifteen': 15,
      }[token];

  /// A numbered topic is a complete command even without an opening verb.
  /// Require the whole utterance so an ordinary sentence mentioning a topic
  /// does not navigate, and a partial prefix never commits a missing number.
  static int? directTopicNumber(String recognizedText) {
    final normalized = _normalize(recognizedText);
    final match = RegExp(
      r'^(?:(?:con|minh|toi) )?'
      r'(?:(?:chon|hoc lai|hoc|muon hoc lai|muon hoc|muon chon|muon|cho minh hoc|mo lai|mo|vao|hay mo|open|choose|select) )?'
      '(?:chu de|topic)(?: so| number)? ($spokenNumberPattern)'
      r'(?: nhe| nha| a| di| please)?$',
    ).firstMatch(normalized);
    return match == null ? null : parseSpokenNumber(match.group(1)!);
  }

  /// Whole commands only; a sentence mentioning a section remains content.
  static VoiceVocabularyTarget? directVocabularyTarget(String text) {
    for (final entry in const <String, VoiceVocabularyTarget>{
      'OPEN_PARENT': VoiceVocabularyTarget.parent,
      'OPEN_STAR': VoiceVocabularyTarget.star,
      'OPEN_REVIEW': VoiceVocabularyTarget.review,
    }.entries) {
      if (MasterNavigationContract.matches(entry.key, text)) return entry.value;
    }
    return null;
  }

  /// HOMI wake aliases approved in the fallback workbook. "Bạn ơi" is
  /// intentionally excluded: without a brand word it is too broad to use as
  /// an app-wide wake trigger.
  static final List<String> _wakePhrases =
      <String>[
            ...?HomiFallbackCatalog.childPhrasesByIntent['INT-022'],
            ...?MasterNavigationContract.phrases['WAKE_WORD'],
            'HOMI ơi',
            'Hey HOMI',
            'Bạn HOMI ơi',
            'HOMI có nghe không',
            'HOMI giúp mình',
            'HOMI nghe mình nói nhé',
            'bạn HOMI',
            'Ê HOMI',
          ]
          .map(HomiFallbackCatalog.normalizeVietnamese)
          .where((phrase) => phrase != 'ban oi')
          .toSet()
          .toList(growable: false);

  static final Set<String> _compactWakePhrases = _wakePhrases
      .where(
        (phrase) =>
            phrase.startsWith('hey ') ||
            phrase.startsWith('hay ') ||
            phrase.startsWith('hei ') ||
            phrase.startsWith('e '),
      )
      .map((phrase) => phrase.replaceAll(' ', ''))
      .toSet();

  static const List<String> _commandCues = <String>[
    'con muon',
    'cho con',
    'giup con',
    'toi muon',
    'minh muon',
    'cho minh',
    'hay mo',
    'di den',
    'chuyen den',
    'chuyen sang',
    'quay ve',
    'tro ve',
    '我想',
    '帮我',
    '打开',
    '进入',
    '前往',
    '学习',
    '练习',
    '查看',
  ];

  static const List<String> _leadingCommandCues = <String>[
    'mo',
    'vao',
    'xem',
    'hoc',
    'luyen',
    'bat dau',
    'quay ve',
    'tro ve',
  ];

  static final List<
    ({VoiceNavigationDestination destination, List<String> phrases})
  >
  _rules = <({VoiceNavigationDestination destination, List<String> phrases})>[
    (
      destination: VoiceNavigationDestination.vocabulary,
      phrases: _mergePhrases(<String>[
        'hoc tu vung',
        'on tu vung',
        'hoc tu moi',
        'luyen tu',
        'hoc tu',
        'kho tu vung',
        'tu vung',
        'tu moi',
        '词汇',
        '生词',
      ], 'INT-003'),
    ),
    (
      destination: VoiceNavigationDestination.topics,
      phrases: _mergePhrases(<String>[
        'luyen nghe theo chu de',
        'bat dau bai hoc',
        'hoc khoa hoc',
        'hoc theo chu de',
        'hoc chu de',
        'hoc bai',
        'chu de',
        '主题听力',
        '主题',
      ], 'INT-002'),
    ),
    (
      destination: VoiceNavigationDestination.conversation,
      phrases: <String>[
        'luyen giao tiep',
        'trang giao tiep',
        'giao tiep',
        'luyen noi',
        'noi chuyen',
        '沟通',
        '口语练习',
      ],
    ),
    (
      destination: VoiceNavigationDestination.history,
      phrases: <String>[
        'lich su gan day',
        'lich su hoc',
        'lich su',
        'cau da hoc',
        '历史记录',
        '历史',
      ],
    ),
    (
      destination: VoiceNavigationDestination.settings,
      phrases: <String>[
        'mo cai dat',
        'cai dat',
        'thiet lap',
        'doi giao dien',
        '设置',
      ],
    ),
  ];

  VoiceNavigationIntent? resolve(
    String recognizedText, {
    bool allowShortDirectCommand = true,
  }) {
    final normalized = _normalize(recognizedText);
    if (normalized.isEmpty) {
      return null;
    }

    final vocabularyTarget = directVocabularyTarget(normalized);
    if (vocabularyTarget != null &&
        (allowShortDirectCommand || _hasCommandCue(normalized))) {
      return VoiceNavigationIntent(
        destination: VoiceNavigationDestination.vocabulary,
        recognizedText: recognizedText.trim(),
        matchedPhrase: normalized,
        vocabularyTarget: vocabularyTarget,
      );
    }

    final directTopic = directTopicNumber(normalized);
    if (directTopic != null && allowShortDirectCommand) {
      return VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'chu de so $directTopic',
        topicNumber: directTopic,
      );
    }
    if (RegExp(r'^(?:chu de so|topic number)(?: |$)').hasMatch(normalized)) {
      return null;
    }

    final hasCommandCue = _hasCommandCue(normalized);
    final wordCount = normalized.split(' ').length;
    final topicNumber = _numberAfter(normalized, 'chu de');
    final lessonNumber = _numberAfter(normalized, 'bai');
    final hasLessonRequest = _hasLessonRequest(normalized);
    final isShortLessonRequest =
        allowShortDirectCommand &&
        wordCount <= 4 &&
        (normalized == 'bai hoc' || normalized.startsWith('bai '));
    if (hasLessonRequest && (hasCommandCue || isShortLessonRequest)) {
      return VoiceNavigationIntent(
        destination: VoiceNavigationDestination.topics,
        recognizedText: recognizedText.trim(),
        matchedPhrase: 'bai hoc',
        topicNumber: topicNumber,
        lessonNumber: lessonNumber ?? 1,
        openLesson: true,
      );
    }

    VoiceNavigationIntent? bestMatch;
    var bestScore = -1;

    for (final rule in _rules) {
      for (final phrase in rule.phrases) {
        if (!_containsPhrase(normalized, phrase)) {
          continue;
        }

        // A short destination name such as "Từ vựng" is a useful command on
        // its own. Longer sentences need an action cue to avoid redirecting a
        // normal question that merely mentions a feature.
        final isShortDirectCommand =
            allowShortDirectCommand &&
            (normalized == phrase ||
                (wordCount <= 4 && normalized.endsWith(phrase)));
        // Catalog variants without a command cue are useful after a final ASR
        // result, but a partial "từ vựng" may still grow into a normal
        // sentence. Keep those broad variants out of the fast path.
        final isApprovedFallbackPhrase =
            allowShortDirectCommand &&
            _isFallbackDestinationPhrase(normalized, rule.destination);
        if (!hasCommandCue &&
            !isShortDirectCommand &&
            !isApprovedFallbackPhrase) {
          continue;
        }

        final score = phrase.runes.length + (normalized == phrase ? 100 : 0);
        if (score <= bestScore) {
          continue;
        }
        bestScore = score;
        bestMatch = VoiceNavigationIntent(
          destination: rule.destination,
          recognizedText: recognizedText.trim(),
          matchedPhrase: phrase,
          topicNumber: rule.destination == VoiceNavigationDestination.topics
              ? topicNumber
              : null,
        );
      }
    }

    return bestMatch;
  }

  bool containsWakeWord(String recognizedText) {
    final normalized = _normalize(recognizedText);
    if (_wakePhrases.any((phrase) => _containsPhrase(normalized, phrase))) {
      return true;
    }

    // Vietnamese ASR commonly changes the HOMI syllables. Only allow fuzzy
    // matching after an explicit wake-like first word so an incidental brand
    // mention does not open a page accidentally.
    final words = normalized.split(' ');
    const wakeStarts = <String>{'hey', 'hay', 'hei', 'e'};
    for (var start = 0; start < words.length; start += 1) {
      if (!wakeStarts.contains(words[start])) {
        continue;
      }
      var candidate = '';
      final endLimit = (start + 3).clamp(0, words.length - 1);
      for (var end = start; end <= endLimit; end += 1) {
        candidate += words[end];
        if (_compactWakePhrases.any(
          (phrase) => _editDistanceAtMost(candidate, phrase, 1),
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _editDistanceAtMost(String left, String right, int limit) {
    if ((left.length - right.length).abs() > limit) {
      return false;
    }
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex;
      var rowMinimum = current[0];
      for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
        final substitutionCost =
            left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
            ? 0
            : 1;
        current[rightIndex] = _minimumOfThree(
          current[rightIndex - 1] + 1,
          previous[rightIndex] + 1,
          previous[rightIndex - 1] + substitutionCost,
        );
        if (current[rightIndex] < rowMinimum) {
          rowMinimum = current[rightIndex];
        }
      }
      if (rowMinimum > limit) {
        return false;
      }
      previous = current;
    }
    return previous.last <= limit;
  }

  static int _minimumOfThree(int first, int second, int third) {
    final firstTwo = first < second ? first : second;
    return firstTwo < third ? firstTwo : third;
  }

  static bool _containsPhrase(String value, String phrase) {
    if (phrase.runes.any((rune) => rune > 127)) {
      return value.contains(phrase);
    }
    return ' $value '.contains(' $phrase ');
  }

  static List<String> _mergePhrases(
    List<String> existingPhrases,
    String fallbackIntentId,
  ) {
    return <String>{
      ...existingPhrases,
      ...?HomiFallbackCatalog.childPhrasesByIntent[fallbackIntentId]?.map(
        HomiFallbackCatalog.normalizeVietnamese,
      ),
    }.toList(growable: false);
  }

  static bool _isFallbackDestinationPhrase(
    String normalized,
    VoiceNavigationDestination destination,
  ) {
    final intentId = switch (destination) {
      VoiceNavigationDestination.vocabulary => 'INT-003',
      VoiceNavigationDestination.topics => 'INT-002',
      _ => null,
    };
    return intentId != null &&
        _bestFallbackPhrase(normalized, <String>[intentId]) != null;
  }

  static String? _bestFallbackPhrase(
    String normalized,
    Iterable<String> intentIds,
  ) {
    String? bestMatch;
    for (final intentId in intentIds) {
      for (final phrase
          in HomiFallbackCatalog.childPhrasesByIntent[intentId] ??
              const <String>[]) {
        final normalizedPhrase = HomiFallbackCatalog.normalizeVietnamese(
          phrase,
        );
        if (_containsPhrase(normalized, normalizedPhrase) &&
            (bestMatch == null || normalizedPhrase.length > bestMatch.length)) {
          bestMatch = normalizedPhrase;
        }
      }
    }
    return bestMatch;
  }

  static bool _hasCommandCue(String value) {
    if (_commandCues.any((cue) => _containsPhrase(value, cue))) {
      return true;
    }
    return _leadingCommandCues.any(
      (cue) =>
          value == cue ||
          value.startsWith('$cue ') ||
          value.startsWith('con $cue ') ||
          value.startsWith('toi $cue '),
    );
  }

  static bool _hasLessonRequest(String value) {
    if (_containsPhrase(value, 'bai hat')) {
      return false;
    }
    return _containsPhrase(value, 'bai hoc') ||
        _numberAfter(value, 'bai') != null ||
        RegExp(r'(^| )(mo|vao|hoc|luyen|bat dau) bai( |$)').hasMatch(value);
  }

  static int? _numberAfter(String value, String marker) {
    final match = RegExp(
      '(^| )$marker(?: hoc)?(?: so)? '
      '($spokenNumberPattern)( |\$)',
    ).firstMatch(value);
    final token = match?.group(2);
    if (token == null) {
      return null;
    }
    return parseSpokenNumber(token);
  }

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
        .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
