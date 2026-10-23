import 'dart:async';

import 'package:ai_speaking_flutter_app/core/navigation/app_navigator.dart';
import 'package:ai_speaking_flutter_app/core/navigation/app_router.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/topic_lessons_arguments.dart';
import 'package:ai_speaking_flutter_app/core/navigation/view_arguments/topic_listening_arguments.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:ai_speaking_flutter_app/presentation/navigation/app_view_registry.dart';
import 'package:ai_speaking_flutter_app/presentation/navigation/view_bindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Build registered views without mounting them or starting audio. These checks
// protect the live Future identities that were dropped during the route merge.
Future<T> buildRegisteredView<T extends Widget>(
  WidgetTester tester,
  AppRoute<Object?> destination,
) async {
  late BuildContext caller;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          caller = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  final request = TypedAppRouteRequest<void>(
    context: caller,
    destination: destination,
    presentation: AppRoutePresentation.learningPage,
  );
  final route =
      createAppRouter().onGenerateRoute(
            RouteSettings(name: destination.name, arguments: request),
          )!
          as MaterialPageRoute<void>;
  try {
    return (route.builder(caller) as PopScope<void>).child as T;
  } finally {
    route.dispose();
  }
}

void main() {
  testWidgets('topic route preserves the pending MAIN activation gate', (
    tester,
  ) async {
    final gate = Completer<void>();
    final screen = await buildRegisteredView<TopicListeningScreen>(
      tester,
      AppRoute<TopicListeningArguments>(
        name: AppRouteNames.topicCatalog,
        arguments: const TopicListeningArguments(
          language: DisplayLanguage.vietnamese,
          childAge: 3,
        ),
        bindings: () =>
            TopicListeningBindings(initialVoiceActivationGate: gate.future),
      ),
    );
    expect(screen.initialVoiceActivationGate, same(gate.future));
    gate.complete();
  });

  testWidgets('lesson list route preserves MAIN reply and covered state', (
    tester,
  ) async {
    final catalog = await AssetListeningContentRepository().load();
    final group = catalog.groups.first;
    final reply = Completer<void>();
    final leadPrompt = Completer<void>();
    final screen = await buildRegisteredView<TopicLessonListScreen>(
      tester,
      AppRoute<TopicLessonsArguments>(
        name: AppRouteNames.topicLessons,
        arguments: TopicLessonsArguments(
          language: DisplayLanguage.vietnamese,
          startAge: group.startAge,
          endAge: group.endAge,
          topic: listeningCatalogs.first.topics.first,
          content: group.topics.first,
          initialLessonNumber: 1,
          coverUntilInitialLessonReturns: true,
        ),
        bindings: () => TopicLessonListBindings(
          initialLessonLeadPrompt: leadPrompt.future,
          initialLessonMainReply: reply.future,
        ),
      ),
    );
    expect(screen.initialLessonNumber, 1);
    expect(screen.coverUntilInitialLessonReturns, isTrue);
    expect(screen.initialLessonMainReply, same(reply.future));
    expect(screen.initialLessonLeadPrompt, same(leadPrompt.future));
    reply.complete();
    leadPrompt.complete();
  });
}
