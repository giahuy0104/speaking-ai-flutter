import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseline = <String, String>{
    'assets/data/listening_lessons.json':
        '18d06fee96896bb3f6fa053ab4b7d55a034143eee5c1bafb57d13cca6be1d909',
    'assets/data/listening_topic_patch_v42.json':
        '506d374c8ac01eafc8a03e569bd0d032c64479e17c8e2d311478e6ec6ffc1544',
    'assets/data/listening_ai_lexicon_v4.json':
        '1ade63c2bf2cb9cf0858980c19f8ba0d4cace0271be532a05046ff5e453b6305',
    'assets/data/songs_audio.json':
        '2bf933e1ea8fa87387d82d1e0954460354fd7b664fe12093d0e37ef33d2618f3',
    'assets/data/listening_3_5_audio.json':
        'aa6120a1014099da0323ed29f1894b752af824199f74b00fdcae69bee2a0d09c',
    'assets/data/listening_6_7_audio.json':
        'f5f67c87a4e1eb54aa40fc54d85eb439afcec59f6286899af8c5f403a34f925e',
    'assets/data/listening_8_10_audio.json':
        '048c77395a754e10675cc5cbeb5da57637f6a39c6a04ac4eba9544d635e9997d',
    'assets/data/listening_11_12_audio.json':
        'e7757ac0bdb4fd1bbf33752747b891cc0f338f6c819c89de9c0ac8e0cb07f9c0',
    'assets/data/listening_13_15_audio.json':
        '2edbbd32c237c2c19ecbd0e91efd66a8d063cba0fa7b430a82a0146f709312cf',
    'assets/data/challenge_3_5_audio.json':
        'f8725f04c478a99cb37426ca4489639267cb1eac9a7effeb7402109b4c6986ba',
    'assets/data/challenge_6_7_audio.json':
        '49a30884ac3a5d1b18f3ab766bce83ab198bb73bde9b9d57a35de4fb0874204c',
    'assets/data/challenge_8_10_audio.json':
        '7608e11b48b5bb04143e09204330f962b9141b590e9057822a5c648fc0c29e94',
    'assets/data/challenge_11_12_audio.json':
        'd8a1ff766fb62fc3240c2055e528e958ebb43b3ad975a86d1096fec5c4f2764c',
    'assets/data/challenge_13_15_audio.json':
        '7ce950dc31caf4ff06721d6a5656fe5df761603a6d9fe05375504306fab5456a',
  };
  test(
    'curriculum, patch and audio match the reviewed content and recordings',
    () async {
      for (final entry in baseline.entries) {
        // Git may check text out with CRLF on Windows.
        final text = (await File(
          entry.key,
        ).readAsString()).replaceAll('\r\n', '\n');
        expect(
          sha256.convert(utf8.encode(text)).toString(),
          entry.value,
          reason: entry.key,
        );
      }
    },
  );
}
