package com.innotrik.aispeaking

import org.junit.Assert.*
import org.junit.Test

class MediaPlaybackQuietGateTest {
    private class Harness {
        var now = 0L
        var active = false
        val tasks = mutableListOf<Pair<Long, () -> Unit>>()
        val gate = MediaPlaybackQuietGate({ active }, { now }, { delay, task -> tasks.add(now + delay to task) })
        fun advance(ms: Long) {
            val end = now + ms
            while (tasks.any { it.first <= end }) {
                val next = tasks.minBy { it.first }
                tasks.remove(next)
                now = next.first
                next.second()
            }
            now = end
        }
    }

    @Test fun quietMustRemainStableBeforeOpeningMicrophone() {
        val h = Harness()
        val results = mutableListOf<MediaPlaybackQuietGate.Result>()
        h.gate.awaitQuiet { results.add(it) }
        assertTrue(results.isEmpty())
        h.advance(50)
        h.active = true
        h.advance(50)
        h.active = false
        h.advance(100)
        assertTrue(results.isEmpty())
        h.advance(50)
        assertEquals(listOf(MediaPlaybackQuietGate.Result.QUIET), results)
    }

    @Test fun PreviousPlayerCleanupCanSettleWithoutRejectingTheTurn() {
        val h = Harness()
        h.active = true
        val results = mutableListOf<MediaPlaybackQuietGate.Result>()
        h.gate.awaitQuiet { results.add(it) }
        h.advance(300)
        h.active = false
        h.advance(150)
        assertEquals(listOf(MediaPlaybackQuietGate.Result.QUIET), results)
    }

    @Test fun PersistentPlaybackFailsOnceWithinTheBound() {
        val h = Harness()
        h.active = true
        val results = mutableListOf<MediaPlaybackQuietGate.Result>()
        h.gate.awaitQuiet { results.add(it) }
        h.advance(1000)
        assertEquals(listOf(MediaPlaybackQuietGate.Result.ACTIVE), results)
    }

    @Test fun CancelledCallbacksCannotCompleteAReplacementTurn() {
        val h = Harness()
        h.active = true
        val old = mutableListOf<MediaPlaybackQuietGate.Result>()
        val current = mutableListOf<MediaPlaybackQuietGate.Result>()
        h.gate.awaitQuiet { old.add(it) }
        h.advance(100)
        h.gate.cancel()
        h.active = false
        h.gate.awaitQuiet { current.add(it) }
        h.advance(1000)
        assertEquals(listOf(MediaPlaybackQuietGate.Result.CANCELLED), old)
        assertEquals(listOf(MediaPlaybackQuietGate.Result.QUIET), current)
    }
}
