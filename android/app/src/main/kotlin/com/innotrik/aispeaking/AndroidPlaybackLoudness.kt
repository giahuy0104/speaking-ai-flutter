package com.innotrik.aispeaking

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * Source-level matching for playback only. This is gated, unweighted PCM RMS,
 * NOT integrated LUFS or a true-peak meter. No recording bytes are rewritten.
 *
 * Call analyze on a worker: local files may need MediaCodec decoding. Complete
 * short clips are measured; partial/unsupported/slow decodes return null so an
 * unseen loud section cannot be boosted based on a quiet beginning.
 */
object AndroidPlaybackLoudness {
    const val TARGET_RMS_DBFS = -21.0
    const val SAMPLE_PEAK_CEILING_DBFS = -1.0
    // H20 SCO captures can be substantially quieter than authored audio. The
    // LoudnessEnhancer supplies limiting, while the meter still attenuates loud
    // sources and respects sample headroom when choosing the actual gain.
    const val MAX_GAIN_DB = 28.0
    const val FALLBACK_GAIN_DB = 8.0
    private const val MAX_DURATION_MS = 30_000L
    private const val MAX_DECODE_NS = 350_000_000L
    /** For measurements nobody waits on, e.g. warming a clip's next playback. */
    const val BACKGROUND_DECODE_NS = 3_000_000_000L
    private const val MAX_CACHE_ENTRIES = 128

    private data class CacheKey(val path: String, val length: Long, val modified: Long)
    private data class Cached(val result: PlaybackLoudnessResult?)
    private val cache = object : LinkedHashMap<CacheKey, Cached>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<CacheKey, Cached>?) =
            size > MAX_CACHE_ENTRIES
    }

    fun analyze(file: File, maxDecodeNs: Long = MAX_DECODE_NS): PlaybackLoudnessResult? {
        if (!file.isFile || file.length() <= 0) return null
        val key = CacheKey(file.absolutePath, file.length(), file.lastModified())
        synchronized(cache) { cache[key]?.let { return it.result } }
        val deadline = System.nanoTime() + maxDecodeNs
        val result = try {
            if (isWave(file)) analyzeWave(file, deadline) else decode(file, deadline)
        } catch (_: Exception) {
            null
        }
        // A recording still being finalized must not poison the final cache.
        if (file.length() == key.length && file.lastModified() == key.modified) {
            synchronized(cache) { cache[key] = Cached(result) }
        }
        return result
    }

    private fun isWave(file: File): Boolean = RandomAccessFile(file, "r").use {
        if (it.length() < 12) return@use false
        it.readInt() == 0x52494646 && run {
            it.skipBytes(4)
            it.readInt() == 0x57415645
        }
    }

    private fun analyzeWave(file: File, deadline: Long): PlaybackLoudnessResult? =
        RandomAccessFile(file, "r").use { input ->
            input.seek(4)
            val riffEnd = readUnsignedIntLe(input) + 8
            if (riffEnd > input.length() || riffEnd < 12) return@use null
            var offset = 12L
            var sampleRate = 0
            var channels = 0
            var blockAlign = 0
            var pcmOffset = -1L
            var pcmLength = -1L
            var seenFormat = false
            while (offset + 8 <= riffEnd) {
                if (System.nanoTime() >= deadline) return@use null
                input.seek(offset)
                val tag = input.readInt()
                val size = readUnsignedIntLe(input)
                val end = offset + 8 + size
                if (end > riffEnd) return@use null
                when (tag) {
                    0x666d7420 -> { // fmt
                        if (seenFormat || size < 16) return@use null
                        seenFormat = true
                        val encoding = readUnsignedShortLe(input)
                        channels = readUnsignedShortLe(input)
                        sampleRate = readUnsignedIntLe(input).toInt()
                        val byteRate = readUnsignedIntLe(input)
                        blockAlign = readUnsignedShortLe(input)
                        val bits = readUnsignedShortLe(input)
                        if (encoding != 1 || bits != 16 || channels !in 1..8 ||
                            sampleRate !in 8000..192000 || blockAlign != channels * 2 ||
                            byteRate != sampleRate.toLong() * blockAlign
                        ) return@use null
                    }
                    0x64617461 -> { // data
                        if (pcmOffset >= 0) return@use null
                        pcmOffset = offset + 8
                        pcmLength = size
                    }
                }
                offset = end + (size and 1)
            }
            if (offset != riffEnd || !seenFormat || pcmOffset < 0 || pcmLength <= 0 ||
                pcmLength % blockAlign != 0L ||
                pcmLength / blockAlign > sampleRate * MAX_DURATION_MS / 1000
            ) return@use null
            val meter = PcmPlaybackLevelMeter(sampleRate, channels)
            input.seek(pcmOffset)
            val bytes = ByteArray(16_384)
            var remaining = pcmLength
            while (remaining > 0) {
                if (System.nanoTime() >= deadline) return@use null
                val count = min(bytes.size.toLong(), remaining).toInt()
                input.readFully(bytes, 0, count)
                var index = 0
                while (index < count) {
                    val sample = ((bytes[index].toInt() and 0xff) or
                        (bytes[index + 1].toInt() shl 8)).toShort()
                    meter.addSample(sample / 32768.0)
                    index += 2
                }
                remaining -= count
            }
            meter.result()
        }

    private fun decode(file: File, deadline: Long): PlaybackLoudnessResult? {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var decoderStarted = false
        try {
            extractor.setDataSource(file.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            if (format.containsKey(MediaFormat.KEY_DURATION) &&
                format.getLong(MediaFormat.KEY_DURATION) > MAX_DURATION_MS * 1000
            ) return null
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            if (sampleRate !in 8000..192000 || channels !in 1..8) return null
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var meter = PcmPlaybackLevelMeter(sampleRate, channels)
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            decoderStarted = true
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            while (System.nanoTime() < deadline) {
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(1_000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index) ?: return null
                        buffer.clear()
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(index, 0, count, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                when (val index = codec.dequeueOutputBuffer(info, 1_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val output = codec.outputFormat
                        val nextRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        val nextChannels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (nextRate !in 8000..192000 || nextChannels !in 1..8) return null
                        if (nextRate != sampleRate || nextChannels != channels) {
                            if (meter.sampleCount != 0L) return null
                            sampleRate = nextRate
                            channels = nextChannels
                            meter = PcmPlaybackLevelMeter(sampleRate, channels)
                        }
                        encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            output.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        } else AudioFormat.ENCODING_PCM_16BIT
                        if (encoding != AudioFormat.ENCODING_PCM_16BIT &&
                            encoding != AudioFormat.ENCODING_PCM_FLOAT
                        ) return null
                    }
                    else -> if (index >= 0) {
                        try {
                            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                val bytesPerSample = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                                if (info.size % (bytesPerSample * channels) != 0) return null
                                val buffer = codec.getOutputBuffer(index) ?: return null
                                buffer.position(info.offset)
                                buffer.limit(info.offset + info.size)
                                buffer.order(ByteOrder.LITTLE_ENDIAN)
                                while (buffer.remaining() >= bytesPerSample) {
                                    meter.addSample(if (bytesPerSample == 4) buffer.float.toDouble()
                                        else buffer.short / 32768.0)
                                }
                                if (meter.durationMs > MAX_DURATION_MS) return null
                            }
                        } finally {
                            codec.releaseOutputBuffer(index, false)
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            return meter.result()
                        }
                    }
                }
            }
            return null
        } finally {
            if (decoderStarted) try { decoder?.stop() } catch (_: Exception) { }
            try { decoder?.release() } catch (_: Exception) { }
            extractor.release()
        }
    }

    private fun readUnsignedIntLe(input: RandomAccessFile): Long =
        Integer.reverseBytes(input.readInt()).toLong() and 0xffffffffL

    private fun readUnsignedShortLe(input: RandomAccessFile): Int =
        java.lang.Short.reverseBytes(input.readShort()).toInt() and 0xffff
}

data class PlaybackLoudnessResult(
    val gainDb: Double,
    val measuredDb: Double,
    val peakDb: Double,
    val analyzedDurationMs: Long,
    val activeWindowCount: Int,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "gainDb" to gainDb,
        "measuredDb" to measuredDb,
        "peakDb" to peakDb,
        "analyzedDurationMs" to analyzedDurationMs,
        "activeWindowCount" to activeWindowCount,
        "measurement" to "gated-rms-dbfs",
    )
}

/** Pure PCM meter, shared by the WAV and codec paths and tested without Android. */
class PcmPlaybackLevelMeter(private val sampleRate: Int, private val channelCount: Int) {
    init {
        require(sampleRate > 0 && channelCount > 0)
    }

    private data class Window(val energy: Double, val count: Int) {
        val meanSquare: Double get() = energy / count
    }

    private val windowSamples = max(1, sampleRate / 50) * channelCount
    private val windows = ArrayList<Window>()
    private var windowEnergy = 0.0
    private var windowCount = 0
    private var peak = 0.0
    var sampleCount = 0L
        private set
    val durationMs: Long get() = sampleCount * 1000 / sampleRate / channelCount

    fun addSample(value: Double) {
        require(value.isFinite())
        peak = max(peak, abs(value))
        windowEnergy += value * value
        windowCount++
        sampleCount++
        if (windowCount == windowSamples) {
            windows.add(Window(windowEnergy, windowCount))
            windowEnergy = 0.0
            windowCount = 0
        }
    }

    fun result(): PlaybackLoudnessResult? {
        if (sampleCount == 0L || sampleCount % channelCount != 0L) return null
        val complete = if (windowCount > 0) windows + Window(windowEnergy, windowCount) else windows
        // Pad only for gate selection: a last-window click with one sample
        // must not set a much higher relative gate than a full speech window.
        val maxMeanSquare = complete.maxOf { it.energy / windowSamples }
        // Absolute -50 dBFS gate, plus -30 dB relative to the strongest window.
        // This excludes pauses and very quiet noise from the level estimate.
        val gate = max(0.00001, maxMeanSquare / 1000)
        val active = complete.filter { it.energy / windowSamples >= gate }
        val peakDb = amplitudeDb(peak)
        if (active.isEmpty()) {
            val meanSquare = complete.sumOf { it.energy } / sampleCount
            return PlaybackLoudnessResult(0.0, powerDb(meanSquare), peakDb, durationMs, 0)
        }
        val measuredDb = powerDb(active.sumOf { it.energy } / active.sumOf { it.count }.toDouble())
        val desired = AndroidPlaybackLoudness.TARGET_RMS_DBFS - measuredDb
        val headroom = AndroidPlaybackLoudness.SAMPLE_PEAK_CEILING_DBFS - peakDb
        val gain = min(min(desired, AndroidPlaybackLoudness.MAX_GAIN_DB), headroom)
        return PlaybackLoudnessResult(gain, measuredDb, peakDb, durationMs, active.size)
    }

    private fun amplitudeDb(value: Double) = if (value > 0) 20 * log10(value) else -120.0
    private fun powerDb(value: Double) = if (value > 0) 10 * log10(value) else -120.0
}
