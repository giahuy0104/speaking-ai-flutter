import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_key.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_request.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_resolver.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _approvedHookAssets = <String, String>{
  'c35-l1-t02-b03': 'nghe-that-ki-nhe.mp3',
  'c35-l2-t05-b01': 'ban-doan-xem-con-gi.mp3',
  'c35-l3-t09-b02': 'mua-roi-mac-gi-nhi.mp3',
  'c35-l3-t10-b02': 'mot-ngay-moi-bat-dau-roi.mp3',
  'c67-l1-t03-b02': 'no-co-the-lam-gi-nhi.mp3',
  'c67-l3-t07-b02': 'den-gio-vao-lop-roi.mp3',
  'c67-l3-t09-b02': 'homi-dang-o-dau-nhi.mp3',
  'c810-l1-t01-b01': 'may-gio-roi-nhi.mp3',
  'c810-l1-t02-b02': 'cua-lop-dang-dong.mp3',
  'c810-l2-t05-b01': 'hom-nay-troi-the-nao.mp3',
  'c1112-l2-t06-b02': 'co-mot-tin-nhan-la.mp3',
  'c1315-l3-t07-b02': 'sap-den-gio-tau-chay.mp3',
  'c1315-l3-t08-b02': 'den-luc-goi-mon-roi.mp3',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform resolves all 13 registered scene hooks through the registry',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final catalog = await AssetListeningContentRepository(
          bundle: rootBundle,
        ).load();
        final lessons = {
          for (final group in catalog.groups)
            for (final topic in group.topics)
              for (final lesson in topic.lessons) lesson.id: lesson,
        };
        final repository = AudioPackRepository(
          bundledManifestAssets: const [
            'assets/data/listening_common_audio.json',
          ],
          cache: MemoryAudioPackCache(),
        );
        addTearDown(repository.dispose);
        final resolver = AudioPromptResolver(repository: repository);
        for (final hook in _approvedHookAssets.entries) {
          final lesson = lessons[hook.key]!;
          expect(lesson.entry!.kind, ListeningLessonEntryKind.hook);
          expect(lesson.combinedHookAudioUri, isNull);
          final request = AudioPromptRequest(
            key: AudioPromptKey(ListeningAudioKeys.lessonHook(lesson.id)),
            fallbackText: lesson.entry!.text,
            locale: 'vi-VN',
          );
          final resolved = await resolver.resolve(request);
          expect(
            resolved.source,
            AudioPromptSource.bundledAsset,
            reason: lesson.id,
          );
          expect(
            resolved.prompt!.asset,
            'assets/audio/LESSON_HOOKS/${hook.value}',
          );
          expect(resolved.bytes, isNotEmpty);
          expect(await resolver.budget(request), isNotNull);
        }

        final changedText = AudioPromptRequest(
          key: AudioPromptKey(ListeningAudioKeys.lessonHook('c35-l2-t05-b01')),
          fallbackText: 'Một lời dẫn đã thay đổi.',
          locale: 'vi-VN',
        );
        expect(
          (await resolver.resolve(changedText)).source,
          AudioPromptSource.tts,
        );
        expect(await resolver.budget(changedText), isNull);
      },
    );
  }

  test('excluded listening-common recordings retain TTS fallback', () async {
    final repository = AudioPackRepository(
      bundledManifestAssets: const ['assets/data/listening_common_audio.json'],
      cache: MemoryAudioPackCache(),
    );
    addTearDown(repository.dispose);
    final resolver = AudioPromptResolver(repository: repository);
    const excluded = {
      'listening.completion.lesson.2_to_1.vi':
          'Bạn muốn học Bài 1 hay học lại Bài 2?',
      'listening.milestone.course.vi': 'Bạn đã hoàn thành khóa học rồi!',
      'listening.milestone.level.1.vi': 'Bạn đã hoàn thành Level 1 rồi!',
      'listening.milestone.level.2.vi': 'Bạn đã hoàn thành Level 2 rồi!',
      'listening.milestone.level.3.vi': 'Bạn đã hoàn thành Level 3 rồi!',
      'listening.navigation.choose_level.vi':
          'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?',
    };
    for (final prompt in excluded.entries) {
      final request = AudioPromptRequest(
        key: AudioPromptKey(prompt.key),
        fallbackText: prompt.value,
        locale: 'vi-VN',
      );
      final resolved = await resolver.resolve(request);
      expect(resolved.source, AudioPromptSource.tts, reason: prompt.key);
      expect(resolved.bytes, isNull, reason: prompt.key);
      expect(await resolver.budget(request), isNull, reason: prompt.key);
    }
  });

  test(
    'hook provenance identifies retained and replacement recordings',
    () async {
      final manifest =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/listening_common_audio.json',
                ),
              )
              as Map<String, dynamic>;
      final hooks = (manifest['prompts'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (prompt) => (prompt['asset'] as String).startsWith(
              'assets/audio/LESSON_HOOKS/',
            ),
          );
      expect(hooks, hasLength(13));
      const receiptPath =
          'deliverables/lesson-hook-audio-import-2026-10-14.json';
      final receipt =
          jsonDecode(await File(receiptPath).readAsString())
              as Map<String, dynamic>;
      final replacements = {
        for (final entry
            in (receipt['files'] as List).cast<Map<String, dynamic>>())
          entry['asset'] as String: entry,
      };
      expect(replacements, hasLength(3));
      expect(
        hooks.where((prompt) => prompt['source'] == 'user-provided'),
        hasLength(3),
      );
      for (final hook in hooks) {
        final imported = replacements[hook['asset']];
        if (imported == null) {
          expect(
            hook['sourceCommit'],
            '4091f3fada0aec1c2bd8c23e88f7e3c22df9d924',
          );
          continue;
        }
        final audio = await rootBundle.load(hook['asset'] as String);
        final bytes = audio.buffer.asUint8List(
          audio.offsetInBytes,
          audio.lengthInBytes,
        );
        expect(hook['source'], 'user-provided');
        expect(hook['sourceCommit'], isNull);
        expect(hook['importReceipt'], receiptPath);
        expect(imported['key'], hook['key']);
        expect(imported['text'], hook['text']);
        expect(imported['sha256'], hook['sha256']);
        expect(sha256.convert(bytes).toString(), imported['sha256']);
        expect(imported['sizeBytes'], bytes.length);
        expect(imported['durationSeconds'], hook['durationSeconds']);
      }
    },
  );
}
