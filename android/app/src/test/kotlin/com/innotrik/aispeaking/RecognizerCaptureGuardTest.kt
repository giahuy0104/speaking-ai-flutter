package com.innotrik.aispeaking

import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class RecognizerCaptureGuardTest {
    @Before fun reset() = RecognizerCaptureGuard.reset()

    @Test fun noSessionMeansNoHold() {
        assertEquals(0L, RecognizerCaptureGuard.remainingMs(10_000L))
    }

    @Test fun holdCoversTheWindowAfterASession() {
        RecognizerCaptureGuard.markEnded(1_000L)
        assertEquals(1_200L, RecognizerCaptureGuard.remainingMs(1_000L))
        assertEquals(400L, RecognizerCaptureGuard.remainingMs(1_800L))
        assertEquals(0L, RecognizerCaptureGuard.remainingMs(2_200L))
        assertEquals(0L, RecognizerCaptureGuard.remainingMs(5_000L))
    }

    @Test fun aLaterSessionExtendsTheHold() {
        RecognizerCaptureGuard.markEnded(1_000L)
        RecognizerCaptureGuard.markEnded(1_500L)
        assertEquals(700L, RecognizerCaptureGuard.remainingMs(2_000L))
    }
}
