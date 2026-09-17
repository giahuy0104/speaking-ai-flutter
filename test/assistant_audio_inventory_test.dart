import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> entries;
  setUpAll(() async {
    manifest =
        jsonDecode(
              await File(
                MainAssistantAudioPromptService.manifestAsset,
              ).readAsString(),
            )
            as Map<String, dynamic>;
    entries = (manifest['prompts'] as List).cast<Map<String, dynamic>>();
  });
  test(
    'all fixed catalog, silence and fallback texts are covered without duplicates',
    () {
      final fixed = <String>[
        ...HomiFallbackCatalog.assistantPromptById.values.where(
          (text) => !text.contains('{'),
        ),
        ...HomiFallbackCatalog.silencePromptById.values,
        ...HomiFallbackCatalog.fallbackPolicyById.values.expand(
          (policy) => [policy.firstPrompt, policy.secondPrompt],
        ),
        ...VocabularyFlowV3.fixedPrompts.map((p) => p.text),
        ...LessonGuideFlowV2.coreSpeakCues.map((p) => p.text),
        MainVoiceAssistantFlow.continuousTranslationPrompt,
        for (final age in [4, 6, 9, 11, 14])
          for (final kind in LessonFeedbackKind.values)
            ...LessonAgeFeedbackLibrary.messages(age: age, kind: kind),
      ];
      for (final text in fixed.toSet()) {
        expect(
          entries.where(
            (entry) =>
                entry['text'] == text ||
                ((entry['lookupTexts'] as List<dynamic>?) ?? const []).contains(
                  text,
                ),
          ),
          hasLength(1),
          reason: text,
        );
      }
      expect(entries.map((e) => e['text']).toSet().length, entries.length);
      final lookupKeys = entries
          .expand<String>(
            (entry) => <String>[
              entry['text'] as String,
              ...((entry['lookupTexts'] as List<dynamic>?) ?? const []).cast(),
            ],
          )
          .toList();
      expect(lookupKeys.toSet(), hasLength(lookupKeys.length));
      expect(entries.map((e) => e['id']).toSet().length, entries.length);
      expect(entries.where((e) => e['voiceLanguage'] == 'en'), hasLength(7));
    },
  );
  test('local spoken replies and guide objects are also covered', () {
    final patterns = [
      RegExp(r"spokenReply:\s*'([^']+)'"),
      RegExp(
        r"LessonGuidePrompt\(\s*audioCode:\s*'[^']+',\s*text:\s*'([^']+)'",
      ),
    ];
    final sources = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sources) {
      final source = file.readAsStringSync();
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(source)) {
          final text = match.group(1)!;
          if (text.contains(r'$') || text.contains('{')) continue;
          expect(
            entries.where((entry) => entry['text'] == text),
            hasLength(1),
            reason: '${file.path}: $text',
          );
        }
      }
    }
  });
  test(
    'every generated entry is enabled, reachable and matches its Eleven v3 receipt',
    () async {
      expect(manifest['enabled'], true);
      final pubspec = await File('pubspec.yaml').readAsString();
      for (final entry in entries) {
        expect(entry['enabled'], true, reason: entry['id'] as String);
        expect(entry['text'], isNot(matches(RegExp(r'[$\[\]{}]'))));
        final bytes = await File(entry['asset'] as String).readAsBytes();
        expect(sha256.convert(bytes).toString(), entry['sha256']);
        final remoteUrl = entry['url'];
        if (remoteUrl is String) {
          expect(
            Uri.parse(remoteUrl),
            isA<Uri>()
                .having((uri) => uri.scheme, 'scheme', 'https')
                .having((uri) => uri.host, 'host', 'res.cloudinary.com'),
          );
        } else {
          expect(
            pubspec,
            contains('    - ${entry['asset']}'),
            reason: '${entry['id']} must be bundled when it has no remote URL',
          );
        }
        final receipt =
            jsonDecode(await File('${entry['asset']}.json').readAsString())
                as Map;
        final language = entry['voiceLanguage'] as String;
        final profile = (manifest['profiles'] as Map)[language] as Map;
        expect(receipt['voiceId'], profile['voiceId']);
        expect(receipt['speed'], profile['speed']);
        expect(receipt['request']['text'], entry['text']);
        expect(receipt['request']['model_id'], 'eleven_v3');
        expect(receipt['finalSha256'], entry['sha256']);
        expect(entry['durationSeconds'], inExclusiveRange(0, 45));
      }
    },
  );
}
