import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/active_listening_session_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round-trips the active lesson route checkpoint', () async {
    const store = ActiveListeningSessionStore();

    await store.save(childAge: 8, topicNumber: 3, lessonNumber: 2);
    final checkpoint = await store.read();

    expect(checkpoint, isNotNull);
    expect(checkpoint?.childAge, 8);
    expect(checkpoint?.topicNumber, 3);
    expect(checkpoint?.lessonNumber, 2);
    expect(checkpoint?.updatedAtEpochMs, greaterThan(0));
  });

  test(
    'clear prevents a completed or exited route from being restored',
    () async {
      const store = ActiveListeningSessionStore();
      await store.save(childAge: 11, topicNumber: 4, lessonNumber: 1);

      await store.clear();

      expect(await store.read(), isNull);
    },
  );

  test('ignores a malformed checkpoint', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'active-listening-session-v1',
      '{"childAge":0,"topicNumber":2}',
    );

    expect(await const ActiveListeningSessionStore().read(), isNull);
  });

  Future<ActiveListeningSessionStore> legacySession({
    required int age,
    required int topic,
    required int lesson,
    Map<String, int> progress = const {},
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'topic-patch-resume-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/progress.json');
    await file.writeAsString(jsonEncode(progress));
    await (await SharedPreferences.getInstance()).setString(
      'active-listening-session-v1',
      jsonEncode({
        'childAge': age,
        'topicNumber': topic,
        'lessonNumber': lesson,
        'updatedAtEpochMs': 123,
      }),
    );
    return ActiveListeningSessionStore(
      progressStore: ListeningProgressStore(progressFilePath: file.path),
    );
  }

  test('Count With Me resumes as lesson three exactly once', () async {
    final store = await legacySession(
      age: 5,
      topic: 2,
      lesson: 2,
      progress: {'c35-l1-t02-b02::current-sentence': 4},
    );
    final migrated = await store.read();
    expect(migrated?.childAge, 5);
    expect(migrated?.lessonNumber, 3);
    expect(migrated?.updatedAtEpochMs, 123);
    expect((await store.read())?.lessonNumber, 3);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'active-listening-session-before-topic-patch-v42',
      ),
      contains('"lessonNumber":2'),
    );
  });

  test(
    'split lesson resumes in the destination of its current target',
    () async {
      final store = await legacySession(
        age: 4,
        topic: 2,
        lesson: 1,
        progress: {'c35-l1-t02-b01::current-sentence': 7},
      );
      expect((await store.read())?.lessonNumber, 2);
      expect((await store.read())?.topicNumber, 2);
    },
  );

  test(
    'newly saved checkpoint is never treated as legacy Count With Me',
    () async {
      final store = await legacySession(age: 4, topic: 2, lesson: 2);
      await store.save(childAge: 4, topicNumber: 2, lessonNumber: 2);
      expect((await store.read())?.lessonNumber, 2);
    },
  );

  test(
    'removed target is archived without resuming wrong new content',
    () async {
      final store = await legacySession(age: 6, topic: 1, lesson: 1);
      expect(await store.read(), isNull);
      expect(await store.read(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'active-listening-session-before-topic-patch-v42',
        ),
        isNotNull,
      );
    },
  );

  test(
    'a target moved to six-seven never silently switches a younger course',
    () async {
      final store = await legacySession(age: 5, topic: 1, lesson: 3);
      expect(await store.read(), isNull);
    },
  );

  test(
    'unaffected legacy checkpoint remains byte-for-byte unchanged',
    () async {
      final store = await legacySession(age: 9, topic: 2, lesson: 2);
      final preferences = await SharedPreferences.getInstance();
      final original = preferences.getString('active-listening-session-v1');
      expect((await store.read())?.lessonNumber, 2);
      expect(preferences.getString('active-listening-session-v1'), original);
    },
  );

  test('migration cannot overwrite a newer navigation checkpoint', () async {
    await legacySession(age: 5, topic: 2, lesson: 2);
    final progress = _BlockedLegacyProgress();
    final store = ActiveListeningSessionStore(progressStore: progress);
    final pendingRead = store.read();
    await progress.started.future;
    await store.save(childAge: 5, topicNumber: 3, lessonNumber: 1);
    progress.result.complete({});
    expect((await pendingRead)?.topicNumber, 3);
    expect((await store.read())?.topicNumber, 3);
  });
}

class _BlockedLegacyProgress extends ListeningProgressStore {
  final started = Completer<void>();
  final result = Completer<Map<String, int>>();

  @override
  Future<Map<String, int>> readBeforeTopicPatch() {
    started.complete();
    return result.future;
  }
}
