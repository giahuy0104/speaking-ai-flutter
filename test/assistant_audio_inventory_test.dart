import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowedAudioPaths = <String>{
  'assets/audio/A-6-7/SONGS/A067_T05_SONG01_FULL_EN.mp3',
  'assets/audio/A-6-7/SONGS/A067_T07_SONG01_FULL_EN.mp3',
  'assets/audio/A-6-7/SONGS/A067_T08_SONG01_FULL_EN.mp3',
  'assets/audio/A-8-10/SONGS/A0810_T03_SONG01_FULL_EN.mp3',
  'assets/audio/A-8-10/SONGS/A0810_T04_SONG01_FULL_EN.mp3',
  'assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3',
  'assets/audio/MAIN/SFX_STAR_TING.mp3',
};

const _listeningSentenceManifestPaths = <String>[
  'assets/data/listening_3_5_audio.json',
  'assets/data/listening_6_7_audio.json',
  'assets/data/listening_8_10_audio.json',
  'assets/data/listening_11_12_audio.json',
  'assets/data/listening_13_15_audio.json',
];

const _challengeManifestPaths = <String>[
  'assets/data/challenge_3_5_audio.json',
  'assets/data/challenge_6_7_audio.json',
  'assets/data/challenge_8_10_audio.json',
  'assets/data/challenge_11_12_audio.json',
  'assets/data/challenge_13_15_audio.json',
];

const _removedAuthoredFields = <String>{
  'audioUrl',
  'vietnameseAudioUrl',
  'introAudioUrl',
  'combinedHookAudioUrl',
  'outroAudioUrl',
  'fullAudioUrl',
  'dialogueTransitionAudioUrl',
  'englishAudioId',
  'vietnameseAudioId',
  'fullAudioId',
  'dialogueTransitionAudioId',
};

Iterable<MapEntry<String, Object?>> _entries(Object? value) sync* {
  if (value is List) {
    for (final item in value) {
      yield* _entries(item);
    }
  } else if (value is Map) {
    for (final entry in value.entries) {
      yield MapEntry(entry.key.toString(), entry.value);
      yield* _entries(entry.value);
    }
  }
}

void main() {
  test(
    'repository keeps approved media plus assistant-core and GAP66 packs',
    () async {
      final actual = Directory('assets/audio')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp3'))
          .map((file) => file.path.replaceAll(r'\', '/'))
          .toSet();

      final manifest =
          jsonDecode(
                await File(
                  'assets/data/assistant_core_audio.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final assistantCorePaths = (manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((entry) => entry['asset'] as String)
          .toSet();
      final gap66Manifest =
          jsonDecode(
                await File('assets/data/homi_gap66_audio.json').readAsString(),
              )
              as Map<String, dynamic>;
      final gap66Paths = (gap66Manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((entry) => entry['asset'] as String)
          .toSet();
      final listeningManifest =
          jsonDecode(
                await File(
                  'assets/data/listening_common_audio.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final listeningCommonPaths =
          (listeningManifest['prompts'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((entry) => entry['asset'] as String)
              .toSet();
      final vocabularyManifest =
          jsonDecode(
                await File(
                  'assets/data/vocabulary_common_audio.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final vocabularyCommonPaths =
          (vocabularyManifest['prompts'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((entry) => entry['asset'] as String)
              .toSet();
      final mediaManifests = await Future.wait(
        <String>[
          'assets/data/songs_audio.json',
          'assets/data/system_sfx_audio.json',
        ].map(
          (path) async =>
              jsonDecode(await File(path).readAsString())
                  as Map<String, dynamic>,
        ),
      );
      final mediaPaths = mediaManifests
          .expand((manifest) => manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((entry) => entry['asset'] as String)
          .toSet();
      final listeningSentenceManifests = await Future.wait(
        _listeningSentenceManifestPaths.map(
          (path) async =>
              jsonDecode(await File(path).readAsString())
                  as Map<String, dynamic>,
        ),
      );
      final listeningSentencePaths = listeningSentenceManifests
          .expand((manifest) => manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((entry) => entry['asset'] as String)
          .toSet();
      final challengeManifests = await Future.wait(
        _challengeManifestPaths.map(
          (path) async =>
              jsonDecode(await File(path).readAsString())
                  as Map<String, dynamic>,
        ),
      );
      final challengePaths = challengeManifests
          .expand((manifest) => manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((entry) => entry['asset'] as String)
          .toSet();
      expect(manifest['pack'], 'assistant-core');
      expect(listeningManifest['pack'], 'listening-common');
      expect(vocabularyManifest['pack'], 'vocabulary-common');
      expect(mediaManifests.map((manifest) => manifest['pack']), <String>[
        'songs',
        'system-sfx',
      ]);
      expect(
        listeningSentenceManifests.map((manifest) => manifest['pack']),
        <String>[
          'listening-3-5',
          'listening-6-7',
          'listening-8-10',
          'listening-11-12',
          'listening-13-15',
        ],
      );
      expect(challengeManifests.map((manifest) => manifest['pack']), <String>[
        'challenge-3-5',
        'challenge-6-7',
        'challenge-8-10',
        'challenge-11-12',
        'challenge-13-15',
      ]);
      expect(actual, {
        ..._allowedAudioPaths,
        ...assistantCorePaths,
        ...gap66Paths,
        ...listeningCommonPaths,
        ...vocabularyCommonPaths,
        ...mediaPaths,
        ...listeningSentencePaths,
        ...challengePaths,
      });
      expect(
        Directory('assets/audio')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.json')),
        isEmpty,
        reason: 'Prerecorded audio receipt sidecars must not ship.',
      );
    },
  );

  test(
    'pubspec bundles approved media, assistant-core and GAP66 independently',
    () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      expect(
        pubspec,
        contains('assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3'),
      );
      expect(pubspec, contains('assets/audio/MAIN/SFX_STAR_TING.mp3'));
      expect(pubspec, contains('assets/audio/assistant-core/'));
      expect(pubspec, contains('assets/data/assistant_core_audio.json'));
      expect(pubspec, contains('assets/audio/MAIN/GAP66/'));
      expect(pubspec, contains('assets/data/homi_gap66_audio.json'));
      expect(pubspec, contains('assets/audio/listening-common/'));
      expect(pubspec, contains('assets/data/listening_common_audio.json'));
      expect(pubspec, contains('assets/audio/vocabulary-common/'));
      expect(pubspec, contains('assets/data/vocabulary_common_audio.json'));
      expect(pubspec, contains('assets/data/vocabulary_built_in_audio.json'));
      expect(pubspec, contains('assets/data/songs_audio.json'));
      expect(pubspec, contains('assets/data/system_sfx_audio.json'));
      for (final ages in const ['3-5', '6-7', '8-10', '11-12', '13-15']) {
        expect(pubspec, contains('assets/audio/listening-$ages/'));
        expect(
          pubspec,
          contains(
            'assets/data/listening_${ages.replaceAll('-', '_')}_audio.json',
          ),
        );
        expect(pubspec, contains('assets/audio/challenge-$ages/'));
        expect(
          pubspec,
          contains(
            'assets/data/challenge_${ages.replaceAll('-', '_')}_audio.json',
          ),
        );
      }
      expect(
        pubspec,
        isNot(
          matches(RegExp(r'^\s*- assets/audio/MAIN/\s*$', multiLine: true)),
        ),
      );
      expect(
        pubspec,
        isNot(
          matches(
            RegExp(r'^\s*- assets/audio/CURRICULUM/\s*$', multiLine: true),
          ),
        ),
      );
      expect(
        pubspec,
        isNot(
          matches(
            RegExp(r'^\s*- assets/audio/LESSON_HOOKS/\s*$', multiLine: true),
          ),
        ),
      );
      for (final manifest in const [
        'main_assistant_audio.json',
        'homi_missing_audio_v1.json',
        'curriculum_audio.json',
        'listening_audio_manifest_v4.json',
        'cloudinary_audio_manifest.json',
      ]) {
        expect(pubspec, isNot(contains(manifest)), reason: manifest);
        expect(File('assets/data/$manifest').existsSync(), isFalse);
      }
    },
  );

  test(
    'lesson data contains only the five approved remote song URLs',
    () async {
      final catalog = jsonDecode(
        await File('assets/data/listening_lessons.json').readAsString(),
      );
      final entries = _entries(catalog).toList(growable: false);
      final forbidden = entries
          .where((entry) => _removedAuthoredFields.contains(entry.key))
          .map((entry) => entry.key)
          .toList(growable: false);
      expect(forbidden, isEmpty);

      final songs = entries
          .where((entry) => entry.key == 'songAudioUrl')
          .map((entry) => entry.value)
          .whereType<String>()
          .toSet();
      expect(songs, hasLength(5));
      expect(
        songs.every((url) => url.startsWith('https://res.cloudinary.com/')),
        isTrue,
      );
      expect(songs.every((url) => !url.contains('/CURRICULUM/')), isTrue);
      expect(
        entries.where((entry) => entry.key == 'songAudioId'),
        hasLength(5),
      );
    },
  );

  test('topic migration snapshot cannot regenerate authored audio', () async {
    final patch = jsonDecode(
      await File('assets/data/listening_topic_patch_v42.json').readAsString(),
    );
    final fields = _entries(patch).map((entry) => entry.key).toSet();
    expect(fields.intersection(_removedAuthoredFields), isEmpty);
  });
}
