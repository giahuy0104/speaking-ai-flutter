package com.innotrik.aispeaking

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidPlaybackLoudnessTest {
    @Test
    fun quietAndLoudSpeechReachTheSameTargetWithoutStackingGain() {
        val quiet = sineMeter(-30.0).result()!!
        val loud = sineMeter(-10.0).result()!!
        assertEquals(-21.0, quiet.measuredDb + quiet.gainDb, 0.001)
        assertEquals(-21.0, loud.measuredDb + loud.gainDb, 0.001)
        assertTrue(quiet.gainDb > 0)
        assertTrue(loud.gainDb < 0)
        assertTrue(quiet.peakDb + quiet.gainDb <= -1.0)
        assertTrue(loud.peakDb + loud.gainDb <= -1.0)
    }

    @Test
    fun silenceAndLowLevelNoiseNeverGetBoosted() {
        val silence = PcmPlaybackLevelMeter(16000, 1)
        repeat(16000) { silence.addSample(0.0) }
        assertEquals(0.0, silence.result()!!.gainDb, 0.0)
        assertEquals(0, silence.result()!!.activeWindowCount)
        assertEquals(0.0, sineMeter(-60.0).result()!!.gainDb, 0.0)
    }

    @Test
    fun longPausesDoNotIncreaseTheSpeechGain() {
        val short = sineMeter(-30.0).result()!!
        val withPause = sineMeter(-30.0)
        repeat(16000 * 4) { withPause.addSample(0.0) }
        assertEquals(short.gainDb, withPause.result()!!.gainDb, 0.001)
        assertEquals(5000L, withPause.result()!!.analyzedDurationMs)
    }

    @Test
    fun isolatedPeaksLimitTheGainEvenWhenAverageSpeechIsQuiet() {
        val meter = sineMeter(-35.0)
        meter.addSample(1.0)
        val result = meter.result()!!
        assertEquals(-1.0, result.gainDb, 0.001)
        assertEquals(-1.0, result.peakDb + result.gainDb, 0.001)
    }

    @Test
    fun veryQuietSpeechCanUseTheH20RecordingGainRange() {
        val result = sineMeter(-45.0).result()!!
        assertEquals(24.0, result.gainDb, 0.001)
        assertEquals(-21.0, result.measuredDb + result.gainDb, 0.001)
    }

    @Test
    fun h20RecordingGainNeverExceedsTwentyEightDb() {
        val result = sineMeter(-49.5).result()!!
        assertTrue(result.activeWindowCount > 0)
        assertEquals(28.0, result.gainDb, 0.001)
    }

    @Test
    fun oppositeStereoChannelsAreMeasuredWithoutPhaseCancellation() {
        val mono = sineMeter(-25.0).result()!!
        val stereo = PcmPlaybackLevelMeter(16000, 2)
        repeat(16000) { index ->
            val value = sineSample(index, -25.0)
            stereo.addSample(value)
            stereo.addSample(-value)
        }
        assertEquals(mono.measuredDb, stereo.result()!!.measuredDb, 0.001)
        assertEquals(1000L, stereo.result()!!.analyzedDurationMs)
    }

    @Test
    fun emptyOrPartialStereoSamplesAreNotMeasured() {
        assertNull(PcmPlaybackLevelMeter(16000, 1).result())
        val incomplete = PcmPlaybackLevelMeter(16000, 2)
        incomplete.addSample(0.1)
        assertNull(incomplete.result())
    }

    @Test(expected = IllegalArgumentException::class)
    fun nonFiniteSamplesAreRejected() {
        PcmPlaybackLevelMeter(16000, 1).addSample(Double.NaN)
    }

    @Test
    fun waveAnalysisPreservesOriginalBytesAndSupportsNon16kAudio() {
        withWave(wave(-27.0, 24000)) { file, bytes ->
            val measured = AndroidPlaybackLoudness.analyze(file)
            assertNotNull(measured)
            assertEquals(-21.0, measured!!.measuredDb + measured.gainDb, 0.001)
            assertEquals(1000L, measured.analyzedDurationMs)
            assertArrayEquals(bytes, file.readBytes())
            assertEquals(measured, AndroidPlaybackLoudness.analyze(file))
        }
    }

    @Test
    fun metadataChangeInvalidatesTheLevelCache() {
        withWave(wave(-27.0)) { file, _ ->
            val before = AndroidPlaybackLoudness.analyze(file)!!
            val previousTime = file.lastModified()
            file.writeBytes(wave(-10.0))
            assertTrue(file.setLastModified(previousTime + 2000))
            val after = AndroidPlaybackLoudness.analyze(file)!!
            assertTrue(before.gainDb > 0)
            assertTrue(after.gainDb < 0)
        }
    }

    @Test
    fun truncatedWaveAndUnsupportedEncodingHaveNoPartialEstimate() {
        val complete = wave(-27.0)
        withWave(complete.copyOf(complete.size - 10)) { file, _ ->
            assertNull(AndroidPlaybackLoudness.analyze(file))
        }
        complete[20] = 3 // IEEE float bytes must not be interpreted as PCM16.
        withWave(complete) { file, _ ->
            assertNull(AndroidPlaybackLoudness.analyze(file))
        }
    }

    @Test
    fun mapIdentifiesTheMeasurementAsRmsAndNotLufs() {
        val result = sineMeter(-25.0).result()!!
        assertEquals("gated-rms-dbfs", result.toMap()["measurement"])
        assertEquals(result.gainDb, result.toMap()["gainDb"])
    }

    private fun sineMeter(rmsDb: Double): PcmPlaybackLevelMeter =
        PcmPlaybackLevelMeter(16000, 1).also { meter ->
            repeat(16000) { meter.addSample(sineSample(it, rmsDb)) }
        }

    private fun sineSample(index: Int, rmsDb: Double, sampleRate: Int = 16000): Double =
        10.0.pow(rmsDb / 20) * kotlin.math.sqrt(2.0) * sin(2 * PI * 1000 * index / sampleRate)

    private fun wave(rmsDb: Double, sampleRate: Int = 16000): ByteArray {
        val size = sampleRate * 2
        val output = ByteBuffer.allocate(44 + size).order(ByteOrder.LITTLE_ENDIAN)
        output.put("RIFF".toByteArray(Charsets.US_ASCII))
        output.putInt(36 + size)
        output.put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
        output.putInt(16)
        output.putShort(1)
        output.putShort(1)
        output.putInt(sampleRate)
        output.putInt(sampleRate * 2)
        output.putShort(2)
        output.putShort(16)
        output.put("data".toByteArray(Charsets.US_ASCII))
        output.putInt(size)
        repeat(sampleRate) { output.putShort((sineSample(it, rmsDb, sampleRate) * 32768).toInt().toShort()) }
        return output.array()
    }

    private fun withWave(bytes: ByteArray, block: (File, ByteArray) -> Unit) {
        val file = File.createTempFile("playback-level-", ".wav")
        try {
            file.writeBytes(bytes)
            block(file, bytes)
        } finally {
            file.delete()
        }
    }
}
