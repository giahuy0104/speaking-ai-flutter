import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_fallback_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/master_navigation_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('leave translation hands the choice to navigation immediately', () {
    final flow = MainSpeakingFallbackFlow();
    for (final text in MasterNavigationContract.phrases['LEAVE_TRANSLATE']!) {
      final turn = flow.handle(text);
      expect(
        turn?.action,
        MainSpeakingFallbackAction.openOtherLearning,
        reason: text,
      );
      expect(turn?.promptText, isNull);
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

  test('help repeats translation guidance without switching module', () {
    final flow = MainSpeakingFallbackFlow();
    final help = flow.handle('Giúp mình với');
    expect(help?.action, MainSpeakingFallbackAction.resumeTranslation);
    expect(help?.promptText, MasterNavigationContract.translationIntro);
    expect(flow.handle('Hôm nay mình không hiểu bài này'), isNull);
  });
}
