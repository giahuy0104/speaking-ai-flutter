import 'homi_fallback_catalog.dart';

/// Navigation-only contract from HOMI Master FINAL plus the 2026-09-22 patch.
/// Matching is whole-utterance; lesson media, scoring and progress stay with
/// the destination module. Never feed free-form translation through this menu.
abstract final class MasterNavigationContract {
  static const version = '2026-09-22';
  static const mainPrompt =
      'HOMI đây. Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?';
  static const mainRetry =
      'Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?';
  static const translationIntro =
      'Bạn cứ nói từng câu. Muốn dừng thì nói “Dừng lại”.';
  static const afterTranslationStop =
      'Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?';
  static const translationStopped = 'Đã dừng.';
  static const translationContinue = 'Mình tiếp tục nhé.';
  static const translationSwitch =
      'Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?';
  static const keepCurrentContent = 'Mình giữ nội dung hiện tại nhé.';
  static const switchedToSubject = 'Mình đã chuyển sang Chủ đề.';
  static const switchedToVocabulary = 'Mình đã chuyển sang Bộ từ vựng.';
  static const switchedToTranslation = 'Mình đã chuyển sang Dịch tiếng Anh.';
  static const continueSubject = 'Mình tiếp tục Chủ đề nhé.';
  static const continueVocabulary = 'Mình tiếp tục Bộ từ vựng nhé.';
  static const coreControlPrompt = 'Bạn muốn nghe lại, câu trước, hay câu sau?';
  static const nextItemPrompt = 'Mình chuyển sang câu sau nhé.';
  static const challengeControlPrompt = 'Bạn muốn nghe lại hay dừng lại?';
  static const songControlPrompt = 'Bạn muốn nghe lại, dừng lại hay bỏ qua?';
  static const songReplay = 'Mình phát lại bài hát nhé.';
  static const songSkipped = 'Mình bỏ qua bài hát nhé.';
  static const pause = 'Mình tạm dừng nhé.';

  /// Review/import metadata. Callers still validate dynamic numbers against
  /// the owner's unlocked choices before constructing a navigation action.
  static const allowedStates = <String, List<String>>{
    'STOP_GLOBAL': ['ACTIVITY_EXCEPT_TRANSLATE'],
    'HELP': ['CURRENT_NODE'],
    'OPEN_SUBJECT': ['MAIN', 'LEARNING_ANY', 'TRANSLATE_SWITCH_CONFIRM'],
    'OPEN_VOCAB': ['MAIN', 'LEARNING_ANY', 'TRANSLATE_SWITCH_CONFIRM'],
    'OPEN_TRANSLATE': ['MAIN', 'LEARNING_ANY'],
    'TRANSLATE_CONTINUOUS': ['MAIN', 'TRANSLATE_MAIN_AFTER_STOP'],
    'STOP_TRANSLATE': ['TRANSLATE_CONTINUOUS'],
    'CONTINUE_TRANSLATE': [
      'TRANSLATE_MAIN_AFTER_STOP',
      'TRANSLATE_SWITCH_CONFIRM',
    ],
    'LEAVE_TRANSLATE': ['TRANSLATE_CONTINUOUS'],
    'SWITCH_MODULE_MENU': ['LEARNING_ANY_EXCEPT_OTHER_CONTENT_END'],
    'OPEN_PARENT': ['LEARNING_ANY', 'TRANSLATE_SWITCH_CONFIRM'],
    'OPEN_STAR': ['LEARNING_ANY', 'TRANSLATE_SWITCH_CONFIRM'],
    'OPEN_REVIEW': ['LEARNING_ANY', 'TRANSLATE_SWITCH_CONFIRM'],
    'CONTINUE_GLOBAL': ['LEARNING_ANY'],
    'GO_TO_TOPIC_SELECTION': ['SUBJECT_ANY'],
    'OTHER_CONTENT': [
      'TODAY_END',
      'PARENT_BLOCK_END',
      'PARENT_END',
      'STAR_BLOCK_END',
      'STAR_END',
      'REVIEW_BLOCK_END',
    ],
    'CONTINUE_BLOCK': [
      'PARENT_BLOCK_END',
      'STAR_BLOCK_END',
      'REVIEW_BLOCK_END',
    ],
    'REPLAY_TODAY': ['TODAY_END'],
    'REPLAY_LIST': ['PARENT_END', 'STAR_END'],
    'OTHER_TOPIC': ['TOPIC_DONE'],
    'RELEARN_TOPIC': ['TOPIC_DONE'],
    'LISTEN_AGAIN': ['CORE', 'CHALLENGE', 'REVIEW', 'TODAY', 'PARENT', 'STAR'],
    'PREVIOUS_ITEM': ['CORE', 'VOCAB_REVIEW', 'TODAY', 'PARENT', 'STAR'],
    'NEXT_ITEM': [
      'CORE',
      'VOCAB_REVIEW',
      'TODAY_AFTER_EN_VN',
      'PARENT',
      'STAR',
    ],
    'SKIP_ITEM': ['CORE', 'PARENT', 'STAR'],
    'SKIP_SONG': ['SONG_PLAYING'],
    'REPLAY_SONG': ['SONG_PLAYING'],
    'RESUME_ACTIVITY': ['ACTIVE_RESUME'],
    'NEXT_LESSON': ['LESSON_END'],
    'RELEARN_LESSON': ['LESSON_END'],
    'NEXT_LEVEL': ['LEVEL_END'],
  };

  static const Map<String, List<String>> phrases = {
    'NEXT_LESSON': [
      'Học bài tiếp',
      'Bài sau',
      'Bài tiếp',
      'Bài tiếp theo',
      'Qua Bài mới',
      'Mình muốn học Bài sau',
      'Tiếp tục với Bài tiếp',
      'Tiếp tục',
      'Tiếp theo',
      'Tiếp đi',
    ],
    'RELEARN_LESSON': [
      'Học lại',
      'Học lại Bài này',
      'Bài này',
      'Mở lại bài này',
      'Bắt đầu lại Bài này',
      'Cho mình học lại từ đầu Bài',
      'Quay về đầu Bài',
      'Quay về bắt đầu',
      'Quay về từ đầu',
    ],
    'NEXT_LEVEL': [
      'Mở khóa',
      'Học Level tiếp theo',
      'Mình muốn sang Level mới',
      'Mở Level tiếp theo',
      'Tiếp tục Level mới',
    ],
    'STOP_GLOBAL': [
      'Dừng lại',
      'Mình muốn dừng',
      'Tạm dừng nhé',
      'Cho mình nghỉ một chút',
      'Thôi, mình không học nữa',
      'Dừng ở đây nhé',
      'Stop',
      'Sì tóp',
    ],
    'HELP': [
      'Giúp mình với',
      'Mình phải làm gì',
      'Tiếp theo làm gì',
      'Mình chưa hiểu',
      'Bạn chỉ mình nhé',
      'Giờ mình nói gì',
      'Phải nói gì',
      'Nói gì',
      'Nói gì tiếp',
      'Mình nói gì',
      'Phải làm sao',
    ],
    'OPEN_SUBJECT': [
      'Chuyển sang Chủ đề',
      'Chuyển sang học Chủ đề',
      'Chủ đề',
      'Học theo Chủ đề',
      'Mình muốn học Chủ đề',
      'Vào phần Chủ đề',
      'Cho mình học bài',
      'Mở bài học Chủ đề',
      'Bắt đầu học Chủ đề',
      'Học Chủ đề',
      'Vào học Chủ đề',
      'Mở phần Chủ đề',
      'Chủ đề đi',
    ],
    'OPEN_VOCAB': [
      'Chuyển sang Bộ từ vựng',
      'Chuyển sang từ vựng',
      'Học Bộ từ vựng',
      'Mình muốn học từ vựng',
      'Vào Bộ từ vựng',
      'Mở phần từ vựng',
      'Cho mình học Bộ từ vựng',
      'Học từ vựng nhé',
      'Bộ từ vựng',
      'Từ vựng',
      'Học từ vựng',
      'Từ',
      'Vào học Từ vựng',
      'Vào học Bộ từ vựng',
      'Bộ từ vựng đi',
    ],
    'OPEN_TRANSLATE': [
      'Chuyển sang Dịch',
      'Chuyển sang Dịch tiếng Anh',
      'Dịch sang tiếng Anh',
      'Mình muốn dịch',
      'Dịch giúp mình',
      'Mở phần dịch',
      'Nói tiếng Anh giúp mình',
      'Cho mình dịch câu này',
      'Dịch',
      'Dịch tiếng Anh',
      'Cho mình dịch',
      'Vào phần Dịch',
      'Vào phần dịch tiếng Anh',
      'Dịch câu',
      'Học dịch đi',
      'Phiên dịch',
    ],
    'TRANSLATE_CONTINUOUS': [
      'Dịch liên tục',
      'Dịch nhiều câu',
      'Mình muốn dịch liên tiếp',
      'Mở dịch liên tục',
      'Dịch từng câu giúp mình',
      'Cho mình nói nhiều câu',
      'Dịch tiếp nhiều câu',
      'Dịch từng câu liên tiếp',
    ],
    'CONTINUE_TRANSLATE': [
      'Dịch',
      'Tiếp tục',
      'Tiếp tục dịch',
      'Tiếp tục dịch tiếng Anh',
      'Dịch tiếp',
      'Dịch tiếng Anh',
      'Mình muốn dịch tiếp',
    ],
    'LEAVE_TRANSLATE': [
      'Mình muốn học phần khác',
      'Cho mình học Chủ đề',
      'Chuyển sang Bộ từ vựng',
      'Mình muốn làm việc khác',
      'Đổi sang phần khác',
      'Gọi HOMI giúp mình',
      'Học phần khác',
      'Học cái khác',
      'Mình muốn học cái khác',
      'Cái khác',
    ],
    'SWITCH_MODULE_MENU': [
      'Học nội dung khác',
      'Mình muốn học nội dung khác',
      'Học phần khác',
      'Học phần khác',
      'Đổi phần khác',
      'Chuyển sang phần khác',
      'Mình muốn học cái khác',
      'Học cái khác',
      'Cái khác',
      'Mở phần khác',
      'Cho mình chọn phần khác',
    ],
    'OPEN_PARENT': [
      'Ba mẹ đã thêm',
      'phần Ba mẹ đã thêm',
      'Học phần Ba mẹ đã thêm',
      'Mở nội dung ba mẹ thêm',
      'Mình muốn nghe nội dung ba mẹ thêm',
      'Cho mình vào Ba mẹ đã thêm',
      'Nghe phần Ba mẹ đã thêm',
      'Ba mẹ',
      'Đã thêm',
      'Vào học Ba mẹ thêm',
      'Ba mẹ thêm',
    ],
    'OPEN_STAR': [
      'Ngôi sao',
      'Học phần Ngôi sao',
      'Mở Ngôi sao',
      'Mình muốn nghe Ngôi sao',
      'Cho mình xem Ngôi sao',
      'Nghe các Ngôi sao của mình',
      'Star',
      'Học Ngôi sao',
      'Ngôi sao đi',
      'Ngôi sao nha',
      'Vào học ngôi sao',
    ],
    'OPEN_REVIEW': [
      'Luyện lại',
      'Học phần Luyện lại',
      'Mở Luyện lại',
      'Mình muốn luyện lại',
      'Cho mình ôn lại',
      'Luyện các câu chưa đạt',
      'Vào học Luyện lại',
      'Học luyện lại',
    ],
    'OTHER_CONTENT': [
      'Khác',
      'Nội dung khác',
      'Cái khác',
      'Chọn cái khác',
      'Chọn nội dung khác',
      'Mở nội dung khác',
      'Học nội dung khác',
      'Mình muốn học phần khác',
      'Chuyển sang nội dung khác',
      'Cho mình chọn phần khác',
      'Mở phần khác nhé',
      'Mình muốn đổi nội dung',
      'Học cái khác',
      'Cái khác đi',
    ],
    'CONTINUE_BLOCK': [
      'Học tiếp',
      'Tiếp tục',
      'Mình muốn nghe tiếp',
      'Cho mình học tiếp',
      'Mở phần tiếp theo',
      'Tiếp tục phần này',
      'Chọn Học tiếp',
      'Tiếp theo',
      'Tiếp tục đi',
      'Học nữa',
      'Nữa đi',
      'Cái tiếp theo',
    ],
    'REPLAY_TODAY': [
      'Học lại',
      'Nghe lại',
      'Nghe lại từ đầu',
      'Học lại Danh sách',
      'Học lại Hôm nay',
      'Cho mình nghe lại',
      'Cho mình nghe danh sách',
      'Mình muốn học lại phần này',
      'Phát lại từ câu đầu',
      'Nghe danh sách',
      'Lại lần nữa',
    ],
    'REPLAY_LIST': [
      'Học lại',
      'Nghe lại',
      'Nghe lại từ đầu',
      'Mình muốn nghe lại tất cả',
      'Phát lại danh sách',
      'Cho mình học lại phần này',
      'Bắt đầu lại từ đầu',
      'Lại lần nữa',
      'Nghe lại tất cả',
    ],
    'OTHER_TOPIC': [
      'Chủ đề khác',
      'Chọn Chủ đề khác',
      'Học Chủ đề khác',
      'Cái khác',
      'Phần khác',
      'Mình muốn đổi Chủ đề',
      'Cho mình chọn lại Chủ đề',
      'Mở Chủ đề khác',
      'Mình học Chủ đề mới',
      'Đổi cái khác',
      'Đổi chủ đề khác',
    ],
    'RELEARN_TOPIC': [
      'Học lại',
      'Học lại Chủ đề',
      'Học lại chủ đề này',
      'Chủ đề này',
      'Bắt đầu lại Chủ đề này',
      'Cho mình học lại cả Chủ đề',
      'Học lại từ Bài 1',
      'Học Chủ đề này',
      'Học lại Bài 1',
      'Học Bài đầu tiên',
      'Học lại Bài đầu',
      'Học lại từ đầu',
      'Con muốn học lại',
    ],
    'LISTEN_AGAIN': [
      'Nghe lại',
      'Cho mình nghe lại',
      'Bạn nói lại nhé',
      'Phát lại câu này',
      'Mình muốn nghe lần nữa',
      'Lặp lại giúp mình',
    ],
    'PREVIOUS_ITEM': [
      'Câu trước',
      'Quay lại câu trước',
      'Cho mình nghe câu vừa rồi',
      'Lùi lại một câu',
      'Về câu trước nhé',
      'Mình muốn nghe lại câu trước',
      'Câu vừa rồi',
      'Câu lúc nãy',
      'Câu cũ',
    ],
    'NEXT_ITEM': [
      'Câu tiếp theo',
      'Qua câu sau',
      'Cho mình câu tiếp',
      'Sang câu kế tiếp',
      'Mình muốn nghe câu khác',
      'Tiếp câu mới nhé',
      'Câu sau',
      'Tiếp theo',
      'Câu tiếp',
      'Câu mới',
    ],
    'REPLAY_SONG': [
      'Nghe lại',
      'Cho mình nghe lại',
      'Phát lại bài hát',
      'Nghe lại bài hát',
    ],
    'SKIP_ITEM': [
      'Bỏ qua',
      'Qua phần này',
      'Mình không muốn nghe câu này',
      'Chuyển sang câu khác',
      'Bỏ câu này nhé',
      'Cho mình qua câu này',
    ],
    'SKIP_SONG': [
      'Bỏ qua',
      'Bỏ qua bài hát',
      'Qua bài này',
      'Không nghe bài này',
      'Mình không muốn nghe bài này',
      'Chuyển sang phần tiếp theo',
    ],
    'RESUME_ACTIVITY': [
      'Tiếp tục',
      'Tiếp tục học',
      'Học tiếp',
      'Tiếp',
      'Học tiếp tục',
      'Học tiếp chỗ cũ',
      'Mình muốn tiếp tục',
      'Cho mình học tiếp',
      'Tiếp tục phần đang dở',
      'Mở lại chỗ lúc trước',
      'Tiếp theo',
      'Tiếp nha',
      'Tiếp luôn',
    ],
    'CONTINUE_GLOBAL': [
      'Tiếp tục',
      'Học tiếp',
      'Tiếp tục học',
      'Mình muốn học tiếp',
      'Cho mình tiếp tục',
      'Tiếp tục nhé',
      'Làm tiếp',
      'Nghe tiếp',
    ],
    'GO_TO_TOPIC_SELECTION': [
      'Chủ đề khác',
      'Đổi Chủ đề',
      'Chọn Chủ đề khác',
      'Qua Chủ đề khác',
      'Bài khác',
      'Đổi bài',
      'Học bài khác',
      'Chọn bài khác',
      'Level khác',
      'Đổi Level',
      'Học Level khác',
      'Bài số 2',
      'Học Bài 2',
    ],
    'STOP_TRANSLATE': ['Dừng lại'],
    'WAKE_WORD': [
      'HOMI ơi',
      'Hey HOMI',
      'Bạn HOMI ơi',
      'HOMI có nghe không',
      'HOMI giúp mình',
      'HOMI nghe mình nói nhé',
      'Ê HOMI',
    ],
  };

  static bool matches(String intent, String text) {
    final normalized = normalize(text);
    return phrases[intent]?.any((phrase) => normalize(phrase) == normalized) ??
        false;
  }

  static bool legacy(String intent, String text) {
    final normalized = normalize(text);
    return HomiFallbackCatalog.childPhrasesByIntent[intent]?.any(
          (phrase) => normalize(phrase) == normalized,
        ) ??
        false;
  }

  static String normalize(String text) =>
      HomiFallbackCatalog.normalizeVietnamese(text);

  /// Translation control preserves accents: only the approved phrase, with
  /// optional casing, whitespace and punctuation, stops a translation turn.
  static bool isTranslationStop(String text) =>
      _normalizeTranslationControl(text) ==
      _normalizeTranslationControl(phrases['STOP_TRANSLATE']!.single);

  static String _normalizeTranslationControl(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
