import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_command_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = MainSpeakingCommandResolver();

  test('detects requests to learn something else', () {
    for (final text in <String>[
      'Còn cái gì khác để học không?',
      'Có gì khác không?',
      'Con muốn học cái khác',
      'Con muốn học thứ khác',
      'Cho con học bài khác',
    ]) {
      expect(resolver.resolve(text), MainSpeakingCommand.otherLearning);
    }
  });

  test('only the exact approved stop exits continuous translation', () {
    expect(
      resolver.resolve('DỪNG   LẠI!'),
      MainSpeakingCommand.stopTranslation,
    );
    for (final text in <String>[
      'Mình muốn dừng',
      'Dừng dịch liên tục',
      'Ngừng dịch',
      'Không dịch nữa',
      'Thoát dịch',
      'Hổng dịch nữa',
      'Dừng dịch giúp mình',
    ]) {
      expect(resolver.resolve(text), isNull, reason: text);
    }
  });

  test('whole module requests leave translation for the navigation menu', () {
    for (final text in [
      'Bộ từ vựng',
      'Học Bộ từ vựng',
      'Mình muốn học từ vựng',
      'Chủ đề',
      'Học Chủ đề',
      'Chuyển sang Chủ đề',
      'Chuyển sang Bộ từ vựng',
    ]) {
      expect(
        resolver.resolve(text),
        MainSpeakingCommand.otherLearning,
        reason: text,
      );
    }
    for (final text in [
      'Từ',
      'Hôm nay mình học Bộ từ vựng ở trường',
      'Tôi muốn dịch câu học Chủ đề này',
    ]) {
      expect(resolver.resolve(text), isNull, reason: text);
    }
  });

  test('keeps unapproved non-translation stop requests out of this flow', () {
    for (final text in <String>[
      'Thoát luyện nói',
      'Con không muốn luyện nói nữa',
    ]) {
      expect(resolver.resolve(text), isNull);
    }
  });

  test('keeps ordinary speaking sentences in the translation flow', () {
    for (final text in <String>[
      'Con muốn ăn cơm',
      'Hôm nay con học ở trường',
      'Con thích một bài hát khác',
      'Tôi muốn học bài khác bằng tiếng Anh',
    ]) {
      expect(resolver.resolve(text), isNull);
    }
  });
}
