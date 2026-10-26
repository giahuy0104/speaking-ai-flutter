import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/widgets/result_panel.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    ConversationResult? result,
    DisplayLanguage language = DisplayLanguage.vietnamese,
    double textScale = 1,
    bool dark = false,
    VoidCallback? onPlay,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? buildDarkAppTheme() : buildAppTheme(),
        home: DisplayLanguageScope(
          language: language,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 568),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 300,
                  child: ResultPanel(result: result, onPlay: onPlay ?? () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ConversationResult result({
    bool audio = true,
    String? source,
  }) => ConversationResult.fromJson(<String, dynamic>{
    'conversationId': 'bubble-test',
    'sessionId': 'session',
    'vietnameseText':
        'Một câu dài cần xuống dòng tự nhiên để cha mẹ đọc rõ trên màn hình nhỏ.',
    'englishText':
        'A long translation should remain readable without clipping, including with large text.',
    if (audio) 'audioUrl': '/result.mp3',
    'textSource': source,
  }, backendBaseUri: Uri.parse('https://example.com'));

  testWidgets('empty bubbles are localized and do not show replay', (
    tester,
  ) async {
    for (final language in DisplayLanguage.values) {
      await pumpPanel(tester, language: language);
      expect(
        find.byKey(const Key('conversation-vietnamese-bubble')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('conversation-english-bubble')),
        findsOneWidget,
      );
      expect(
        find.text(language.choose('Bản dịch sẽ hiện ở đây', '译文会显示在这里')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('conversation-replay-result')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'long results grow in both themes and replay retains its callback',
    (tester) async {
      for (final dark in [false, true]) {
        var calls = 0;
        final current = result();
        await pumpPanel(
          tester,
          result: current,
          textScale: 2,
          dark: dark,
          onPlay: () => calls++,
        );
        expect(find.text(current.vietnameseText), findsOneWidget);
        expect(find.text(current.englishText), findsOneWidget);
        final replay = find.byKey(const Key('conversation-replay-result'));
        await tester.ensureVisible(replay);
        await tester.tap(replay);
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'offline attribution remains and text-only results have no replay',
    (tester) async {
      await pumpPanel(
        tester,
        result: result(audio: false, source: 'mlkit_on_device_translation'),
      );
      expect(
        find.byKey(const Key('google-translate-attribution')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('conversation-replay-result')), findsNothing);
    },
  );

  testWidgets('shows the selected translation and can replay device speech', (
    tester,
  ) async {
    var calls = 0;
    final translated = ConversationResult.fromJson(<String, dynamic>{
      'conversationId': 'conv_ko',
      'sessionId': 'sess_ko',
      'vietnameseText': 'Con cần nước.',
      'englishText': '',
      'targetLanguage': 'ko',
      'translatedText': '물 주세요.',
      'audioSource': 'device_tts',
    }, backendBaseUri: Uri.parse('https://example.com'));
    await pumpPanel(tester, result: translated, onPlay: () => calls++);
    expect(find.text('Câu tiếng Hàn'), findsOneWidget);
    expect(find.text('물 주세요.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation-replay-result')));
    expect(calls, 1);
  });
}
