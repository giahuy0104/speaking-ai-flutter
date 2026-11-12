import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/homi_assistant_bubble.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/homi_bubble_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bubbleKey = Key('bubble');

Widget _harness({VoidCallback? onPressed}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Colors.white),
          HomiBubbleDock(
            child: HomiAssistantBubble(
              key: _bubbleKey,
              visual: HomiBubbleVisual.idle,
              onPressed: onPressed,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HomiBubbleDock.resetSavedSpotForTest();
  });

  void useScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('starts docked at the bottom-right above bottom CTAs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_bubbleKey));
    expect(rect.right, closeTo(400 - 12, 0.5));
    expect(rect.bottom, closeTo(800 - 112, 0.5));
  });

  testWidgets('dragging snaps to the nearest edge and is remembered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(_harness(onPressed: () => taps++));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(_bubbleKey),
      const Offset(-250, -300),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(_bubbleKey));
    expect(rect.left, closeTo(12, 0.5));
    expect(rect.top, lessThan(800 - 112 - 46 - 100));
    expect(taps, 0, reason: 'a drag must not count as a tap');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('homi_bubble_dock.on_right'), isFalse);

    // When HOMI shows again it starts at the saved spot on its very first
    // frame, without a jump from the default corner.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_harness());
    expect(tester.getRect(find.byKey(_bubbleKey)).left, closeTo(12, 0.5));
  });

  testWidgets('grabbing the bubble while it settles holds it in place', (
    tester,
  ) async {
    useScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(_bubbleKey),
      const Offset(-250, -300),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 40));
    final midway = tester.getRect(find.byKey(_bubbleKey)).center;
    expect(midway.dx, greaterThan(12 + 24 + 20), reason: 'still settling');

    final gesture = await tester.startGesture(midway);
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();
    final held = tester.getRect(find.byKey(_bubbleKey)).center;
    expect((held - midway).distance, lessThan(40));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the touch target is at least 48 dp', (tester) async {
    useScreen(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(_bubbleKey));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('a short tap still activates HOMI', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_harness(onPressed: () => taps++));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_bubbleKey));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('every visual state renders with its label', (tester) async {
    for (final visual in HomiBubbleVisual.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: HomiAssistantBubble(visual: visual, label: visual.name),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(visual.name), findsOneWidget, reason: '$visual');
      expect(tester.takeException(), isNull, reason: '$visual');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
