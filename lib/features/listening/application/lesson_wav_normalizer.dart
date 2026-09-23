import 'dart:math' as math;
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
  var leftEnergy = 0.0;
  var rightEnergy = 0.0;
  for (var frame = 0; frame < frameCount; frame += 1) {
    final sampleOffset = pcmOffset + frame * 4;
    final left = data.getInt16(sampleOffset, Endian.little);
    final right = data.getInt16(sampleOffset + 2, Endian.little);
    leftEnergy += left * left;
    rightEnergy += right * right;
  }
  // H20/OEM drivers can expose a stereo container even though only one
  // microphone channel carries speech. Averaging the two channels halves a
  // single live channel (~6 dB) and can cancel phase-inverted captures. Keep
  // the stronger complete channel instead; the backend still receives the
  // mono PCM16 format it expects, without altering duration or sample rate.
  final selectedChannelOffset = rightEnergy > leftEnergy ? 2 : 0;
  final header = buildPcm16WavHeader(pcmByteLength: frameCount * 2);
  final mono = Uint8List(header.length + frameCount * 2)..setAll(0, header);
  final output = ByteData.sublistView(mono);
  for (var frame = 0; frame < frameCount; frame += 1) {
    final sampleOffset = pcmOffset + frame * 4 + selectedChannelOffset;
    output.setInt16(
      header.length + frame * 2,
      data.getInt16(sampleOffset, Endian.little),
      Endian.little,
    );
  }
  return mono;
}

/// Raises only quiet mono PCM16 lesson captures to a conservative speech
/// target. Pauses are excluded and peak headroom prevents clipping. Authored
/// lesson audio never enters this recording-only finalization path.
Uint8List normalizeLessonWavLoudness(Uint8List source) {
  final data = ByteData.sublistView(source);
  bool hasTag(int offset, String tag) =>
      offset + tag.length <= source.length &&
      Iterable<int>.generate(
        tag.length,
      ).every((index) => source[offset + index] == tag.codeUnitAt(index));
  if (source.length < 12 || !hasTag(0, 'RIFF') || !hasTag(8, 'WAVE')) {
    return source;
  }
  final riffEnd = data.getUint32(4, Endian.little) + 8;
  int? formatOffset;
  int? formatLength;
  int? pcmOffset;
  int? pcmLength;
  var offset = 12;
  while (offset + 8 <= riffEnd && riffEnd <= source.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;
    final chunkEnd = chunkStart + size;
    if (chunkEnd > riffEnd) return source;
    if (hasTag(offset, 'fmt ')) {
      formatOffset = chunkStart;
      formatLength = size;
    }
    if (hasTag(offset, 'data')) {
      pcmOffset = chunkStart;
      pcmLength = size;
    }
    offset = chunkEnd + (size & 1);
  }
  if (formatOffset == null ||
      formatLength == null ||
      formatLength < 16 ||
      pcmOffset == null ||
      pcmLength == null) {
    return source;
  }
  final channels = data.getUint16(formatOffset + 2, Endian.little);
  final sampleRate = data.getUint32(formatOffset + 4, Endian.little);
  final bits = data.getUint16(formatOffset + 14, Endian.little);
  if (data.getUint16(formatOffset, Endian.little) != 1 ||
      channels != 1 ||
      bits != 16 ||
      sampleRate <= 0 ||
      pcmLength.isOdd) {
    return source;
  }
  final sampleCount = pcmLength ~/ 2;
  if (sampleCount == 0) return source;
  final windowSamples = math.max(1, sampleRate ~/ 50);
  final windowPowers = <double>[];
  var peak = 0.0;
  for (var start = 0; start < sampleCount; start += windowSamples) {
    final end = math.min(sampleCount, start + windowSamples);
    var energy = 0.0;
    for (var index = start; index < end; index += 1) {
      final sample = data.getInt16(pcmOffset + index * 2, Endian.little);
      final scaled = sample / 32768.0;
      peak = math.max(peak, scaled.abs());
      energy += scaled * scaled;
    }
    windowPowers.add(energy / (end - start));
  }
  final strongest = windowPowers.reduce(math.max);
  if (strongest <= 0 || peak <= 0) return source;
  final gate = math.max(math.pow(10, -5).toDouble(), strongest / 1000);
  final active = windowPowers.where((power) => power >= gate).toList();
  if (active.isEmpty) return source;
  final rmsPower = active.reduce((a, b) => a + b) / active.length;
  final measuredDb = 10 * math.log(rmsPower) / math.ln10;
  final peakDb = 20 * math.log(peak) / math.ln10;
  final gainDb = math.max(
    0.0,
    math.min(28.0, math.min(-21.0 - measuredDb, -1.0 - peakDb)),
  );
  if (gainDb <= 0.05) return source;
  final multiplier = math.pow(10, gainDb / 20).toDouble();
  final output = Uint8List.fromList(source);
  final outputData = ByteData.sublistView(output);
  for (var index = 0; index < sampleCount; index += 1) {
    final sample = data.getInt16(pcmOffset + index * 2, Endian.little);
    outputData.setInt16(
      pcmOffset + index * 2,
      (sample * multiplier).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return output;
}
