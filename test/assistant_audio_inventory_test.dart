import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/main_assistant_audio_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/domain/homi_fallback_catalog.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/approved_assistant_tts_fallbacks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> manifest;
  late List<Map<String, dynamic>> entries;
  late List<Map<String, dynamic>> runtimeEntries;
  setUpAll(() async {
    manifest =
        jsonDecode(
              await File(
                MainAssistantAudioPromptService.manifestAsset,
              ).readAsString(),
            )
            as Map<String, dynamic>;
    entries = (manifest['prompts'] as List).cast<Map<String, dynamic>>();
    // Match the enabled packs composed by createVoicePromptService. Each pack
    // keeps its own receipt/hash checks; coverage is a property of their union.
    runtimeEntries = [...entries];
    for (final path in [
      'assets/data/curriculum_audio.json',
      'assets/data/homi_gap66_audio.json',
    ]) {
      final pack = jsonDecode(await File(path).readAsString()) as Map;
      expect(pack['enabled'], true);
      runtimeEntries.addAll(
        (pack['prompts'] as List).cast<Map<String, dynamic>>(),
      );
    }
  });
  test(
    'fixed texts have one authored match or an explicitly approved TTS fallback',
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
      final missing = <String>{};
      for (final text in fixed.toSet()) {
        if (!runtimeEntries.any(
          (entry) =>
              entry['text'] == text ||
              (entry['lookupTexts'] as List? ?? const []).contains(text),
        )) {
          if (!approvedAssistantTtsFallbacks.contains(text)) missing.add(text);
          continue;
        }
        expect(
          runtimeEntries.where(
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
      expect(missing, isEmpty, reason: jsonEncode(missing.toList()));
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
    final missing = <String>{};
    for (final file in sources) {
      final source = file.readAsStringSync();
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(source)) {
          final text = match.group(1)!;
          if (text.contains(r'$') || text.contains('{')) continue;
          if (!runtimeEntries.any(
            (entry) =>
                entry['text'] == text ||
                (entry['lookupTexts'] as List? ?? const []).contains(text),
          )) {
            if (!approvedAssistantTtsFallbacks.contains(text)) {
              missing.add(text);
            }
            continue;
          }
          expect(
            runtimeEntries.where(
              (entry) =>
                  entry['text'] == text ||
                  (entry['lookupTexts'] as List? ?? const []).contains(text),
            ),
            hasLength(1),
            reason: '${file.path}: $text',
          );
        }
      }
    }
    expect(missing, isEmpty, reason: jsonEncode(missing.toList()));
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
          final asset = entry['asset'] as String;
          final parentDirectory = asset.substring(
            0,
            asset.lastIndexOf('/') + 1,
          );
          expect(
            pubspec.contains('    - $asset') ||
                pubspec
                    .split('\n')
                    .any((line) => line.trim() == '- $parentDirectory'),
            isTrue,
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
