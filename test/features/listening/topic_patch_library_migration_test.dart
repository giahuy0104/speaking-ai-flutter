import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/data/lesson_recording_history_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_topic_patch_migration.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vocabularyKey = 'innotrik.vocabulary.v1';
final _time = DateTime.utc(2026, 9, 18, 10);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ListeningTopicPatchMigration patch;
  late VocabularyStore vocabulary;
  setUp(() {
    patch = ListeningTopicPatchMigration.fromJson(
      jsonDecode(
            File(
              'assets/data/listening_topic_patch_v42.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    vocabulary = VocabularyStore(topicPatchMigration: patch);
  });

  test('unknown target IDs remain outside the four-topic migration', () async {
    final synthetic = _entry(
      'synthetic-star',
      'C35-L1-T01-B01',
      'GUIDED-FLOW_S1',
    );
    final futureTarget = _entry(
      'future-star',
      'C35-L1-T01-B01',
      'C35-L1-T01-B01-T99',
    );
    final known = _entry('known-star', 'C35-L1-T01-B01', 'C35-L1-T01-B01-T06');
    await vocabulary.write([synthetic, futureTarget, known]);
    final entries = {
      for (final entry in await vocabulary.read()) entry.id: entry,
    };
    expect(entries[synthetic.id]!.toJson(), synthetic.toJson());
    expect(entries[futureTarget.id]!.toJson(), futureTarget.toJson());
    expect(entries[known.id]!.sourceLessonCode, 'C35-L1-T01-B02');

    final directory = await Directory.systemTemp.createTemp(
      'unknown-target-recordings-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final history = LessonRecordingHistoryStore(
      customPath: '${directory.path}/history.json',
      topicPatchMigration: patch,
    );
    final recording = _recording(
      'synthetic',
      'c35-l1-t01-b01',
      'GUIDED-FLOW_S1',
      1,
    );
    final futureRecording = _recording(
      'future',
      'c35-l1-t01-b01',
      'C35-L1-T01-B01-T99',
      99,
    );
    await history.addSuccessful(recording);
    await history.addSuccessful(futureRecording);
    await history.addSuccessful(
      _recording('known', 'c35-l1-t01-b01', 'C35-L1-T01-B01-T06', 6),
    );
    final recordings = {
      for (final entry in await history.readAll()) entry.id: entry,
    };
    expect(recordings[recording.id]!.toJson(), recording.toJson());
    expect(recordings[futureRecording.id]!.toJson(), futureRecording.toJson());
  });

  test(
    'default store loads the packaged patch without explicit injection',
    () async {
      await const VocabularyStore().write(<VocabularyEntry>[
        _entry('fish-star', 'C35-L1-T01-B01', 'C35-L1-T01-B01-T06'),
      ]);
      final entry = (await const VocabularyStore().read()).single;
      expect(entry.sourceLessonCode, 'C35-L1-T01-B02');
      expect(entry.id, 'fish-star');
    },
  );

  test(
    'moves Stars and review by target, preserves IDs and parent Today',
    () async {
      final star = _entry('kite-star', 'C35-L1-T01-B02', 'C35-L1-T01-B02-T02');
      final review = _entry(
        'review-six',
        'C35-L1-T02-B01',
        'C35-L1-T02-B01-T06',
        review: true,
      );
      final parent = VocabularyEntry(
        id: 'parent-today',
        word: 'Family',
        meaning: 'Gia đình',
        addedAt: _time,
        parentState: ParentVocabularyState.today,
        todayStatus: TodayVocabularyStatus.notHeard,
        originBatchId: 'unchanged-batch',
        todayDayKey: '2026-09-18',
      );
      final other = _entry(
        'other-topic',
        'C35-L1-T03-B01',
        'C35-L1-T03-B01-T01',
      );
      final today = jsonEncode(<String, Object>{
        'dayKey': '2026-09-18',
        'entryIds': <String>[parent.id],
        'createdAt': _time.toIso8601String(),
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _vocabularyKey,
        jsonEncode(
          [star, review, parent, other].map((e) => e.toJson()).toList(),
        ),
      );
      await preferences.setString('innotrik.vocabulary-today-view.v4', today);
      await preferences.setString(
        'innotrik.vocabulary-session.v1',
        'unchanged-session',
      );

      final entries = {
        for (final entry in await vocabulary.read()) entry.id: entry,
      };
      expect(entries.keys, [star.id, review.id, parent.id, other.id]);
      expect(entries[star.id]!.sourceLessonCode, 'C67-L1-T01-B01');
      expect(
        entries[star.id]!.starSlotId,
        'C67-L1-T01-B01:core:C35-L1-T01-B02-T02',
      );
      expect(entries[star.id]!.correctAudioPath, star.correctAudioPath);
      expect(entries[star.id]!.earnedAt, star.earnedAt);
      expect(entries[review.id]!.sourceLessonCode, 'C35-L1-T02-B02');
      expect(entries[parent.id]!.toJson(), parent.toJson());
      expect(entries[other.id]!.toJson(), other.toJson());
      expect(preferences.getString('innotrik.vocabulary-today-view.v4'), today);
      expect(
        preferences.getString('innotrik.vocabulary-session.v1'),
        'unchanged-session',
      );
      final encoded = preferences.getString(_vocabularyKey);
      await vocabulary.read();
      await vocabulary.write(await vocabulary.read());
      expect(preferences.getString(_vocabularyKey), encoded);

      await vocabulary.upsertLessonSentence(
        lessonCode: 'C67-L1-T01-B01',
        sentenceId: star.sourceSentenceId!,
        english: star.word,
        vietnamese: star.meaning,
        collection: VocabularyCollection.star,
        starSlotId: 'C67-L1-T01-B01:core:${star.sourceSentenceId}',
        correctAudioPath: 'new-kite.m4a',
      );
      final stars = await vocabulary.starEntries();
      expect(
        stars
            .where((e) => e.sourceSentenceId == star.sourceSentenceId)
            .single
            .id,
        star.id,
      );
      expect(stars, hasLength(2));
      await vocabulary.upsertLessonSentence(
        lessonCode: 'C35-L1-T02-B02',
        sentenceId: review.sourceSentenceId!,
        english: review.word,
        vietnamese: review.meaning,
        collection: VocabularyCollection.review,
      );
      expect((await vocabulary.reviewEntries()).single.id, review.id);
    },
  );

  test(
    'deprecated targets retain Stars but cannot generate new review',
    () async {
      final retiredStar = _entry(
        'ant-star',
        'C67-L1-T01-B01',
        'C67-L1-T01-B01-T01',
      );
      final retiredReview = _entry(
        'one-review',
        'C67-L1-T02-B01',
        'C67-L1-T02-B01-T01',
        review: true,
      );
      await vocabulary.write([retiredStar, retiredReview]);
      final entries = await vocabulary.read();
      expect(entries, hasLength(2));
      expect(entries.first.sourceLessonCode, 'LEGACY-V41:C67-L1-T01-B01');
      expect(
        entries.first.starSlotId,
        'LEGACY-V41:C67-L1-T01-B01:core:C67-L1-T01-B01-T01',
      );
      expect(
        (await vocabulary.starEntries()).single.correctAudioPath,
        retiredStar.correctAudioPath,
      );
      expect(await vocabulary.reviewEntries(), isEmpty);
      expect(VocabularyStore.isActiveReviewEntry(entries.last), isFalse);
      await vocabulary.upsertLessonSentence(
        lessonCode: 'C67-L1-T02-B01',
        sentenceId: retiredReview.sourceSentenceId!,
        english: 'One',
        vietnamese: 'Một',
        collection: VocabularyCollection.review,
      );
      expect(await vocabulary.read(), hasLength(2));
      await vocabulary.upsertLessonSentence(
        lessonCode: 'C67-L1-T01-B01',
        sentenceId: 'C35-L1-T01-B02-T02',
        english: 'K. Kite.',
        vietnamese: 'Cái diều',
        collection: VocabularyCollection.star,
        correctAudioPath: 'kite.m4a',
      );
      expect(
        (await vocabulary.starEntries()).map((e) => e.id),
        contains(retiredStar.id),
      );
      expect(await vocabulary.starEntries(), hasLength(2));
    },
  );

  test(
    'resumed Review drops retired targets and keeps moved IDs/results',
    () async {
      final retired = _entry(
        'old-ant',
        'C67-L1-T01-B01',
        'C67-L1-T01-B01-T01',
        review: true,
      );
      final retained = _entry(
        'old-kite',
        'C35-L1-T01-B02',
        'C35-L1-T01-B02-T02',
        review: true,
      );
      final unrelated = _entry(
        'other-review',
        'C35-L1-T03-B01',
        'C35-L1-T03-B01-T01',
        review: true,
      );
      await vocabulary.write([retired, retained, unrelated]);
      const sessions = VocabularySessionStore();
      await sessions.saveActive(
        VocabularyPracticeSession(
          id: 'review-before-upgrade',
          mode: VocabularyPracticeMode.review,
          entryIds: [retired.id, retained.id, unrelated.id],
          currentIndex: 1,
          results: {retired.id: false, retained.id: true},
          correctAudioPaths: {retained.id: 'preserved-kite.wav'},
          createdAt: _time,
        ),
      );

      final resumed = (await sessions.prepareReview(vocabulary))!;
      expect(resumed.id, 'review-before-upgrade');
      expect(resumed.entryIds, [retained.id, unrelated.id]);
      expect(resumed.currentIndex, 0);
      expect(resumed.results, {retained.id: true});
      expect(resumed.correctAudioPaths, {retained.id: 'preserved-kite.wav'});
      expect((await vocabulary.read()).map((e) => e.id), contains(retired.id));

      await sessions.saveActive(resumed.copyWith(entryIds: [retired.id]));
      expect(await sessions.prepareReview(vocabulary), isNull);
      expect(await sessions.readActive(), isNull);
    },
  );

  test(
    'Today reconciliation remains unchanged by retired review sources',
    () async {
      final parent = VocabularyEntry(
        id: 'parent-today',
        word: 'Apple',
        meaning: 'Táo',
        addedAt: _time,
        parentState: ParentVocabularyState.today,
        todayStatus: TodayVocabularyStatus.heard,
        todayDayKey: '2026-09-18',
        originBatchId: 'original-batch',
      );
      await vocabulary.write([
        _entry(
          'retired-review',
          'C67-L1-T01-B01',
          'C67-L1-T01-B01-T01',
          review: true,
        ),
        parent,
      ]);
      const sessions = VocabularySessionStore();
      final original = VocabularyPracticeSession(
        id: 'today-before-upgrade',
        mode: VocabularyPracticeMode.today,
        entryIds: [parent.id],
        currentIndex: 0,
        results: {parent.id: true},
        correctAudioPaths: {parent.id: 'parent.wav'},
        createdAt: _time,
        dayKey: '2026-09-18',
      );
      await sessions.saveActive(original);
      expect(
        (await sessions.prepareToday(vocabulary))!.toJson(),
        original.toJson(),
      );
    },
  );

  test(
    'all 56 retained targets canonicalize, including song and shifted Numbers',
    () async {
      final oldStars = <VocabularyEntry>[
        for (final placement in patch.placements)
          _entry(
            'star:${placement.source.targetId}',
            placement.source.lessonCode,
            placement.source.targetId,
          ),
      ];
      await vocabulary.write(oldStars);
      final actual = {
        for (final entry in await vocabulary.read()) entry.id: entry,
      };
      expect(actual, hasLength(56));
      for (final placement in patch.placements) {
        final entry = actual['star:${placement.source.targetId}']!;
        expect(entry.sourceSentenceId, placement.source.targetId);
        expect(entry.sourceLessonCode, placement.destination.lessonCode);
        expect(
          entry.starSlotId,
          '${placement.destination.lessonCode}:core:${placement.source.targetId}',
        );
      }
      final before = jsonEncode(actual.values.map((e) => e.toJson()).toList());
      await vocabulary.write(actual.values.toList());
      expect(
        jsonEncode((await vocabulary.read()).map((e) => e.toJson()).toList()),
        before,
      );
    },
  );

  test(
    'recordings follow targets and archive removed sources without file loss',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'topic-patch-recordings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/history.json');
      final moved = _recording(
        'kite',
        'c35-l1-t01-b02',
        'C35-L1-T01-B02-T02',
        2,
      );
      final song = _recording(
        'song',
        'c35-l1-t02-b02',
        'C35-L1-T02-B02-T01',
        1,
      );
      final retired = _recording(
        'ant',
        'c67-l1-t01-b01',
        'C67-L1-T01-B01-T01',
        1,
      );
      final other = _recording(
        'other',
        'c35-l1-t03-b01',
        'C35-L1-T03-B01-T01',
        1,
      );
      await file.writeAsString(
        jsonEncode(
          [moved, song, retired, other].map((e) => e.toJson()).toList(),
        ),
      );
      final store = LessonRecordingHistoryStore(
        customPath: file.path,
        topicPatchMigration: patch,
      );
      final entries = {
        for (final entry in await store.readAll()) entry.id: entry,
      };
      expect(entries, hasLength(4));
      expect(entries[moved.id]!.lessonId, 'c67-l1-t01-b01');
      expect(entries[moved.id]!.sentenceNumber, 1);
      expect(entries[moved.id]!.filePath, moved.filePath);
      expect(entries[moved.id]!.curriculumVersion, 42);
      expect(entries[song.id]!.lessonId, 'c35-l1-t02-b03');
      expect(entries[retired.id]!.lessonId, 'legacy-v41:c67-l1-t01-b01');
      expect(entries[retired.id]!.filePath, retired.filePath);
      expect(entries[other.id]!.toJson(), other.toJson());
      final before = file.readAsStringSync();
      await store.readAll();
      expect(file.readAsStringSync(), before);
      expect(
        (await store.readForSentence(
          'c67-l1-t01-b01',
          moved.sentenceId,
        )).single.id,
        moved.id,
      );
      expect(
        await store.readForSentence('c67-l1-t01-b01', retired.sentenceId),
        isEmpty,
      );
      expect(
        await store.addSuccessful(
          _recording('kite-new', moved.lessonId, moved.sentenceId, 2),
        ),
        isEmpty,
      );
      expect(
        await store.readForSentence('c67-l1-t01-b01', moved.sentenceId),
        hasLength(2),
      );
      final removed = await store.removeLesson('c67-l1-t01-b01');
      expect(removed, contains(moved.filePath));
      expect(removed, isNot(contains(retired.filePath)));
      expect((await store.readAll()).map((e) => e.id), contains(retired.id));
    },
  );
}

VocabularyEntry _entry(
  String id,
  String code,
  String target, {
  bool review = false,
}) => VocabularyEntry(
  id: id,
  word: target,
  meaning: 'Nghĩa của $target',
  addedAt: _time,
  source: VocabularySource.topicCore,
  sourceLessonCode: code,
  sourceSentenceId: target,
  collection: review ? VocabularyCollection.review : VocabularyCollection.star,
  status: review
      ? VocabularyLearningStatus.needsPractice
      : VocabularyLearningStatus.learnedWell,
  starSlotId: review ? null : '$code:core:$target',
  correctAudioPath: review ? null : '$id.m4a',
  earnedAt: review ? null : _time,
);

LessonRecordingHistoryEntry _recording(
  String id,
  String lesson,
  String target,
  int number,
) => LessonRecordingHistoryEntry(
  id: id,
  lessonId: lesson,
  lessonTitle: 'Old title',
  sentenceId: target,
  sentenceNumber: number,
  english: target,
  vietnamese: 'Nghĩa của $target',
  filePath: '$id.m4a',
  duration: const Duration(seconds: 2),
  createdAt: _time,
);
