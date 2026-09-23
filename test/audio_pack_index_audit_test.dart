import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pack index owns every static audio key and verified file', () async {
    final index =
        jsonDecode(
              await File('assets/data/audio_pack_index.json').readAsString(),
            )
            as Map<String, dynamic>;
    final packs = (index['packs'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(packs, hasLength(16));

    final owners = <String, String>{};
    final referencedAssets = <String>{};
    final checksumTextHashes = <String, Set<String>>{};
    for (final pack in packs) {
      final manifestFile = File(pack['manifest'] as String);
      final manifestBytes = await manifestFile.readAsBytes();
      expect(
        sha256.convert(manifestBytes).toString(),
        pack['manifestSha256'],
        reason: pack['pack'] as String,
      );
      final manifest =
          jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
      expect(manifest['version'], pack['version']);
      expect(manifest['minimumAppVersion'], '1.0.8');
      final requiresTextHash =
          manifest['mediaType'] != 'song' && manifest['mediaType'] != 'system';
      final prompts = (manifest['prompts'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final prompt in prompts) {
        final key = prompt['key'] as String;
        expect(owners[key], isNull, reason: 'Duplicate owner for $key');
        owners[key] = manifest['pack'] as String;
        expect(key, isNot(contains(RegExp(r'(^|\.)(dynamic|user)(\.|$)'))));
        expect(prompt['locale'], isIn(<String>['en-US', 'vi-VN', 'und']));
        final duration = (prompt['durationSeconds'] as num).toDouble();
        expect(duration, greaterThan(0), reason: key);
        expect(duration, lessThanOrEqualTo(300), reason: key);
        final asset = prompt['asset'] as String;
        referencedAssets.add(asset.replaceAll(r'\', '/'));
        final audio = File(asset);
        expect(await audio.exists(), isTrue, reason: key);
        final bytes = await audio.readAsBytes();
        expect(bytes.length, prompt['sizeBytes'], reason: key);
        expect(sha256.convert(bytes).toString(), prompt['sha256'], reason: key);
        if (requiresTextHash) {
          final textHash = prompt['textHash'] as String?;
          expect(textHash, matches(RegExp(r'^[a-f0-9]{64}$')), reason: key);
          checksumTextHashes
              .putIfAbsent(prompt['sha256'] as String, () => <String>{})
              .add(textHash!);
        }
      }
    }

    // GAP66 is the bounded text-compatibility pack for fixed prompts whose
    // legacy module contracts still expose only spoken text. Keep it outside
    // the key index, but audit every bundled file with the same integrity bar.
    final gap66 =
        jsonDecode(
              await File('assets/data/homi_gap66_audio.json').readAsString(),
            )
            as Map<String, dynamic>;
    final gap66Prompts = (gap66['prompts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(gap66Prompts, hasLength(66));
    for (final prompt in gap66Prompts) {
      final asset = (prompt['asset'] as String).replaceAll(r'\', '/');
      referencedAssets.add(asset);
      final bytes = await File(asset).readAsBytes();
      expect(bytes, isNotEmpty, reason: prompt['id'] as String);
      expect(
        sha256.convert(bytes).toString(),
        prompt['sha256'],
        reason: prompt['id'] as String,
      );
    }

    final actualAssets = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp3'))
        .map((file) => file.path.replaceAll(r'\', '/'))
        .toSet();
    expect(actualAssets.difference(referencedAssets), isEmpty);
    expect(
      checksumTextHashes.values.where((hashes) => hashes.length > 1),
      isEmpty,
      reason: 'One shared recording must not represent different source text.',
    );
  });

  test('repository sources do not contain the local ElevenLabs API key', () {
    final keyFile = File(r'C:\Users\DELL\Documents\api_key_elevanlabs.txt');
    if (!keyFile.existsSync()) return;
    final secret = keyFile.readAsStringSync().trim();
    expect(secret, isNotEmpty);
    final leaks = <String>[];
    for (final root in const <String>['lib', 'assets', 'test', 'tool']) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (file.path.toLowerCase().endsWith('.mp3')) continue;
        try {
          if (file.readAsStringSync().contains(secret)) leaks.add(file.path);
        } on FileSystemException {
          // Binary/generated files outside the source audit are ignored.
        }
      }
    }
    expect(leaks, isEmpty);
  });
}
