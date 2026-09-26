package com.innotrik.aispeaking

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** One short, predictable ready cue, independent of OEM ToneGenerator sounds. */
internal object ReadyCueWaveform {
    private const val sampleRate = 16_000
    private const val durationMillis = 120
    private const val fadeMillis = 8
    private const val frequencyHz = 880.0
    private const val activeRmsDbfs = -21.0

    /** PCM16 mono WAV; the active sine has -21 dBFS RMS before its edge fades. */
    fun wavBytes(): ByteArray {
        val sampleCount = sampleRate * durationMillis / 1_000
        val fadeSamples = sampleRate * fadeMillis / 1_000
        val dataBytes = sampleCount * Short.SIZE_BYTES
        val buffer = ByteBuffer.allocate(44 + dataBytes).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(36 + dataBytes)
        buffer.put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1.toShort()) // Linear PCM.
        buffer.putShort(1.toShort()) // Mono.
        buffer.putInt(sampleRate)
        buffer.putInt(sampleRate * Short.SIZE_BYTES)
        buffer.putShort(Short.SIZE_BYTES.toShort())
        buffer.putShort(16.toShort())
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataBytes)

        val amplitude = sqrt(2.0) * 10.0.pow(activeRmsDbfs / 20.0)
        for (index in 0 until sampleCount) {
            val attack = index.toDouble() / fadeSamples
            val release = (sampleCount - index - 1).toDouble() / fadeSamples
            val envelope = min(1.0, min(attack, release))
            val phase = 2.0 * PI * frequencyHz * index / sampleRate
            val sample = (sin(phase) * amplitude * envelope * Short.MAX_VALUE)
                .roundToInt()
                .toShort()
            buffer.putShort(sample)
        }
        return buffer.array()
    }
}
