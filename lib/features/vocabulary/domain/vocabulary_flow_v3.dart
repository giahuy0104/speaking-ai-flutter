import 'vocabulary_entry.dart';

enum VocabularyJourneyKind { parentAdded, review, stars }

class VocabularyFixedPrompt {
  const VocabularyFixedPrompt({
    required this.stateId,
    required this.text,
    this.assetLookupCodes = const <String>[],
  });

  final String stateId;
  final String text;
  final List<String> assetLookupCodes;

  Iterable<String> get lookupCodes sync* {
    yield stateId;
    yield* assetLookupCodes;
  }
}

/// Exact child-facing copy and deterministic rules from Vocabulary FINAL V3.
///
/// Keeping these rules outside the widgets prevents the Android and iOS paths
/// from drifting when they use different microphone implementations.
abstract final class VocabularyFlowV3 {
  static const int groupSize = 5;

  static const String todayIntro =
      'Đã có nội dung mới cho bạn. Bắt đầu học thôi!';
  static const String todayResume = 'Mình học tiếp Danh sách hôm nay nhé.';
  static const String menu =
      'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?';
  static const String todayEmptyMenu =
      'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?';
  static const String finishActiveGroupFirst =
      'Mình học xong lượt này trước nhé.';
  static const String pauseAfterNoResponse = 'Mình tạm dừng nhé.';

  static const String todayCompletion =
      'Bạn muốn học nội dung khác hay học lại?';
  static const String todayQueueEmpty =
      'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?';

  static const String parentSmallIntro = 'Mình cùng nghe nhé.';
  static const String parentEmpty =
      'Chưa có nội dung ở phần này. Bạn muốn học Ngôi sao hay Luyện lại?';
  static const String startPlayback = 'Bắt đầu nào.';
  static const String parentGroupCompletion =
      'Bạn muốn học nội dung khác hay học tiếp?';
  static const String parentOtherMenu = 'Bạn muốn học Ngôi sao hay Luyện lại?';
  static const String parentFinished =
      'Bạn đã nghe hết rồi. Bạn muốn học nội dung khác hay học lại?';
  static const String parentResume = 'Mình nghe tiếp nhé.';

  static const String reviewIntro = 'Mình cùng luyện lại nhé. Bắt đầu thôi!';
  static const String reviewGroupCompletion =
      'Bạn muốn học nội dung khác hay học tiếp?';
  static const String reviewOtherMenu =
      'Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?';
  static const String reviewCycleFinished =
      'Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?';
  static const String reviewEmpty =
      'Không có nội dung cần luyện lại. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?';
  static const String reviewResume = 'Mình luyện tiếp nhé.';

  static const String starIntro = 'Mình cùng nghe Ngôi sao nhé.';
  static String starSmallIntro(int total) => starIntro;

  static const String starEmpty =
      'Bạn chưa có Ngôi sao nào. Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?';
  static const String starGroupCompletion =
      'Bạn muốn học nội dung khác hay học tiếp?';
  static const String starOtherMenu =
      'Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?';
  static const String starFinished =
      'Bạn đã nghe hết Ngôi sao rồi. Bạn muốn học nội dung khác hay học lại?';
  static const String resumeStars = 'Mình nghe tiếp nhé.';
  static const String starMyVoice = 'Giọng của bạn đây.';

  static const List<VocabularyFixedPrompt>
  fixedPrompts = <VocabularyFixedPrompt>[
    VocabularyFixedPrompt(stateId: 'VOCAB_MENU_01', text: menu),
    VocabularyFixedPrompt(stateId: 'TODAY_INTRO_01', text: todayIntro),
    VocabularyFixedPrompt(stateId: 'TODAY_RESUME_01', text: todayResume),
    VocabularyFixedPrompt(stateId: 'TODAY_BLOCK_END_01', text: todayCompletion),
    VocabularyFixedPrompt(
      stateId: 'PARENT_LIST_SHORT_01',
      text: parentSmallIntro,
    ),
    VocabularyFixedPrompt(
      stateId: 'PARENT_RESUME',
      text: parentResume,
      assetLookupCodes: <String>['STAR_RESUME_ALL_01'],
    ),
    VocabularyFixedPrompt(
      stateId: 'PARENT_LIST_BLOCK_END_01',
      text: parentGroupCompletion,
      assetLookupCodes: <String>['STAR_BLOCK_END_01', 'REVIEW_BLOCK_END_01'],
    ),
    VocabularyFixedPrompt(
      stateId: 'PARENT_LIST_OTHER_MENU_01',
      text: parentOtherMenu,
    ),
    VocabularyFixedPrompt(stateId: 'PARENT_LIST_END_01', text: parentFinished),
    VocabularyFixedPrompt(stateId: 'PARENT_LIST_EMPTY_01', text: parentEmpty),
    VocabularyFixedPrompt(stateId: 'STAR_INTRO_01', text: starIntro),
    VocabularyFixedPrompt(stateId: 'STAR_INTRO_0_01', text: starEmpty),
    VocabularyFixedPrompt(stateId: 'STAR_MY_VOICE_01', text: starMyVoice),
    VocabularyFixedPrompt(stateId: 'STAR_RESUME_ALL_01', text: resumeStars),
    VocabularyFixedPrompt(
      stateId: 'STAR_BLOCK_END_01',
      text: starGroupCompletion,
      assetLookupCodes: <String>[
        'PARENT_LIST_BLOCK_END_01',
        'REVIEW_BLOCK_END_01',
      ],
    ),
    VocabularyFixedPrompt(stateId: 'STAR_OTHER_MENU_01', text: starOtherMenu),
    VocabularyFixedPrompt(stateId: 'STAR_END_01', text: starFinished),
    VocabularyFixedPrompt(stateId: 'REVIEW_INTRO_01', text: reviewIntro),
    VocabularyFixedPrompt(stateId: 'REVIEW_RESUME_01', text: reviewResume),
    VocabularyFixedPrompt(
      stateId: 'REVIEW_BLOCK_END_01',
      text: reviewGroupCompletion,
      assetLookupCodes: <String>[
        'PARENT_LIST_BLOCK_END_01',
        'STAR_BLOCK_END_01',
      ],
    ),
    VocabularyFixedPrompt(
      stateId: 'REVIEW_OTHER_MENU_01',
      text: reviewOtherMenu,
    ),
    VocabularyFixedPrompt(
      stateId: 'REVIEW_PASS_END_01',
      text: reviewCycleFinished,
    ),
    VocabularyFixedPrompt(stateId: 'REVIEW_EMPTY_01', text: reviewEmpty),
  ];

  static VocabularyFixedPrompt? fixedPromptForText(String text) {
    for (final prompt in fixedPrompts) {
      if (prompt.text == text) return prompt;
    }
    return null;
  }

  static int playbackStartIndex({required int checkpoint, required int total}) {
    if (total <= 0 || checkpoint < 0 || checkpoint >= total) return 0;
    return checkpoint;
  }

  static int playbackBlockEnd({required int start, required int total}) {
    if (total <= 0) return 0;
    return (start + groupSize).clamp(0, total).toInt();
  }

  static List<VocabularyEntry> orderedForPlayback(
    Iterable<VocabularyEntry> source, {
    required VocabularyJourneyKind journey,
  }) {
    final entries = source.toList(growable: false);
    entries.sort((left, right) {
      final leftTime = journey == VocabularyJourneyKind.stars
          ? left.earnedAt ?? left.addedAt
          : left.addedAt;
      final rightTime = journey == VocabularyJourneyKind.stars
          ? right.earnedAt ?? right.addedAt
          : right.addedAt;
      return leftTime.compareTo(rightTime);
    });
    return entries;
  }

  /// Alphabet targets are authored as "A. Apple." but V3 also accepts the
  /// spoken keyword "Apple". Parent-authored text never receives this rewrite.
  static List<String> acceptedVariantsFor(VocabularyEntry entry) {
    if (entry.source == VocabularySource.parent) {
      return const <String>[];
    }
    final match = RegExp(
      r'^\s*[A-Za-z]\s*[.:-]\s*(.+?)\s*$',
    ).firstMatch(entry.word);
    final keyword = match?.group(1)?.trim() ?? '';
    return keyword.isEmpty ? const <String>[] : <String>[keyword];
  }
}
