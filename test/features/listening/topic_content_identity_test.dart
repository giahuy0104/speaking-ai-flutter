import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseline = <String, String>{
    'assets/data/listening_lessons.json':
        '303fd255e3f485f603d3449403f9ec511e7b30231d7095cc446cc6f0d017d140',
    'assets/data/listening_topic_patch_v42.json':
        '5a016932114e00a498636e4cc369ea516c78d04c9fdf1d80dfe4e1c82cc43be3',
    'assets/data/listening_ai_lexicon_v4.json':
        '1ade63c2bf2cb9cf0858980c19f8ba0d4cace0271be532a05046ff5e453b6305',
    'assets/data/songs_audio.json':
        'f69a754eac9cc91f6ca6283a0a3c2b6858a3ac177b4aff86bab11054f29e4e67',
    // The approved recordings are now delivered through the verified remote
    // catalog. Curriculum text and lesson IDs remain pinned by these hashes.
    'assets/data/listening_3_5_audio.json':
        '0119aa500103ac60da9933646d1cc8111db26f988367ac3d0f176ec8fd166b43',
    'assets/data/listening_6_7_audio.json':
        '9469b79d1b7c2e9b1274ecff4b1b76915ef453ecbd486d08859ef30defbbba0a',
    'assets/data/listening_8_10_audio.json':
        'efd8dd951a5ec1203f0fd712c6630af3ff91c8b80835907257d025f126d50c0a',
    'assets/data/listening_11_12_audio.json':
        '7dbbfe40dd8041a82c3469a98b288096423e455dad68820d742678e6abac50f3',
    'assets/data/listening_13_15_audio.json':
        'a4dee77e261f8dc27885f918eea9d44f380571b162434f94c6bf106bc3b0b8c8',
    'assets/data/challenge_3_5_audio.json':
        '92b33be8a8a5e2c2b29e714158ae421604f026766d7f355e283299417cec1925',
    'assets/data/challenge_6_7_audio.json':
        '53fd8c5dded4956e96053c1cbd611094fa56438dddcd4ef289b90eb352e51a3d',
    'assets/data/challenge_8_10_audio.json':
        '3ad4c1e77cafe319c3ccec35b3bed9317cbda1c0b294b9a8831b63ed607f3f9a',
    'assets/data/challenge_11_12_audio.json':
        'd089dd0a69a31b2e6dbdb19683cc388b6102646cd3e485f01271447850cf0c87',
    'assets/data/challenge_13_15_audio.json':
        '71a785cacf660ff9bd19798ea5c7238c6bdfe2274bcb82aed2a8ca0c191a974f',
  };
  test('curriculum and verified audio catalog stay pinned', () async {
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
  });
}
