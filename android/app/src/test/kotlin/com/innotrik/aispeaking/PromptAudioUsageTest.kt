package com.innotrik.aispeaking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PromptAudioUsageTest {
    @Test fun phoneAloneKeepsEveryPromptOnOneStream() {
        // A vocabulary question (no flag), a word clip (media) and a MAIN
        // prompt on the handset (phone speaker) follow each other in one
        // conversation, so they must share one volume.
        val question = PromptAudioUsage.usesCallStream(false, false, false, false)
        val wordClip = PromptAudioUsage.usesCallStream(false, true, false, false)
        val mainPrompt = PromptAudioUsage.usesCallStream(true, false, false, false)

        assertFalse(question)
        assertEquals(question, wordClip)
        assertEquals(question, mainPrompt)
    }

    @Test fun activeScoCarriesPromptsOnTheCallStream() {
        assertTrue(PromptAudioUsage.usesCallStream(false, false, true, true))
        assertTrue(PromptAudioUsage.usesCallStream(false, true, true, true))
    }

    @Test fun ownedH20RouteKeepsThePromptOnTheCallStreamWhileScoComesUp() {
        assertTrue(PromptAudioUsage.usesCallStream(false, false, true, false))
        assertFalse(PromptAudioUsage.usesCallStream(false, true, true, false))
    }

    @Test fun phoneSpeakerPromptNeverUsesTheCallStream() {
        assertFalse(PromptAudioUsage.usesCallStream(true, false, true, true))
    }
}
