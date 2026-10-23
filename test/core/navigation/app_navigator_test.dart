import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/core/navigation/app_navigator.dart';
import 'package:ai_speaking_flutter_app/core/navigation/app_router.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/topic_listening_arguments.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const navigator = AppNavigator();
  const arguments = TopicListeningArguments(
    language: DisplayLanguage.vietnamese,
    childAge: 6,
  );

  testWidgets(
    'named factory installs synchronously and preserves typed pop result',
    (tester) async {
      late BuildContext context;
      final observer = _Observer();
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      var exits = 0;
      var generated = 0;
      var built = false;
      var bindingsRead = false;
      final router = AppRouter({
        AppRouteNames.topicCatalog:
            AppRouteEntry<TopicListeningArguments, Object>(
              builder: (_, value, _) {
                built = true;
                expect(value, same(arguments));
                return Scaffold(body: Text('Age ${value.childAge}'));
              },
            ),
      });
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          onNavigationExit: () => exits++,
          child: MaterialApp(
            onGenerateRoute: (settings) {
              generated++;
              return router.onGenerateRoute(settings);
            },
            navigatorObservers: [observer],
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold(body: Text('Home'));
              },
            ),
          ),
        ),
      );
      Route<int>? created;
      var completed = false;
      final result = navigator.push<int>(
        context,
        AppRoute<TopicListeningArguments>(
          name: AppRouteNames.topicCatalog,
          arguments: arguments,
          bindings: () {
            bindingsRead = true;
            return Object();
          },
        ),
        onRouteCreated: (route) => created = route,
        foregroundTransitionDuration: const Duration(milliseconds: 260),
        foregroundReverseTransitionDuration: const Duration(milliseconds: 180),
        foregroundTransitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );
      result.then((_) => completed = true);
      expect(generated, 1);
      expect(created, same(observer.lastRoute));
      expect(created!.isActive, isTrue);
      expect(built, isFalse);
      expect(bindingsRead, isFalse);
      expect(created!.settings.name, AppRouteNames.topicCatalog);
      expect(created!.settings.arguments, same(arguments));
      expect(
        (created! as PageRoute).transitionDuration,
        const Duration(milliseconds: 260),
      );
      expect(
        (created! as PageRoute).reverseTransitionDuration,
        const Duration(milliseconds: 180),
      );
      await tester.pumpAndSettle();
      expect(bindingsRead, isTrue);
      expect(completed, isFalse);
      expect(find.text('Age 6'), findsOneWidget);
      Navigator.of(context).pop(42);
      await tester.pumpAndSettle();
      expect(await result, 42);
      expect(exits, 1);
      expect(find.text('Home'), findsOneWidget);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'named push and replace initialise while $platform is paused',
      (tester) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        late BuildContext rootContext;
        late BuildContext lessonContext;
        final observer = _Observer();
        final router = AppRouter({
          AppRouteNames.lessonIntro: AppRouteEntry<Null, Object>(
            builder: (context, _, _) {
              lessonContext = context;
              return const Scaffold(body: Text('Intro'));
            },
          ),
          AppRouteNames.lessonPractice: const AppRouteEntry<Null, Object>(
            builder: _practice,
          ),
        });
        await tester.pumpWidget(
          MaterialApp(
            onGenerateRoute: router.onGenerateRoute,
            navigatorObservers: [observer],
            home: Builder(
              builder: (context) {
                rootContext = context;
                return const Scaffold();
              },
            ),
          ),
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        final introClosed = navigator.push<String>(
          rootContext,
          _empty(AppRouteNames.lessonIntro),
        );
        await tester.pump();
        expect(find.text('Intro'), findsOneWidget);
        expect(
          (observer.lastRoute! as PageRoute).transitionDuration,
          Duration.zero,
        );
        final practiceClosed = navigator.replace<int, String>(
          lessonContext,
          _empty(AppRouteNames.lessonPractice),
          result: 'advanced',
        );
        await tester.pump();
        await tester.pump();
        expect(await introClosed, 'advanced');
        expect(find.text('Practice'), findsOneWidget);
        expect(observer.lastRoute!.settings.name, AppRouteNames.lessonPractice);
        expect(
          (observer.lastRoute! as PageRoute).transitionDuration,
          Duration.zero,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        Navigator.of(rootContext).pop(7);
        await tester.pumpAndSettle();
        expect(await practiceClosed, 7);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'registered sheet keeps modal semantics and Back does not exit learning',
    (tester) async {
      late BuildContext context;
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      var exits = 0;
      final observer = _Observer();
      final router = AppRouter({
        AppRouteNames.history: AppRouteEntry<Null, Object>(
          presentation: AppRoutePresentation.bottomSheet,
          builder: (_, _, _) =>
              const SizedBox(height: 180, child: Text('History')),
        ),
      });
      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          onNavigationExit: () => exits++,
          child: MaterialApp(
            onGenerateRoute: router.onGenerateRoute,
            navigatorObservers: [observer],
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      final closed = navigator.showSheet<bool>(
        context,
        _empty(AppRouteNames.history),
      );
      await tester.pumpAndSettle();
      final route = observer.lastRoute! as ModalBottomSheetRoute<bool>;
      expect(route.settings.name, AppRouteNames.history);
      expect(route.isScrollControlled, isTrue);
      expect(route.useSafeArea, isTrue);
      expect(route.showDragHandle, isTrue);
      expect(route.barrierLabel, MaterialLocalizations.of(context).scrimLabel);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await closed, isNull);
      expect(exits, 0);
    },
  );

  testWidgets('regular page returns a result without ending active learning', (
    tester,
  ) async {
    late BuildContext context;
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    var exits = 0;
    final router = AppRouter({
      AppRouteNames.settings: AppRouteEntry<Null, Object>(
        presentation: AppRoutePresentation.page,
        builder: (_, _, _) => const Scaffold(body: Text('Settings')),
      ),
    });
    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        onNavigationExit: () => exits++,
        child: MaterialApp(
          onGenerateRoute: router.onGenerateRoute,
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    final result = navigator.pushPage<bool>(
      context,
      _empty(AppRouteNames.settings),
    );
    await tester.pumpAndSettle();
    Navigator.of(context).pop(true);
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(exits, 0);
  });

  testWidgets(
    'nested stack uses its registry and preserves unnamed continuation identity',
    (tester) async {
      const adapter = AppNavigator();
      final root = _Observer();
      final nested = _Observer();
      late BuildContext context;
      var generated = 0;
      final router = AppRouter({
        AppRouteNames.learningContinuation:
            AppRouteEntry<Null, LearningContinuationBindings>(
              unnamed: true,
              builder: (context, _, bindings) => bindings.builder(context),
            ),
      });
      await tester.pumpWidget(
        AppNavigationScope(
          navigator: adapter,
          child: MaterialApp(
            navigatorObservers: [root],
            home: Navigator(
              observers: [nested],
              onGenerateRoute: (settings) {
                if (settings.name == '/') {
                  return MaterialPageRoute<void>(
                    builder: (value) {
                      context = value;
                      return const Scaffold();
                    },
                  );
                }
                generated++;
                return router.onGenerateRoute(settings);
              },
            ),
          ),
        ),
      );
      final originalRoot = root.lastRoute;
      expect(AppNavigator.of(context), same(adapter));
      AppNavigator.of(context).replaceLearningContinuation<void, void>(
        context,
        (_) => const Scaffold(body: Text('Continuation')),
      );
      await tester.pumpAndSettle();
      expect(generated, 1);
      expect(root.lastRoute, same(originalRoot));
      expect(nested.lastRoute!.settings.name, isNull);
      expect(find.text('Continuation'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown routes and invalid requests fail before changing the stack',
    (tester) async {
      late BuildContext context;
      final observer = _Observer();
      final router = AppRouter({
        AppRouteNames.topicCatalog:
            AppRouteEntry<TopicListeningArguments, Object>(
              builder: (_, _, _) => const Scaffold(body: Text('Topic')),
            ),
      });
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: router.onGenerateRoute,
          navigatorObservers: [observer],
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      final original = observer.lastRoute;
      expect(
        () => navigator.push<void>(context, _empty('/missing')),
        throwsFlutterError,
      );
      expect(
        () => navigator.push<void>(context, _empty(AppRouteNames.topicCatalog)),
        throwsFlutterError,
      );
      expect(
        () => Navigator.of(
          context,
        ).pushNamed(AppRouteNames.topicCatalog, arguments: arguments),
        throwsFlutterError,
      );
      expect(
        () => navigator.showSheet<void>(
          context,
          AppRoute(
            name: AppRouteNames.topicCatalog,
            arguments: arguments,
            bindings: Object.new,
          ),
        ),
        throwsFlutterError,
      );
      expect(observer.lastRoute, same(original));
      expect(find.text('Topic'), findsNothing);
    },
  );
}

AppRoute<void> _empty(String name) =>
    AppRoute<void>(name: name, arguments: null, bindings: Object.new);
Widget _practice(BuildContext context, Null arguments, Object bindings) =>
    const Scaffold(body: Text('Practice'));

class _Observer extends NavigatorObserver {
  Route<dynamic>? lastRoute;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    lastRoute = newRoute;
  }
}
