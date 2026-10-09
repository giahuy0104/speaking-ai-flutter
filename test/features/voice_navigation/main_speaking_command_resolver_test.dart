import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_command_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = MainSpeakingCommandResolver();

  test('learning requests remain translation content', () {
    for (final text in <String>[
      'Còn cái gì khác để học không?',
      'Có gì khác không?',
      'Con muốn học cái khác',
      'Con muốn học thứ khác',
      'Cho con học bài khác',
    ]) {
      expect(resolver.resolve(text), isNull, reason: text);
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

  test('module requests remain translation content', () {
    for (final text in [
      'Bộ từ vựng',
      'Học Bộ từ vựng',
      'Mình muốn học từ vựng',
      'Chủ đề',
      'Học Chủ đề',
      'Chuyển sang Chủ đề',
      'Chuyển sang Bộ từ vựng',
      'Ba mẹ đã thêm',
      'Ngôi sao',
      'Luyện lại',
      'Tôi nhìn thấy ngôi sao',
      'Ba mẹ đã thêm một câu cho tôi',
      'Tôi muốn luyện lại đoạn văn',
    ]) {
      expect(resolver.resolve(text), isNull, reason: text);
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
