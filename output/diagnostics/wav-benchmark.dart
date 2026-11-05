import 'dart:math' as math;
import 'dart:typed_data';
import '../../lib/features/listening/application/lesson_wav_normalizer.dart';
Uint8List source(int channels) {
 final frames=16000*6;
 final bytes=Uint8List(44+frames*channels*2);
 final d=ByteData.sublistView(bytes);
 void tag(int o,String s){bytes.setRange(o,o+s.length,s.codeUnits);}
 tag(0,'RIFF');d.setUint32(4,bytes.length-8,Endian.little);tag(8,'WAVE');tag(12,'fmt ');d.setUint32(16,16,Endian.little);d.setUint16(20,1,Endian.little);d.setUint16(22,channels,Endian.little);d.setUint32(24,16000,Endian.little);d.setUint32(28,16000*channels*2,Endian.little);d.setUint16(32,channels*2,Endian.little);d.setUint16(34,16,Endian.little);tag(36,'data');d.setUint32(40,bytes.length-44,Endian.little);
 for(var i=0;i<frames;i++)for(var c=0;c<channels;c++)d.setInt16(44+(i*channels+c)*2,(math.sin(i*2*math.pi*440/16000)*2000*(0.4+0.6*math.sin(i/10000).abs())).round(),Endian.little);
 return bytes;
}
void main(){for(final channels in [1,2]){final b=source(channels); final times=<int>[]; for(var n=0;n<105;n++){final sw=Stopwatch()..start(); final result=trimLessonWavSilence(normalizeLessonWavLoudness(normalizeAndroidLessonWav(b))); sw.stop();if(n>=5)times.add(sw.elapsedMicroseconds);if(n==0)print('channels=$channels cold_us=${sw.elapsedMicroseconds} bytes=${result.length}');}times.sort();print('channels=$channels p50_us=${times[50]} p95_us=${times[95]} max_us=${times.last}');}}
