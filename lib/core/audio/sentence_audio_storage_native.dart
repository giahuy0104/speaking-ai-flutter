import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<Uri> storeSentenceAudio(Uint8List bytes, String mime) async {
  final root = await getTemporaryDirectory();
  final directory = await Directory(
    '${root.path}/sentence_audio_',
  ).createTemp();
  final file = File('${directory.path}/speech.mp3');
  await file.writeAsBytes(bytes);
  return file.uri;
}

Future<void> releaseSentenceAudio(Uri uri) async {
  if (!uri.isScheme('file')) return;
  final file = File.fromUri(uri);
  if (await file.exists()) await file.delete();
  if (await file.parent.exists()) await file.parent.delete();
}
