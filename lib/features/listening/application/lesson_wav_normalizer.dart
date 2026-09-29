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

/// Gated speech level of every saved child recording, ~4 dB above the level
/// Android plays authored prompts at, so a replay is clearly audible.
const double lessonRecordingTargetDbfs = -17.0;

const double _lessonRecordingPeakCeilingDbfs = -1.0;

/// Most a quiet recording is raised; more mostly raises the room's hiss.
const double _lessonRecordingMaxGainDb = 20.0;

/// Most the pauses between words are turned down, so a raised recording does
/// not replay its background noise at speech level.
const double _lessonRecordingPauseCutDb = 10.0;

/// Brings mono PCM16 lesson captures, quiet or loud, to one speech level.
/// Pauses are excluded from the measurement. A look-ahead limiter keeps peaks
/// under -1 dBFS, so one plosive no longer caps the gain of a whole recording.
/// A recording that is only steady noise is never raised, and pauses are
/// turned down by up to 10 dB so the raised noise floor does not hiss.
/// Authored lesson audio never enters this recording-only finalization path.
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
  // A click fills at most two 20 ms windows. Leaving the two strongest out
  // keeps it from setting the gate or the level; the limiter holds its peak.
  final ranked = windowPowers.toList()..sort((a, b) => b.compareTo(a));
  final measured = ranked.length > 2 ? ranked.sublist(2) : ranked;
  final strongest = measured.first;
  if (strongest <= 0 || peak <= 0) return source;
  final gate = math.max(math.pow(10, -5).toDouble(), strongest / 1000);
  final active = measured.where((power) => power >= gate).toList();
  if (active.isEmpty) return source;
  final rmsPower = active.reduce((a, b) => a + b) / active.length;
  final measuredDb = 10 * math.log(rmsPower) / math.ln10;
  // The quietest tenth of the recording is its background noise.
  final floorPower = math.max(
    1e-10,
    ranked[ranked.length - 1 - ranked.length ~/ 10],
  );
  final separationDb = measuredDb - 10 * math.log(floorPower) / math.ln10;
  var gainDb = math.min(
    _lessonRecordingMaxGainDb,
    lessonRecordingTargetDbfs - measuredDb,
  );
  // Under 100 ms above the gate is a knock, not speech; never turn the child
  // down to match it.
  final knockOnly = active.length < 5;
  if (knockOnly) gainDb = math.max(0, gainDb);
  // Nothing rises 6 dB over the noise: raising it would only replay hiss.
  if (separationDb < 6) gainDb = math.min(0, gainDb);
  final multiplier = math.pow(10, gainDb / 20).toDouble();
  final ceiling = math.pow(10, _lessonRecordingPeakCeilingDbfs / 20);
  if (gainDb.abs() <= 0.05 && peak * multiplier <= ceiling) return source;
  final reduction = _limiterGain(
    data,
    pcmOffset: pcmOffset,
    sampleCount: sampleCount,
    sampleRate: sampleRate,
    multiplier: multiplier,
    ceiling: ceiling.toDouble(),
  );
  final pauses = _pauseGain(
    windowPowers,
    windowSamples: windowSamples,
    sampleCount: sampleCount,
    sampleRate: sampleRate,
    // Halfway, in dB, between the noise floor and the speech level.
    threshold: math.sqrt(floorPower * rmsPower),
    // Noisy recordings get a shallower cut, so the gate does not chatter.
    cutDb: knockOnly
        ? 0
        : (separationDb - 6).clamp(0.0, _lessonRecordingPauseCutDb),
  );
  final output = Uint8List.fromList(source);
  final outputData = ByteData.sublistView(output);
  for (var index = 0; index < sampleCount; index += 1) {
    final sample = data.getInt16(pcmOffset + index * 2, Endian.little);
    outputData.setInt16(
      pcmOffset + index * 2,
      (sample * multiplier * reduction[index] * pauses[index]).round().clamp(
        -32768,
        32767,
      ),
      Endian.little,
    );
  }
  return output;
}

/// Per-sample gain reduction that keeps `sample * multiplier` under
/// [ceiling]. It ramps down over 5 ms before a peak and recovers over 60 ms,
/// so limiting a peak does not click or pump.
Float64List _limiterGain(
  ByteData data, {
  required int pcmOffset,
  required int sampleCount,
  required int sampleRate,
  required double multiplier,
  required double ceiling,
}) {
  final reduction = Float64List(sampleCount);
  final attackStep = 1 / math.max(1, sampleRate * 5 ~/ 1000);
  final releaseStep = 1 / math.max(1, sampleRate * 60 ~/ 1000);
  var next = 1.0;
  for (var index = sampleCount - 1; index >= 0; index -= 1) {
    final level =
        (data.getInt16(pcmOffset + index * 2, Endian.little) / 32768.0).abs() *
        multiplier;
    final needed = level > ceiling ? ceiling / level : 1.0;
    next = math.min(needed, next + attackStep);
    reduction[index] = next;
  }
  var previous = 1.0;
  for (var index = 0; index < sampleCount; index += 1) {
    previous = math.min(reduction[index], previous + releaseStep);
    reduction[index] = previous;
  }
  return reduction;
}

/// Per-sample gain that turns 20 ms windows under [threshold] down by
/// [cutDb]. It stays open 200 ms after speech, opens 20 ms before it and
/// closes over 100 ms, so word edges and short gaps are never cut.
Float64List _pauseGain(
  List<double> windowPowers, {
  required int windowSamples,
  required int sampleCount,
  required int sampleRate,
  required double threshold,
  required double cutDb,
}) {
  final gain = Float64List(sampleCount)..fillRange(0, sampleCount, 1);
  if (cutDb <= 0) return gain;
  final floor = math.pow(10, -cutDb / 20).toDouble();
  const holdWindows = 10;
  var sinceSpeech = holdWindows + 1;
  for (var window = 0; window < windowPowers.length; window += 1) {
    sinceSpeech = windowPowers[window] >= threshold ? 0 : sinceSpeech + 1;
    if (sinceSpeech <= holdWindows) continue;
    final start = window * windowSamples;
    final end = math.min(sampleCount, start + windowSamples);
    gain.fillRange(start, end, floor);
  }
  final closeStep = (1 - floor) / math.max(1, sampleRate ~/ 10);
  final openStep = (1 - floor) / math.max(1, sampleRate ~/ 50);
  var previous = 1.0;
  for (var index = 0; index < sampleCount; index += 1) {
    previous = math.max(gain[index], previous - closeStep);
    gain[index] = previous;
  }
  var next = gain[sampleCount - 1];
  for (var index = sampleCount - 1; index >= 0; index -= 1) {
    next = math.max(gain[index], next - openStep);
    gain[index] = next;
  }
  return gain;
}
