import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client createLocalCloudinaryAudioClient() {
  final catalog =
      jsonDecode(
            File('assets/data/remote_audio_catalog.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final assetByUrl = <String, String>{
    for (final entry in (catalog['assets'] as Map).entries)
      (entry.value as Map)['url'] as String: entry.key as String,
  };
  return MockClient((request) async {
    final asset = assetByUrl[request.url.toString()];
    if (asset == null) {
      return http.Response('Unknown Cloudinary test URL', 404);
    }
    return http.Response.bytes(await File(asset).readAsBytes(), 200);
  });
}
