package com.innotrik.aispeaking

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptScoWaitTest {
    @Test fun ownedH20RouteWaitsForScoInsteadOfFallingBackToMedia() {
        assertTrue(PromptScoWait.shouldWait(false, true, false, 0))
        assertTrue(PromptScoWait.shouldWait(false, true, false, 900))
    }

    @Test fun waitIsBoundedSoAMissingRouteStillPlays() {
        assertFalse(PromptScoWait.shouldWait(false, true, false, PromptScoWait.MAX_WAIT_MS))
    }

    @Test fun activeScoOrNoOwnedRoutePlaysImmediately() {
        assertFalse(PromptScoWait.shouldWait(false, true, true, 0))
        assertFalse(PromptScoWait.shouldWait(false, false, false, 0))
    }

    @Test fun phoneSpeakerPromptNeverWaitsForSco() {
        assertFalse(PromptScoWait.shouldWait(true, true, false, 0))
    }
}
