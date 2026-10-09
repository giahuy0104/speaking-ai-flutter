package com.innotrik.aispeaking

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadyCueWaveformTest {
    @Test
    fun wavHas120MillisecondsOf16KhzMonoPcm() {
        val bytes = ReadyCueWaveform.wavBytes()
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals("RIFF", String(bytes, 0, 4, Charsets.US_ASCII))
        assertEquals(bytes.size - 8, header.getInt(4))
        assertEquals("WAVEfmt ", String(bytes, 8, 8, Charsets.US_ASCII))
        assertEquals(16, header.getInt(16))
        assertEquals(1, header.getShort(20).toInt())
        assertEquals(1, header.getShort(22).toInt())
        assertEquals(16_000, header.getInt(24))
        assertEquals(32_000, header.getInt(28))
        assertEquals(2, header.getShort(32).toInt())
        assertEquals(16, header.getShort(34).toInt())
        assertEquals("data", String(bytes, 36, 4, Charsets.US_ASCII))
        assertEquals(3_840, header.getInt(40))
        assertEquals(44 + 3_840, bytes.size)
    }

    @Test
    fun cueHasOneContinuous880HzToneWithQuietEdgesAndNoSecondBurst() {
        val samples = samples()
        assertEquals(0.0, samples.first(), 0.0)
        assertEquals(0.0, samples.last(), 0.0)

        val plateau = samples.copyOfRange(128, samples.size - 128)
        val plateauPeak = plateau.maxOf { abs(it) }
        assertTrue(plateauPeak < 0.13)
        assertTrue(samples.take(32).maxOf { abs(it) } < plateauPeak * 0.3)
        assertTrue(samples.takeLast(32).maxOf { abs(it) } < plateauPeak * 0.3)
        assertEquals(-21.0, 20.0 * log10(rms(plateau)), 0.05)

        // All interior 10 ms windows retain the same tone energy: there is no
        // hidden silence/restart creating a second beep in the waveform.
        for (start in 160..1_600 step 160) {
            val windowDbfs = 20.0 * log10(rms(samples.copyOfRange(start, start + 160)))
            assertEquals(-21.0, windowDbfs, 0.15)
        }
        val upwardCrossings = (1 until samples.size).count { index ->
            samples[index - 1] <= 0.0 && samples[index] > 0.0
        }
        assertTrue(upwardCrossings in 105..106)
    }

    private fun samples(): DoubleArray {
        val bytes = ReadyCueWaveform.wavBytes()
        val pcm = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        pcm.position(44)
        return DoubleArray((bytes.size - 44) / Short.SIZE_BYTES) {
            pcm.short.toDouble() / Short.MAX_VALUE
        }
    }

    private fun rms(samples: DoubleArray): Double =
        sqrt(samples.sumOf { it * it } / samples.size)
}
