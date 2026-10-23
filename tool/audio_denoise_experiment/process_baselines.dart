// Local experiment only. Does not change app capture or playback configuration.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ai_speaking_flutter_app/core/audio/pcm_speech_preprocessor.dart';
import 'package:ai_speaking_flutter_app/core/audio/wav_audio.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_wav_normalizer.dart';

void main(List<String> args) {
  final jobs = jsonDecode(File(args.single).readAsStringSync()) as List;
  for (final job in jobs) {
    var pcm = File(job['input'] as String).readAsBytesSync();
    if (job['preprocess'] == true) {
      final processor = PcmSpeechPreprocessor(sampleRate: 16000);
      final output = BytesBuilder(copy: false);
      for (var offset = 0; offset < pcm.length; offset += 6400) {
        final end = (offset + 6400).clamp(0, pcm.length);
        output.add(processor.process(Uint8List.sublistView(pcm, offset, end)));
      }
      pcm = output.takeBytes();
    }
    // No silence trimming: retain the timeline to measure quiet/voiced regions.
    final wav = normalizeLessonWavLoudness(buildPcm16Wav(pcm));
    File(job['output'] as String).writeAsBytesSync(wav.sublist(44));
  }
}
