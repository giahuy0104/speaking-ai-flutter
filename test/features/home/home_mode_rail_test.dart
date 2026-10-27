import 'dart:ui' as ui;

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_mode_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRail(
    WidgetTester tester, {
    HomeRailEdge edge = HomeRailEdge.left,
    String label = 'Từ vựng',
    double textScale = 1,
    bool reduceMotion = false,
    required VoidCallback onPressed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 568),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: Align(
              alignment: edge == HomeRailEdge.left
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: HomeModeRail(
                edge: edge,
                label: label,
                icon: Icons.menu_book_rounded,
                color: AppColors.primaryNavy,
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Transform pressTransform(WidgetTester tester) => tester.widget<Transform>(
    find.byKey(const Key('home-cloud-press-transform')),
  );

  testWidgets('rotates whole labels and keeps a readable accessible button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final edge in HomeRailEdge.values) {
      for (final label in ['Từ vựng', 'Chủ đề', '词汇', '主题']) {
        await pumpRail(
          tester,
          edge: edge,
          label: label,
          textScale: 2,
          onPressed: () {},
        );
        final button = find.byType(HomeModeRail);
        final rect = tester.getRect(button);
        expect(rect.width, inInclusiveRange(60, 68));
        expect(rect.height, 210);
        expect(
          tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
          edge == HomeRailEdge.left ? 3 : 1,
        );
        final text = tester.widget<Text>(
          find.byKey(const Key('home-mode-rail-label')),
        );
        expect(text.data, label);
        expect(text.maxLines, 1);
        expect(text.softWrap, isFalse);
        final semantics = tester.getSemantics(button).getSemanticsData();
        expect(semantics.label, label);
        expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(tester.takeException(), isNull);
      }
    }
    handle.dispose();
  });

  testWidgets('press grows inward without moving the target and opens once', (
    tester,
  ) async {
    var calls = 0;
    await pumpRail(tester, onPressed: () => calls++);
    final button = find.byType(HomeModeRail);
    final original = tester.getRect(button);
    final pointer = await tester.startGesture(original.center);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 60));
    expect(pressTransform(tester).transform.storage[0], greaterThan(1));
    expect(pressTransform(tester).alignment, Alignment.centerLeft);
    expect(tester.getRect(button), original);
    expect(calls, 0);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(pressTransform(tester).transform.storage[0], 1);
    expect(tester.getRect(button), original);
  });

  testWidgets('right tab grows inward; cancelled touch does not navigate', (
    tester,
  ) async {
    var calls = 0;
    await pumpRail(tester, edge: HomeRailEdge.right, onPressed: () => calls++);
    final pointer = await tester.startGesture(
      tester.getCenter(find.byType(HomeModeRail)),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 70));
    expect(pressTransform(tester).alignment, Alignment.centerRight);
    expect(pressTransform(tester).transform.storage[0], greaterThan(1));
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(pressTransform(tester).transform.storage[0], 1);
  });

  testWidgets('rapid taps coalesce while feedback is running', (tester) async {
    var calls = 0;
    await pumpRail(tester, onPressed: () => calls++);
    await tester.tap(find.byType(HomeModeRail));
    await tester.tap(find.byType(HomeModeRail));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('reduced motion opens immediately without scaling', (
    tester,
  ) async {
    var calls = 0;
    await pumpRail(tester, reduceMotion: true, onPressed: () => calls++);
    await tester.tap(find.byType(HomeModeRail));
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(pressTransform(tester).transform.storage[0], 1);
  });

  testWidgets('disposing during feedback does not open a stale destination', (
    tester,
  ) async {
    var calls = 0;
    await pumpRail(tester, onPressed: () => calls++);
    await tester.tap(find.byType(HomeModeRail));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });
}
