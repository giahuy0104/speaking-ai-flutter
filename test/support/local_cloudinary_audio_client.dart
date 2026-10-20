import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client createLocalCloudinaryAudioClient() {
  final manifest =
      jsonDecode(
            File('assets/data/assistant_core_audio.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final assetByUrl = <String, String>{
    for (final entry
        in (manifest['prompts'] as List).cast<Map<String, dynamic>>())
      if (entry['url'] is String)
        entry['url'] as String: entry['asset'] as String,
  };
  return MockClient((request) async {
    final asset = assetByUrl[request.url.toString()];
    if (asset == null) {
      return http.Response('Unknown Cloudinary test URL', 404);
    }
    return http.Response.bytes(await File(asset).readAsBytes(), 200);
  });
}
