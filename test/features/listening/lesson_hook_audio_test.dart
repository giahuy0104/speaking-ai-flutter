import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_pack_repository.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_key.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_request.dart';
import 'package:ai_speaking_flutter_app/core/audio/catalog/audio_prompt_resolver.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_audio_keys.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
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
      '$platform resolves all 13 original scene hooks through the registry',
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

  test(
    'restored hook receipts identify the original committed recordings',
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
      expect(
        hooks.map((prompt) => prompt['sourceCommit']),
        everyElement('4091f3fada0aec1c2bd8c23e88f7e3c22df9d924'),
      );
    },
  );
}
