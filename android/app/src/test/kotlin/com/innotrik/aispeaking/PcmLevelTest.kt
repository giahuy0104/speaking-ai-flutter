package com.innotrik.aispeaking

import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Test

class PcmLevelTest {
    private fun sine(amplitude: Double, samples: Int = 1600): ByteArray {
        val bytes = ByteArray(samples * 2)
        for (index in 0 until samples) {
            val value = (sin(2.0 * PI * 440.0 * index / 16000.0) * amplitude * Short.MAX_VALUE)
                .roundToInt()
            bytes[index * 2] = (value and 0xff).toByte()
            bytes[index * 2 + 1] = ((value shr 8) and 0xff).toByte()
        }
        return bytes
    }

    @Test fun silenceFloorsAtMinusSixtyAndMapsToRecognizerMinimum() {
        val frame = ByteArray(1600)
        assertEquals(-60.0, PcmLevel.dbfs(frame, frame.size), 0.001)
        assertEquals(-2.0, PcmLevel.recognizerRmsDb(-60.0), 0.001)
    }

    @Test fun fullScaleSineIsMinusThreeDbfsAndNearRecognizerMaximum() {
        val frame = sine(1.0)
        assertEquals(-3.01, PcmLevel.dbfs(frame, frame.size), 0.05)
        assertEquals(9.4, PcmLevel.recognizerRmsDb(-3.01), 0.05)
    }

    @Test fun quietSpeechLandsMidRange() {
        val frame = sine(0.03) // about -33.5 dBFS RMS
        val dbfs = PcmLevel.dbfs(frame, frame.size)
        assertEquals(-33.5, dbfs, 0.1)
        assertEquals(3.3, PcmLevel.recognizerRmsDb(dbfs), 0.05)
    }

    @Test fun partialFrameUsesOnlyDeliveredBytes() {
        val frame = sine(1.0)
        val fullLevel = PcmLevel.dbfs(frame, frame.size)
        val halfLevel = PcmLevel.dbfs(frame, frame.size / 2)
        assertEquals(fullLevel, halfLevel, 0.1)
    }
}
