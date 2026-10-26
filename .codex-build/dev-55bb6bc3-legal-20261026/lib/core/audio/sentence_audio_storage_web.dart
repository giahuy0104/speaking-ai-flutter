import 'dart:typed_data';

Future<Uri> storeSentenceAudio(Uint8List bytes, String mime) async =>
    Uri.dataFromBytes(bytes, mimeType: mime);

Future<void> releaseSentenceAudio(Uri uri) async {}
