import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_fallback_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('learning requests remain translation content', () {
    final flow = MainSpeakingFallbackFlow();
    for (final text in [
      'Mình muốn học phần khác',
      'Cho mình học Chủ đề',
      'Chuyển sang Bộ từ vựng',
      'Có gì khác không?',
    ]) {
      expect(flow.canHandle(text), isFalse, reason: text);
      expect(flow.handle(text), isNull, reason: text);
      expect(flow.isAwaitingConfirmation, isFalse);
    }
    expect(flow.handle('Có'), isNull);
    expect(flow.handle('Không'), isNull);
  });

  test(
    'only exact Dừng lại exits, other stop phrases remain translation content',
    () {
      final flow = MainSpeakingFallbackFlow();
      expect(
        flow.handle(' DỪNG   LẠI! ')?.action,
        MainSpeakingFallbackAction.stopTranslation,
      );
      expect(flow.handle('Dừng lại')?.promptText, 'Đã dừng.');
      for (final text in [
        'Thôi',
        'Stop',
        'Dừng',
        'Ngừng dịch',
        'Dừng lại ở trường',
        'Mình muốn dừng',
        'Đừng lại',
        'dung lai',
      ]) {
        expect(flow.handle(text), isNull, reason: text);
      }
    },
  );

  test('help remains translation content', () {
    final flow = MainSpeakingFallbackFlow();
    expect(flow.canHandle('Giúp mình với'), isFalse);
    expect(flow.handle('Giúp mình với'), isNull);
    expect(flow.handle('Hôm nay mình không hiểu bài này'), isNull);
  });

  test('named module requests remain translation content', () {
    final flow = MainSpeakingFallbackFlow();
    for (final text in ['Học Chủ đề', 'Bộ từ vựng']) {
      expect(flow.canHandle(text), isFalse, reason: text);
      expect(flow.handle(text), isNull, reason: text);
    }
    expect(flow.canHandle('Tôi đang học Chủ đề gia đình'), isFalse);
  });
}
