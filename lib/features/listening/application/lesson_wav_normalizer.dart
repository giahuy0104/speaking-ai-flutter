import 'dart:typed_data';

import '../../../core/audio/wav_audio.dart';

/// Normalizes the stereo PCM16 WAV that some Android microphone drivers force
/// on the record plugin despite a mono request. Unsupported formats and valid
/// mono files remain byte-identical; malformed containers are never rewritten.
Uint8List normalizeAndroidLessonWav(Uint8List source) {
  final data = ByteData.sublistView(source);
  bool hasTag(int offset, String tag) =>
      offset + tag.length <= source.length &&
      Iterable<int>.generate(
        tag.length,
      ).every((index) => source[offset + index] == tag.codeUnitAt(index));

  if (source.length < 12 || !hasTag(0, 'RIFF') || !hasTag(8, 'WAVE')) {
    throw const FormatException('Bản ghi WAV chưa được hoàn tất.');
  }
  final riffEnd = data.getUint32(4, Endian.little) + 8;
  if (riffEnd < 12 || riffEnd > source.length) {
    throw const FormatException('Bản ghi WAV bị thiếu dữ liệu.');
  }

  int? formatOffset;
  int? pcmOffset;
  int? pcmLength;
  var offset = 12;
  while (offset + 8 <= riffEnd) {
    final size = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + size;
    if (chunkEnd > riffEnd) {
      throw const FormatException('Bản ghi WAV bị thiếu dữ liệu.');
    }
    if (hasTag(offset, 'fmt ')) {
      if (formatOffset != null || size < 16) {
        throw const FormatException('Thông tin định dạng WAV không hợp lệ.');
      }
      formatOffset = chunkStart;
    } else if (hasTag(offset, 'data')) {
      if (pcmOffset != null) {
        throw const FormatException('Bản ghi WAV có nhiều vùng âm thanh.');
      }
      pcmOffset = chunkStart;
      pcmLength = size;
    }
    // RIFF chunks with an odd payload include one byte of alignment padding.
    offset = chunkEnd + (size & 1);
  }
  if (offset != riffEnd ||
      formatOffset == null ||
      pcmOffset == null ||
      pcmLength == null) {
    throw const FormatException('Cấu trúc bản ghi WAV chưa hoàn tất.');
  }

  final encoding = data.getUint16(formatOffset, Endian.little);
  final channels = data.getUint16(formatOffset + 2, Endian.little);
  final sampleRate = data.getUint32(formatOffset + 4, Endian.little);
  final byteRate = data.getUint32(formatOffset + 8, Endian.little);
  final blockAlign = data.getUint16(formatOffset + 12, Endian.little);
  final bits = data.getUint16(formatOffset + 14, Endian.little);
  if (encoding != 1 ||
      sampleRate != 16000 ||
      bits != 16 ||
      (channels != 1 && channels != 2)) {
    return source;
  }
  if (blockAlign != channels * 2 ||
      byteRate != sampleRate * blockAlign ||
      pcmLength % blockAlign != 0) {
    throw const FormatException('Khung âm thanh WAV không đầy đủ.');
  }
  if (channels == 1) return source;

  final frameCount = pcmLength ~/ blockAlign;
  final header = buildPcm16WavHeader(pcmByteLength: frameCount * 2);
  final mono = Uint8List(header.length + frameCount * 2)..setAll(0, header);
  final output = ByteData.sublistView(mono);
  for (var frame = 0; frame < frameCount; frame += 1) {
    final sampleOffset = pcmOffset + frame * 4;
    final left = data.getInt16(sampleOffset, Endian.little);
    final right = data.getInt16(sampleOffset + 2, Endian.little);
    // Dart integers preserve the full sum before averaging signed samples.
    output.setInt16(
      header.length + frame * 2,
      (left + right) ~/ 2,
      Endian.little,
    );
  }
  return mono;
}
