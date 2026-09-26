import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'V4 catalog connects every target to guided practice and content checks',
    () async {
      final catalog = await AssetListeningContentRepository().load();
      final topics = catalog.groups
          .expand((group) => group.topics)
          .toList(growable: false);
      final lessons = topics
          .expand((topic) => topic.lessons)
          .toList(growable: false);
      final targets = lessons
          .expand((lesson) => lesson.sentences)
          .toList(growable: false);
      final challenges = lessons
          .expand((lesson) => lesson.challengeBank)
          .toList(growable: false);

      expect(catalog.groups, hasLength(5));
      expect(topics, hasLength(50));
      expect(lessons, hasLength(109));
      expect(targets, hasLength(565));
      expect(challenges, hasLength(565));
      expect(
        topics.every(
          (topic) =>
              topic.titleVi.trim().isNotEmpty &&
              topic.titleEn.trim().isNotEmpty &&
              topic.titleVi.trim() != topic.titleEn.trim(),
        ),
        isTrue,
        reason:
            'Every age group must expose distinct Vietnamese and English topic titles.',
      );
      expect(
        lessons.every(
          (lesson) =>
              lesson.titleVi.trim().isNotEmpty &&
              lesson.titleEn.trim().isNotEmpty &&
              lesson.titleVi.trim() != lesson.titleEn.trim(),
        ),
        isTrue,
        reason: 'Every released lesson must expose distinct bilingual titles.',
      );
      expect(
        lessons.where((lesson) => !lesson.usesV4Flow),
        isEmpty,
        reason: 'Every released lesson must use the V4 listen-first flow.',
      );
      expect(
        lessons.where((lesson) => !lesson.usesGuidedPractice),
        isEmpty,
        reason:
            'A V4 target must not silently fall back to the legacy manual flow.',
      );
      expect(
        lessons.every(
          (lesson) => lesson.challengeBank.length == lesson.sentences.length,
        ),
        isTrue,
        reason: 'Every Core has exactly one fixed authored Challenge.',
      );
      expect(
        targets.every(
          (target) =>
              target.id.isNotEmpty &&
              target.english.trim().isNotEmpty &&
              target.vietnamese.trim().isNotEmpty,
        ),
        isTrue,
        reason:
            'Stable target IDs and bilingual text are the recognition contract; '
            'prerecorded audio IDs are intentionally absent in the TTS-only catalog.',
      );

      for (final lesson in lessons) {
        final targetIds = lesson.sentences.map((target) => target.id).toSet();
        expect(
          lesson.challengeBank.map((challenge) => challenge.targetId).toSet(),
          targetIds,
          reason: lesson.id,
        );
        for (final challenge in lesson.challengeBank) {
          expect(challenge.id, isNotEmpty, reason: lesson.id);
          expect(challenge.prompt, isNotEmpty, reason: challenge.id);
          expect(challenge.choices, hasLength(2), reason: challenge.id);
          expect(
            challenge.choices,
            contains(challenge.correctAnswer),
            reason: challenge.id,
          );
          expect(targetIds, contains(challenge.targetId), reason: challenge.id);
        }
      }

      for (final group in catalog.groups) {
        expect(
          group.levels,
          hasLength(3),
          reason: '${group.startAge}-${group.endAge}',
        );
        for (final level in group.levels) {
          expect(level.missionBank, isEmpty, reason: level.id);
        }
      }

      final entries = lessons
          .map((lesson) => lesson.entry)
          .whereType<ListeningLessonEntry>()
          .toList(growable: false);
      expect(
        entries
            .where((entry) => entry.kind == ListeningLessonEntryKind.hook)
            .length,
        18,
      );
      expect(
        entries
            .where(
              (entry) => entry.kind == ListeningLessonEntryKind.microObjective,
            )
            .length,
        91,
      );

      final alphabet = lessons.singleWhere(
        (lesson) => lesson.id == 'c35-l1-t01-b01',
      );
      expect(alphabet.titleVi, 'Các chữ cái từ A đến E');
      expect(alphabet.titleEn, 'A to E Letters');
      expect(
        alphabet.sentences.every(
          (target) =>
              !target.requiresAllExpectedTokens &&
              target.recognitionVariants.contains(
                target.english.replaceFirst(RegExp(r'^[A-Z]\.\s*'), ''),
              ),
        ),
        isTrue,
        reason:
            'Alphabet Core accepts both letter + keyword and keyword-only speech.',
      );
    },
  );

  test('redesign keeps songs and removes role plays', () async {
    final catalog = await AssetListeningContentRepository().load();
    final topics = catalog.groups
        .expand((group) => group.topics)
        .toList(growable: false);
    final lessons = topics
        .expand((topic) => topic.lessons)
        .toList(growable: false);
    final songs = {
      for (final lesson in lessons)
        if (lesson.songTitle != null) lesson.id: lesson.songTitle,
    };
    const expectedSongs = <String, String>{
      'c35-l1-t02-b03': 'Count with Me',
      'c35-l3-t09-b02': 'What Should I Wear?',
      'c35-l3-t10-b02': 'My Happy Day',
      'c67-l3-t08-b01': "Let's Play Together",
      'c810-l1-t01-b02': 'My Busy Day',
    };
    expect(songs, expectedSongs);
    expect(
      topics.expand((topic) => topic.songs),
      isEmpty,
      reason:
          'V4 song milestones live on their authored lesson; this test must not '
          'require legacy, bundled song clips while TTS media is pending.',
    );

    final rolePlayLessons = lessons
        .where((lesson) => lesson.rolePlay != null)
        .toList(growable: false);
    expect(rolePlayLessons, isEmpty);
  });
}
