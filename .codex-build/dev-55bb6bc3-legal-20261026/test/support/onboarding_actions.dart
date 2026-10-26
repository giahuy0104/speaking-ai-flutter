import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit user actions for tests whose subject is a later onboarding step.
Future<void> confirmVisibleOnboardingChoices(WidgetTester tester) async {
  for (final key in ['startup-confirm-adult-role', 'startup-accept-legal']) {
    final checkbox = find.byKey(Key(key));
    if (checkbox.evaluate().isEmpty) continue;
    final widget = tester.widget<Widget>(checkbox);
    final checked = switch (widget) {
      Checkbox(value: final value) => value == true,
      CheckboxListTile(value: final value) => value == true,
      _ => throw StateError(
        'Unexpected onboarding checkbox: ${widget.runtimeType}',
      ),
    };
    if (!checked) {
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      if (key == 'startup-accept-legal' &&
          find
              .byKey(const Key('startup-legal-reviewed'))
              .evaluate()
              .isNotEmpty) {
        await acknowledgeVisibleLegalReview(tester);
      }
    }
  }
}

Future<void> acknowledgeVisibleLegalReview(WidgetTester tester) async {
  final confirm = find.byKey(const Key('startup-legal-reviewed'));
  for (var attempt = 0; attempt < 30; attempt++) {
    if (tester.widget<FilledButton>(confirm).onPressed != null) break;
    await tester.drag(
      find.byKey(const Key('startup-legal-scroll')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
  }
  expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  expect(find.text('Đã hiểu'), findsOneWidget);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}
