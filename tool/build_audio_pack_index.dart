import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _minimumAppVersion = '1.0.8';
const _manifestPaths = <String>[
  'assets/data/assistant_core_audio.json',
  'assets/data/listening_common_audio.json',
  'assets/data/listening_3_5_audio.json',
  'assets/data/listening_6_7_audio.json',
  'assets/data/listening_8_10_audio.json',
  'assets/data/listening_11_12_audio.json',
  'assets/data/listening_13_15_audio.json',
  'assets/data/challenge_3_5_audio.json',
  'assets/data/challenge_6_7_audio.json',
  'assets/data/challenge_8_10_audio.json',
  'assets/data/challenge_11_12_audio.json',
  'assets/data/challenge_13_15_audio.json',
  'assets/data/vocabulary_common_audio.json',
  'assets/data/vocabulary_built_in_audio.json',
  'assets/data/songs_audio.json',
  'assets/data/system_sfx_audio.json',
];

Future<void> main() async {
  final sourceText = await _sourceTextByKey();
  final indexPacks = <Map<String, Object?>>[];
  final missingSourceKeys = <String>[];
  var totalEntries = 0;
  var speechEntries = 0;
  var hashedSpeechEntries = 0;
  var totalBytes = 0;

  for (final manifestPath in _manifestPaths) {
    final file = File(manifestPath);
    final manifest =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    manifest['version'] =
        (manifest['version'] as String?)?.trim().isNotEmpty == true
        ? manifest['version']
        : 'v1';
    manifest['minimumAppVersion'] = _minimumAppVersion;
    final mediaType = manifest['mediaType'] as String?;
    final requiresTextHash = mediaType != 'song' && mediaType != 'system';
    final prompts = (manifest['prompts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final uniqueAssets = <String>{};
    var packBytes = 0;
    for (final prompt in prompts) {
      totalEntries += 1;
      final key = prompt['key'] as String;
      final asset = prompt['asset'] as String?;
      if (asset != null) {
        final audio = File(asset);
        if (await audio.exists()) {
          prompt['sizeBytes'] = await audio.length();
          if (uniqueAssets.add(asset)) packBytes += await audio.length();
        }
      }
      if (requiresTextHash) {
        speechEntries += 1;
        final text = sourceText[key] ?? prompt['text'] as String?;
        if (text == null) {
          missingSourceKeys.add(key);
        } else {
          prompt['textHash'] = _textHash(text);
          hashedSpeechEntries += 1;
        }
      } else {
        prompt.remove('textHash');
      }
    }
    totalBytes += packBytes;
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    final manifestBytes = await file.readAsBytes();
    indexPacks.add(<String, Object?>{
      'pack': manifest['pack'],
      'version': manifest['version'],
      'minimumAppVersion': manifest['minimumAppVersion'],
      'manifest': manifestPath,
      'manifestSha256': sha256.convert(manifestBytes).toString(),
      'audioCount': prompts.length,
      'sizeBytes': packBytes,
      'preloadGroup': _preloadGroup(manifest['pack'] as String),
    });
  }

  final index = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'minimumAppVersion': _minimumAppVersion,
    'packs': indexPacks,
  };
  await File(
    'assets/data/audio_pack_index.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(index)}\n');

  final report = <String, Object?>{
    'generatedAt': index['generatedAt'],
    'packCount': indexPacks.length,
    'audioEntries': totalEntries,
    'uniquePackBytes': totalBytes,
    'speechEntries': speechEntries,
    'textHashCoverage': speechEntries == 0
        ? 1.0
        : hashedSpeechEntries / speechEntries,
    'missingSourceTextKeys': missingSourceKeys,
    'dynamicTtsOnly': const <String>[
      'Bản dịch tiếng Anh phát sinh từ nội dung người dùng',
      'Phản hồi hội thoại động',
      'Nội dung do phụ huynh hoặc trẻ nhập',
    ],
    'platformVerification': const <String, String>{
      'android': 'build required by CI',
      'web': 'build required by CI',
      'ios': 'not verified on Windows',
    },
    'packs': indexPacks,
  };
  final deliverables = Directory('deliverables')..createSync(recursive: true);
  await File(
    '${deliverables.path}/audio_pack_audit_report.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  await File(
    '${deliverables.path}/audio_pack_audit_report.md',
  ).writeAsString(_markdownReport(report, indexPacks));
  stdout.writeln(
    'Indexed ${indexPacks.length} packs, $totalEntries entries, '
    '${(report['textHashCoverage'] as double) * 100}% text-hash coverage.',
  );
}

Future<Map<String, String>> _sourceTextByKey() async {
  final result = <String, String>{};
  for (final script in const <String>[
    'tool/generate_assistant_core_audio.ps1',
    'tool/generate_conversation_fixed_audio.ps1',
    'tool/generate_listening_common_audio.ps1',
    'tool/generate_vocabulary_registry_audio.ps1',
  ]) {
    final source = await File(script).readAsString();
    final promptPattern = RegExp(
      r"@\{\s*key\s*=\s*'([^']+)'[^\r\n]*?text\s*=\s*'([^']*)'",
    );
    for (final match in promptPattern.allMatches(source)) {
      result[match.group(1)!] = _normalize(match.group(2)!);
    }
  }

  final fixedCatalog =
      jsonDecode(await File('tool/fixed_audio_prompts.json').readAsString())
          as Map<String, dynamic>;
  for (final prompt in (fixedCatalog['prompts'] as List<dynamic>)) {
    final item = prompt as Map<String, dynamic>;
    result[item['key'] as String] = _normalize(item['text'] as String? ?? '');
  }

  final catalog =
      jsonDecode(
            await File('assets/data/listening_lessons.json').readAsString(),
          )
          as Map<String, dynamic>;
  for (final group in (catalog['groups'] as List<dynamic>)) {
    for (final topic in (group['topics'] as List<dynamic>)) {
      for (final lesson in (topic['lessons'] as List<dynamic>)) {
        final lessonMap = lesson as Map<String, dynamic>;
        final lessonId = lessonMap['id'] as String;
        final lessonNumber = lessonMap['number'] as int;
        final beforeTitle = lessonNumber == 1
            ? 'Chủ đề ${topic['number']}. Bài đầu tiên là'
            : 'Bài này là';
        final title = _normalize(lessonMap['titleEn'] as String? ?? '');
        final entry = lessonMap['entry'] as Map<String, dynamic>?;
        final afterTitle = _normalize(
          '${entry?['text'] as String? ?? ''} Bắt đầu nhé.',
        );
        result['listening.lesson.$lessonId.intro.vi'] =
            '$beforeTitle\u0000$title\u0000$afterTitle';
        for (final sentence in (lessonMap['sentences'] as List<dynamic>)) {
          final item = sentence as Map<String, dynamic>;
          final id = item['id'] as String;
          final english = _normalize(item['english'] as String? ?? '');
          final vietnamese = _normalize(item['vietnamese'] as String? ?? '');
          result['listening.sentence.$id.en'] = english;
          result['listening.sentence.$id.vi'] = vietnamese;
          result['vocabulary.entry.$id.word.en'] = english;
          result['vocabulary.entry.$id.meaning.vi'] = vietnamese;
        }
        for (final challenge
            in (lessonMap['challengeBank'] as List<dynamic>? ?? const [])) {
          final item = challenge as Map<String, dynamic>;
          final id = item['id'] as String;
          result['listening.challenge.$id.prompt.vi'] = _normalize(
            item['prompt'] as String? ?? '',
          );
          result['listening.challenge.$id.answer.en'] = _normalize(
            item['correctAnswer'] as String? ?? '',
          );
        }
      }
    }
  }
  return result;
}

String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
String _textHash(String value) =>
    sha256.convert(utf8.encode(_normalize(value))).toString();

String _preloadGroup(String pack) {
  final age = RegExp(r'(3-5|6-7|8-10|11-12|13-15)$').firstMatch(pack);
  return age?.group(1) ?? 'shared';
}

String _markdownReport(
  Map<String, Object?> report,
  List<Map<String, Object?>> packs,
) {
  final buffer = StringBuffer()
    ..writeln('# Audio Pack Audit')
    ..writeln()
    ..writeln('- Packs: ${report['packCount']}')
    ..writeln('- Audio entries: ${report['audioEntries']}')
    ..writeln('- Unique bytes by pack: ${report['uniquePackBytes']}')
    ..writeln(
      '- Text-hash coverage: '
      '${((report['textHashCoverage'] as double) * 100).toStringAsFixed(2)}%',
    )
    ..writeln('- iOS: not verified on Windows')
    ..writeln()
    ..writeln('| Pack | Version | Audio | Bytes | Preload |')
    ..writeln('|---|---:|---:|---:|---|');
  for (final pack in packs) {
    buffer.writeln(
      '| ${pack['pack']} | ${pack['version']} | ${pack['audioCount']} | '
      '${pack['sizeBytes']} | ${pack['preloadGroup']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Dynamic content that remains TTS/backend audio')
    ..writeln()
    ..writeln('- English translations derived from user speech')
    ..writeln('- Dynamic conversation responses')
    ..writeln('- Parent/child supplied text');
  return buffer.toString();
}
