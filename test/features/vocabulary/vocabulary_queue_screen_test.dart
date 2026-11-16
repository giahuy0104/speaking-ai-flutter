import 'package:ai_speaking_flutter_app/features/vocabulary/application/vocabulary_queue_settings.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_queue_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'renders long sentence entries in the tomorrow preview without overflow',
    (tester) async {
      const store = VocabularyStore();
      await store.addParentEntries(const <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'I like this baba.',
          vietnameseText: 'Con thích loại bánh tầm rượu và nước đường này.',
        ),
      ]);

      await tester.pumpWidget(
        DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: MaterialApp(
            home: VocabularyQueueScreen(
              store: store,
              settingsStore:
                  const SharedPreferencesVocabularyQueueSettingsStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('vocabulary-queue-tomorrow-preview')),
        findsOneWidget,
      );
    },
  );
}
