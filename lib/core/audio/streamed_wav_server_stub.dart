import 'streamed_wav_source.dart';

/// No local server without dart:io (web): callers play the original URL.
Future<Uri?> registerStreamedWav(StreamedWavSource source) async => null;

void unregisterStreamedWav(StreamedWavSource source) {}
