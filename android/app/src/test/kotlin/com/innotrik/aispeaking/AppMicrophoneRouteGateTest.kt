package com.innotrik.aispeaking

import org.junit.Assert.assertEquals
import org.junit.Test

class AppMicrophoneRouteGateTest {
    @Test fun phoneCaptureKeepsSystemSelectedInput() {
        val gate = AppMicrophoneRouteGate(null)
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(null, 0))
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(7, 2000))
    }

    @Test fun scoStartupDiscardsUnconfirmedPhoneFramesUntilSelectedInputArrives() {
        val gate = AppMicrophoneRouteGate(42)
        assertEquals(AppMicrophoneRouteGate.Decision.WAIT, gate.check(null, 0))
        assertEquals(AppMicrophoneRouteGate.Decision.WAIT, gate.check(7, 100))
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(42, 300))
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(42, 5000))
    }

    @Test fun unavailableScoDoesNotFallBackToPhoneMicrophone() {
        for (actual in listOf(null, 7)) {
            val gate = AppMicrophoneRouteGate(42)
            assertEquals(AppMicrophoneRouteGate.Decision.WAIT, gate.check(actual, 1499))
            assertEquals(AppMicrophoneRouteGate.Decision.FAIL, gate.check(actual, 1500))
        }
    }

    @Test fun disconnectedHeadsetCannotContinueWithPhoneFrames() {
        val gate = AppMicrophoneRouteGate(42)
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(42, 10))
        assertEquals(AppMicrophoneRouteGate.Decision.FAIL, gate.check(7, 20))
    }

    @Test fun lostConfirmedRouteFailsImmediatelyEvenDuringStartupGrace() {
        val gate = AppMicrophoneRouteGate(42)
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, gate.check(42, 10))
        assertEquals(AppMicrophoneRouteGate.Decision.FAIL, gate.check(null, 11))
    }

    @Test fun replacementTurnHasItsOwnRouteConfirmation() {
        val old = AppMicrophoneRouteGate(42)
        val replacement = AppMicrophoneRouteGate(53)
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, old.check(42, 0))
        assertEquals(AppMicrophoneRouteGate.Decision.WAIT, replacement.check(null, 0))
        assertEquals(AppMicrophoneRouteGate.Decision.WAIT, replacement.check(42, 100))
        assertEquals(AppMicrophoneRouteGate.Decision.ACCEPT, replacement.check(53, 200))
    }
}
