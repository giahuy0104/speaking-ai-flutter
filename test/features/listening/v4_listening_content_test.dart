import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ListeningContentCatalog catalog;
  late List<ListeningContentAgeGroup> groups;
  late List<ListeningLevelContent> levels;
  late List<ListeningTopicContent> topics;
  late List<ListeningLessonContent> lessons;
  late List<ListeningSentenceContent> targets;

  setUpAll(() async {
    catalog = await AssetListeningContentRepository().load();
    groups = catalog.groups;
    levels = groups.expand((group) => group.levels).toList(growable: false);
    topics = groups.expand((group) => group.topics).toList(growable: false);
    lessons = topics.expand((topic) => topic.lessons).toList(growable: false);
    targets = lessons
        .expand((lesson) => lesson.sentences)
        .toList(growable: false);
  });

  group('V4 listening curriculum', () {
    test(
      'loads the approved V4 curriculum footprint through the app model',
      () {
        expect(groups, hasLength(5));
        expect(levels, hasLength(15));
        expect(topics, hasLength(50));
        expect(lessons, hasLength(109));
        expect(catalog.contentVersion, '4.2');
        expect(targets, hasLength(565));
        expect(
          lessons.expand((lesson) => lesson.challengeBank),
          hasLength(565),
        );
        expect(levels.expand((level) => level.missionBank), isEmpty);

        expect(
          groups
              .map((group) => '${group.startAge}-${group.endAge}')
              .toList(growable: false),
          orderedEquals(const <String>['3-5', '6-7', '8-10', '11-12', '13-15']),
        );
        expect(groups.every((group) => group.levels.length == 3), isTrue);
        expect(groups.every((group) => group.topics.length == 10), isTrue);
        expect(
          groups.every(
            (group) =>
                group.levels
                    .map((level) => level.topicNumbers.length)
                    .toList(growable: false)
                    .join(',') ==
                '3,3,4',
          ),
          isTrue,
        );
        expect(lessons.every((lesson) => lesson.entry != null), isTrue);
        expect(lessons.every((lesson) => lesson.usesV4Flow), isTrue);
        expect(
          lessons.every(
            (lesson) => lesson.challengeBank.length == lesson.sentences.length,
          ),
          isTrue,
        );
      },
    );

    test('does not expose audio-production cues as lesson copy', () async {
      final productionCue = RegExp(
        r'\[(?:SFX|MUSIC|BGM|AMBIENCE|AMBIENT|SOUND|AUDIO|FX)\s*:[^\]\r\n]+\]',
        caseSensitive: false,
      );

      for (final assetPath in const <String>[
        'assets/data/listening_lessons.json',
      ]) {
        final source = await rootBundle.loadString(assetPath);
        final leakedCues = productionCue
            .allMatches(source)
            .map((match) => match.group(0))
            .whereType<String>()
            .toSet();
        expect(
          leakedCues,
          isEmpty,
          reason:
              '$assetPath must keep production directions out of text shown or spoken to children.',
        );
      }
    });

    test('uses lesson text instead of prerecorded combined hooks', () {
      expect(
        lessons.where((lesson) => lesson.combinedHookAudioUri != null),
        isEmpty,
      );
      expect(lessons.every((lesson) => lesson.intro.isNotEmpty), isTrue);
    });

    test('keeps exactly one authored challenge tied to every Core target', () {
      final targetById = <String, ListeningSentenceContent>{
        for (final target in targets) target.id: target,
      };

      expect(targetById, hasLength(565));
      for (final lesson in lessons) {
        expect(lesson.challengeBank, hasLength(lesson.sentences.length));
        expect(
          lesson.challengeBank.map((item) => item.targetId).toSet(),
          lesson.sentences.map((item) => item.id).toSet(),
          reason: lesson.id,
        );
        for (final challenge in lesson.challengeBank) {
          final target = targetById[challenge.targetId];
          expect(target, isNotNull, reason: 'Unknown target: ${challenge.id}');
          expect(challenge.choices, hasLength(2), reason: challenge.id);
          expect(
            challenge.choices,
            contains(challenge.correctAnswer),
            reason: challenge.id,
          );
          final expected = target!.id.startsWith(RegExp(r'C(?:35|67)-L1-T01-'))
              ? target.english.replaceFirst(RegExp(r'^[A-Z]\.\s*'), '')
              : target.english;
          expect(
            expected,
            challenge.correctAnswer,
            reason: 'Challenge ${challenge.id} changed its authored target.',
          );
        }
      }

      expect(levels.expand((level) => level.missionBank), isEmpty);
    });

    test('removes role-play and preserves the five song placements', () async {
      final rolePlayLessons = lessons
          .where((lesson) => lesson.rolePlay != null)
          .toList(growable: false);
      final songLessons = lessons
          .where((lesson) => lesson.songTitle != null)
          .toList(growable: false);

      expect(rolePlayLessons, isEmpty);

      expect(songLessons, hasLength(5));
      expect(
        <String, String>{
          for (final lesson in songLessons) lesson.id: lesson.songTitle!,
        },
        equals(const <String, String>{
          'c35-l1-t02-b03': 'Count with Me',
          'c35-l3-t09-b02': 'What Should I Wear?',
          'c35-l3-t10-b02': 'My Happy Day',
          'c67-l3-t08-b01': "Let's Play Together",
          'c810-l1-t01-b02': 'My Busy Day',
        }),
      );
      const expectedSongPaths = <String, String>{
        'c35-l1-t02-b03': '/homi/audio/A-6-7/SONGS/A067_T05_SONG01_FULL_EN.mp3',
        'c35-l3-t09-b02': '/homi/audio/A-6-7/SONGS/A067_T08_SONG01_FULL_EN.mp3',
        'c35-l3-t10-b02': '/homi/audio/A-6-7/SONGS/A067_T07_SONG01_FULL_EN.mp3',
        'c67-l3-t08-b01':
            '/homi/audio/A-8-10/SONGS/A0810_T04_SONG01_FULL_EN.mp3',
        'c810-l1-t01-b02':
            '/homi/audio/A-8-10/SONGS/A0810_T03_SONG01_FULL_EN.mp3',
      };
      for (final lesson in songLessons) {
        expect(lesson.hasV4SongStage, isTrue, reason: lesson.id);
        expect(
          lesson.songAudioId,
          lesson.id == 'c35-l1-t02-b03'
              ? 'C35-L1-T02-B02_SONG'
              : '${lesson.code}_SONG',
          reason: lesson.id,
        );
        expect(lesson.fullAudioUri, isNull, reason: lesson.id);
        final uri = lesson.songAudioUri!;
        expect(uri.scheme, 'https', reason: lesson.id);
        expect(uri.host, 'res.cloudinary.com', reason: lesson.id);
        expect(
          uri.path,
          endsWith(expectedSongPaths[lesson.id]!),
          reason: lesson.id,
        );
      }
    });
  });
}
