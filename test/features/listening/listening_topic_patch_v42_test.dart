import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_curriculum_flow.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> withoutCombinedHookAudio(Map<String, dynamic> topic) {
    final normalized = jsonDecode(jsonEncode(topic)) as Map<String, dynamic>;
    for (final lesson in normalized['lessons'] as List) {
      (lesson as Map<String, dynamic>).remove('combinedHookAudioUrl');
    }
    return normalized;
  }

  final raw = read('assets/data/listening_lessons.json');
  final patch = read('assets/data/listening_topic_patch_v42.json');
  final oldGroups = (patch['oldTopics'] as List).cast<Map<String, dynamic>>();
  final newGroups = (patch['newTopics'] as List).cast<Map<String, dynamic>>();
  final oldTopics = {
    for (final group in oldGroups)
      (group['topic'] as Map)['id'] as String:
          group['topic'] as Map<String, dynamic>,
  };
  final newTopics = {
    for (final group in newGroups)
      (group['topic'] as Map)['id'] as String:
          group['topic'] as Map<String, dynamic>,
  };
  final oldLessons = {
    for (final topic in oldTopics.values)
      for (final lesson in topic['lessons'] as List)
        lesson['id'] as String: lesson as Map<String, dynamic>,
  };
  final newLessons = {
    for (final topic in newTopics.values)
      for (final lesson in topic['lessons'] as List)
        lesson['id'] as String: lesson as Map<String, dynamic>,
  };
  final catalog = ListeningContentCatalog.fromJson(raw);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform bundles the same 50 topics, patched lessons and target audio',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        // An explicit bundle avoids sharing the cached catalog between platforms.
        final loaded = await AssetListeningContentRepository(
          bundle: rootBundle,
        ).load();
        List<Object?> snapshot(ListeningContentCatalog value) => [
          for (final group in value.groups)
            [
              group.startAge,
              for (final topic in group.topics)
                [
                  topic.id,
                  topic.titleVi,
                  topic.titleEn,
                  for (final lesson in topic.lessons)
                    [
                      lesson.id,
                      lesson.titleVi,
                      lesson.titleEn,
                      lesson.intro,
                      lesson.outro,
                      for (final sentence in lesson.sentences)
                        [
                          sentence.id,
                          sentence.english,
                          sentence.vietnamese,
                          sentence.audioUri.toString(),
                        ],
                      for (final question in lesson.challengeBank)
                        [
                          question.id,
                          question.prompt,
                          question.correctAnswer,
                          question.targetId,
                        ],
                    ],
                ],
            ],
        ];
        expect(snapshot(loaded), snapshot(catalog));
        expect(loaded.groups.expand((group) => group.topics), hasLength(50));
        expect(
          loaded.groups
              .expand((group) => group.topics)
              .expand((topic) => topic.lessons),
          hasLength(109),
        );
      },
    );
  }

  test('four-topic patch leaves every other topic and lesson unchanged', () {
    expect(raw['contentVersion'], '4.2');
    expect(patch['version'], 42);
    expect(oldTopics, hasLength(4));
    expect(newTopics.keys, unorderedEquals(oldTopics.keys));
    final untouched = <Map<String, dynamic>>[];
    final hashes = patch['unchangedTopicSha256'] as Map;
    for (final group in raw['groups'] as List) {
      for (final topic in group['topics'] as List) {
        if (newTopics.containsKey(topic['id'])) {
          // Combined lesson hooks were added after the v4.2 content patch and
          // are verified independently. Keep this regression guard focused on
          // every other topic and lesson field from that patch.
          expect(
            withoutCombinedHookAudio(topic as Map<String, dynamic>),
            withoutCombinedHookAudio(newTopics[topic['id']]!),
          );
        } else {
          untouched.add(topic as Map<String, dynamic>);
          expect(
            sha256
                .convert(
                  utf8.encode(jsonEncode(withoutCombinedHookAudio(topic))),
                )
                .toString(),
            hashes[topic['id']],
            reason: 'Unrelated topic ${topic['id']} was changed',
          );
        }
      }
    }
    expect(untouched, hasLength(46));
    expect(
      untouched.expand((topic) => topic['lessons'] as List),
      hasLength(98),
    );
    expect(catalog.groups, hasLength(5));
    expect(catalog.groups.expand((group) => group.levels), hasLength(15));
    final topics = catalog.groups.expand((group) => group.topics).toList();
    final lessons = topics.expand((topic) => topic.lessons).toList();
    final targets = lessons.expand((lesson) => lesson.sentences).toList();
    expect(topics, hasLength(50));
    expect(lessons, hasLength(109));
    expect(targets, hasLength(565));
    expect(targets.map((target) => target.id).toSet(), hasLength(565));
    expect(lessons.expand((lesson) => lesson.challengeBank), hasLength(565));
    expect(lessons.where((lesson) => !lesson.usesV4Flow), isEmpty);
    for (final group in catalog.groups) {
      final cards = listeningCatalogs.singleWhere(
        (item) => item.startAge == group.startAge,
      );
      for (var index = 0; index < group.topics.length; index++) {
        expect(cards.topics[index].total, group.topics[index].lessons.length);
      }
    }
  });

  test('approved lesson titles and target ranges match the Word patch', () {
    const expected = <String, Map<String, List<String>>>{
      'c35-l1-t01': {
        'A to E Letters': ['A', 'B', 'C', 'D', 'E'],
        'F to J Letters': ['F', 'G', 'H', 'I', 'J'],
      },
      'c35-l1-t02': {
        'One to Five': ['One.', 'Two.', 'Three.', 'Four.', 'Five.'],
        'Six to Ten': ['Six.', 'Seven.', 'Eight.', 'Nine.', 'Ten.'],
        'Count With Me': [
          'One clap.',
          'Two claps.',
          'Three claps.',
          'Four claps.',
          'Five claps.',
        ],
      },
      'c67-l1-t01': {
        'K to O Letters': ['K', 'L', 'M', 'N', 'O'],
        'P to T Letters': ['P', 'Q', 'R', 'S', 'T'],
        'U to Z Letters': ['U', 'V', 'W', 'X', 'Y', 'Z'],
      },
      'c67-l1-t02': {
        'Numbers 11-15': [
          'Eleven.',
          'Twelve.',
          'Thirteen.',
          'Fourteen.',
          'Fifteen.',
        ],
        'Numbers 16-20': [
          'Sixteen.',
          'Seventeen.',
          'Eighteen.',
          'Nineteen.',
          'Twenty.',
        ],
      },
    };
    for (final entry in expected.entries) {
      final topic = newTopics[entry.key]!;
      final lessons = (topic['lessons'] as List).cast<Map>();
      expect(
        lessons.take(entry.value.length).map((lesson) => lesson['titleEn']),
        orderedEquals(entry.value.keys),
      );
      for (final lesson in lessons.take(entry.value.length)) {
        final english = (lesson['sentences'] as List).map((target) {
          final value = target['english'] as String;
          return entry.key.endsWith('t01') ? value.substring(0, 1) : value;
        });
        expect(english, orderedEquals(entry.value[lesson['titleEn']]!));
      }
    }
    expect(newTopics['c67-l1-t01']!['titleEn'], 'ABC Words');
    expect(
      newTopics['c67-l1-t01']!['titleVi'],
      oldTopics['c67-l1-t01']!['titleVi'],
    );
    expect(newLessons['c67-l1-t02-b03'], oldLessons['c67-l1-t02-b03']);
  });

  test(
    'moved targets retain their identity, audio, ASR and exact challenge',
    () {
      final placements = (patch['placements'] as List).cast<Map>();
      expect(placements, hasLength(56));
      final retained = <String>{};
      for (final placement in placements) {
        final source = placement['source'] as Map;
        final destination = placement['destination'] as Map;
        final oldLesson = oldLessons[source['lessonId']]!;
        final newLesson = newLessons[destination['lessonId']]!;
        final oldTarget =
            (oldLesson['sentences'] as List)[source['sentenceIndex']];
        final newTarget =
            (newLesson['sentences'] as List)[destination['sentenceIndex']];
        expect(source['targetId'], destination['targetId']);
        expect(source['targetId'], oldTarget['id']);
        expect(newTarget, {
          ...oldTarget as Map,
          'number': (destination['sentenceIndex'] as int) + 1,
        });
        final oldChallenge = (oldLesson['challengeBank'] as List).singleWhere(
          (question) => question['targetId'] == source['targetId'],
        );
        final newChallenge = (newLesson['challengeBank'] as List).singleWhere(
          (question) => question['targetId'] == destination['targetId'],
        );
        expect(newChallenge, oldChallenge);
        expect(retained.add(source['targetId'] as String), isTrue);
      }
      final removed = (patch['removedTargetIds'] as List).cast<String>();
      expect(removed, hasLength(36));
      expect(removed.where(retained.contains), isEmpty);
      expect(
        removed.every(
          (id) =>
              id.startsWith('C67-L1-T01-') || id.startsWith('C67-L1-T02-B01-'),
        ),
        isTrue,
      );
    },
  );

  test(
    'Count With Me moves intact and changed lessons cannot play old full audio',
    () {
      final previous = oldLessons['c35-l1-t02-b02']!;
      final current = newLessons['c35-l1-t02-b03']!;
      expect(current, {
        ...previous,
        'id': 'c35-l1-t02-b03',
        'code': 'C35-L1-T02-B03',
        'number': 3,
      });
      for (final lesson in newLessons.values) {
        if (lesson['id'] == 'c35-l1-t02-b03' ||
            lesson['id'] == 'c67-l1-t02-b03') {
          continue;
        }
        expect(lesson['fullAudioUrl'], isNull, reason: lesson['id'] as String);
        expect(lesson['fullAudioId'], isNull);
        expect(lesson['songTitle'], isNull);
        expect(lesson['entry']['kind'], 'microObjective');
        expect(lesson['intro'], lesson['entry']['text']);
        if ((lesson['code'] as String).startsWith('C67-L1-T01-')) {
          expect(
            lesson['introAudioUrl'],
            oldLessons['c67-l1-t01-b01']!['introAudioUrl'],
          );
          expect(
            lesson['intro'],
            'Mình cùng học chữ cái qua những từ quen thuộc nhé.',
          );
        }
      }
    },
  );

  test(
    'exported lookup ownership follows the new lesson without deleting source audio',
    () {
      final audio = read('assets/data/listening_audio_manifest_v4.json');
      final lexicon = read('assets/data/listening_ai_lexicon_v4.json');
      final audioEntries = (audio['entries'] as List).cast<Map>();
      final lexiconEntries = (lexicon['entries'] as List).cast<Map>();
      expect(audio['contentVersion'], '4.2');
      expect(lexicon['contentVersion'], '4.2');
      bool belongsToPatch(Map entry) =>
          ['3-5', '6-7'].contains(entry['course']) &&
          [1, 2].contains(entry['topic'] ?? entry['topicNumber']);
      for (final pair in [
        (audioEntries, 'unchangedAudioEntriesSha256'),
        (lexiconEntries, 'unchangedLexiconEntriesSha256'),
      ]) {
        final unchanged = pair.$1
            .where((entry) => !belongsToPatch(entry))
            .toList();
        expect(
          sha256.convert(utf8.encode(jsonEncode(unchanged))).toString(),
          patch[pair.$2],
          reason:
              'Unrelated export content and relative order must stay intact',
        );
      }
      for (final placement in patch['placements'] as List) {
        final destination = placement['destination'] as Map;
        final target = lexiconEntries.singleWhere(
          (entry) => entry['id'] == destination['targetId'],
        );
        expect(target['lessonCode'], destination['lessonCode']);
        expect(
          target['course'],
          '${destination['startAge']}-${destination['endAge']}',
        );
        final sourceClips = audioEntries.where(
          (entry) =>
              entry['targetId'] == destination['targetId'] &&
              ['coreEnglish', 'coreVietnamese'].contains(entry['kind']),
        );
        expect(sourceClips, hasLength(2));
        expect(
          sourceClips.every(
            (clip) => clip['lessonCode'] == destination['lessonCode'],
          ),
          isTrue,
        );
      }
      for (final removed in patch['removedTargetIds'] as List) {
        expect(
          lexiconEntries.where((entry) => entry['id'] == removed),
          isEmpty,
        );
        expect(
          audioEntries.where((entry) => entry['targetId'] == removed),
          isEmpty,
        );
      }
      final sourceSong = audioEntries.singleWhere(
        (entry) => entry['audioId'] == 'C35-L1-T02-B02_SONG',
      );
      expect(sourceSong['lessonCode'], 'C35-L1-T02-B03');
      expect(
        sourceSong['sourceAudioUrl'],
        newLessons['c35-l1-t02-b03']!['songAudioUrl'],
      );
    },
  );

  test('6–7 course unlocks independently of 3–5 Alphabet completion', () {
    final group = catalog.groups.singleWhere((item) => item.startAge == 6);
    expect(
      ListeningCurriculumFlow.levelUnlocked(group, group.levels.first, {}, {}),
      isTrue,
    );
    for (final topic in group.topics.take(2)) {
      expect(ListeningCurriculumFlow.lessonUnlocked(topic, 0, {}, {}), isTrue);
      expect(ListeningCurriculumFlow.lessonUnlocked(topic, 1, {}, {}), isFalse);
    }
  });
}
