import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/conversation_settings_port.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/history_sheet.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Golden tests live in their own file: CI skips any file that uses
// matchesGoldenFile, so behaviour tests stay in history_sheet_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadGoldenFonts);

  testWidgets('empty history keeps the shared HOMI visual system', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: createAppRouter().onGenerateRoute,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(body: HistorySheet(controller: _EmptyHistory())),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HistorySheet));
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/mascot/penguin-wave.png'),
        context,
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/history-empty-390x844.png'),
    );
  });
}

class _EmptyHistory implements ConversationHistoryPort {
  @override
  DisplayLanguage get displayLanguage => DisplayLanguage.vietnamese;

  @override
  Future<List<ConversationHistoryItem>> loadHistory() async =>
      const <ConversationHistoryItem>[];

  @override
  Future<void> playHistoryItem(ConversationHistoryItem item) async {}

  @override
  Future<void> playHistoryUserAudio(ConversationHistoryItem item) async {}

  @override
  Future<void> deleteHistoryItem(ConversationHistoryItem item) async {}

  @override
  Future<void> clearHistory() async {}
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}
