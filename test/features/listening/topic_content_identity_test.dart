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
    // Approved recordings imported from the 14 October audio update.
    // Curriculum, lesson IDs and song content above remain unchanged.
    'assets/data/listening_3_5_audio.json':
        '627616ff729ce0aff07037e52fe53c539e8baa32755d8085e9b41eaf8d6ab367',
    'assets/data/listening_6_7_audio.json':
        '20586597c432e41727b56c0215aea584714dcfabf247c5b435bb2bdb6b757b47',
    'assets/data/listening_8_10_audio.json':
        'f7cfa2c41b137fd1b6666437a72eb2c7db1f0fdc6425767372ebbde6f0558eb9',
    'assets/data/listening_11_12_audio.json':
        'a117ab11da4755c784c8dda575319f4d3d28efe0f184404682c5335f0e8a3937',
    'assets/data/listening_13_15_audio.json':
        '0522eddc6f990d31c33efe7d29a4a9a3282ea6ff4f8914256742c328c1a6e693',
    'assets/data/challenge_3_5_audio.json':
        'd51931943741bbf79d6f7aad3ded0573e42c812ec6b38adec254059f2575221e',
    'assets/data/challenge_6_7_audio.json':
        'eb495c0f9d16788424f9af668a080e6907fc95c493db3d60aaa89703a7c67f1d',
    'assets/data/challenge_8_10_audio.json':
        'ddd9c216f8773168931ceefea7c082adf6d35469859e71f9a5c294f85c698fc4',
    'assets/data/challenge_11_12_audio.json':
        'b0a3ca13be34abcebd992eb8ed5b29032a187e66362f88e84c73baa9731370d1',
    'assets/data/challenge_13_15_audio.json':
        'd32af0fffdc4202daefd85b093d007a66d317bc1f082ed8ba66b1aa3c486ca51',
  };
  test(
    'curriculum stays unchanged and audio matches the approved October update',
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
