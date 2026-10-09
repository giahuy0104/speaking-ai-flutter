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
        '3703dd440a9f02a471ebb235120d9672c27444ad2c370daa70db8a2db9628695',
    'assets/data/listening_6_7_audio.json':
        '8d063dc8321701bb1f5247bd1c2dd31fe07917e4d9f523562aa01623c44161ad',
    'assets/data/listening_8_10_audio.json':
        '6bf062f7901e0e75e4ac072e6473addd29e7bb35fe2327e5bb1b8ceffc3dbfc7',
    'assets/data/listening_11_12_audio.json':
        '4cb015610459d07e0971fe2b3511b73262a1699eac286b4f4a921adff5f7cae3',
    'assets/data/listening_13_15_audio.json':
        'ed658538d429f2061cffdb00d3c5090189c7074897fdf0608fb1f5d7b3fa65bb',
    'assets/data/challenge_3_5_audio.json':
        'cb01b47172bc4e59e8e279f2228c7c3f110738da1152fead2304dd90abe59978',
    'assets/data/challenge_6_7_audio.json':
        '63932fd571dcf446a39ad630e0d4e2199078510b75d11ef9f6782dc852089211',
    'assets/data/challenge_8_10_audio.json':
        'cd535450189d79f98abc1f6024da8b71af1559aeadd7d0d17aeb97406d19acd5',
    'assets/data/challenge_11_12_audio.json':
        'e0f7fdff105dc6a047321e0960f5cca52e430031c98f42367a5ae9bd575f335c',
    'assets/data/challenge_13_15_audio.json':
        'cc727bd8e9d517bc17ab336b1afebb878a4fa20b5863aaba1f69de5e396336cd',
  };
  test(
    'curriculum, patch and lesson/audio identities match the pre-Level-removal content',
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
