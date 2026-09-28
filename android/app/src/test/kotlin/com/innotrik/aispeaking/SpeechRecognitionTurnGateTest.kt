package com.innotrik.aispeaking

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeechRecognitionTurnGateTest {
    @Test fun cancelledTurnCannotFailItsReplacement() {
        var generation = 1
        val old = SpeechRecognitionTurnGate(generation) { generation }
        assertTrue(old.accepts())
        generation += 1
        val replacement = SpeechRecognitionTurnGate(generation) { generation }
        assertFalse(old.accepts(terminal = true))
        assertFalse(old.accepts())
        assertTrue(replacement.accepts())
        assertTrue(replacement.accepts(terminal = true))
    }

    @Test fun terminalResultOrErrorDeliveredOnce() {
        val turn = SpeechRecognitionTurnGate(1) { 1 }
        assertTrue(turn.accepts())
        assertTrue(turn.accepts(terminal = true))
        assertFalse(turn.accepts(terminal = true))
        assertFalse(turn.accepts())
    }
}
