import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/navigation/app_navigator.dart';
import 'package:ai_speaking_flutter_app/core/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'pages enter from right and exit to right (dark: $dark)',
      (tester) async {
        late BuildContext context;
        final router = AppRouter({
          AppRouteNames.settings: AppRouteEntry<Null, Object>(
            presentation: AppRoutePresentation.page,
            builder: (_, _, _) => const Scaffold(key: Key('destination')),
          ),
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? buildDarkAppTheme() : buildAppTheme(),
            onGenerateRoute: router.onGenerateRoute,
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold();
              },
            ),
          ),
        );
        final result = const AppNavigator().pushPage<bool>(
          context,
          AppRoute<void>(
            name: AppRouteNames.settings,
            arguments: null,
            bindings: Object.new,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final page = find.byKey(const Key('destination'));
        final firstX = tester.getTopLeft(page).dx;
        expect(firstX, greaterThan(0));
        expect(firstX, lessThan(tester.view.physicalSize.width));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getTopLeft(page).dx, lessThan(firstX));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(page).dx, closeTo(0, 0.01));

        Navigator.of(context).pop(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final exitX = tester.getTopLeft(page).dx;
        expect(exitX, greaterThan(0));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getTopLeft(page).dx, greaterThan(exitX));
        await tester.pumpAndSettle();
        expect(await result, isTrue);
        expect(page, findsNothing);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'reduced motion shows the destination without horizontal movement',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(key: Key('destination')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const Key('destination'))).dx, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getTopLeft(find.byKey(const Key('destination'))).dx, 0);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
