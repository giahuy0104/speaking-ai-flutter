package com.innotrik.aispeaking

import org.junit.Assert.*
import org.junit.Test

class LessonAudioHandoffTest {
    private class Output : LessonAudioHandoff.Output {
        var releases = 0
        override fun release() { releases++ }
    }

    private class Harness {
        val timeouts = mutableListOf<() -> Unit>()
        val delays = mutableListOf<Long>()
        val reasons = mutableListOf<String>()
        val handoff = LessonAudioHandoff(
            schedule = { delay, action ->
                delays.add(delay)
                timeouts.add(action)
                val cancel: () -> Unit = { }
                cancel
            },
            diagnostic = { event, fields ->
                if (event == "lesson.handoff.stopped") reasons.add(fields["reason"] as String)
            },
        )
    }

    @Test fun timeoutReleasesOnlyItsOwnOutput() {
        val h = Harness()
        val first = Output()
        val old = h.handoff.begin { first }!!
        val second = Output()
        val next = h.handoff.begin { second }!!
        assertNotEquals(old, next)
        assertEquals(1, first.releases)
        h.timeouts[0]()
        h.handoff.end(old)
        assertEquals(0, second.releases)
        h.timeouts[1]()
        assertEquals(1, second.releases)
        assertEquals(listOf(3000L, 3000L), h.delays)
        assertEquals(listOf("replaced", "timeout"), h.reasons)
    }

    @Test fun explicitEndAndRouteStopAreIdempotent() {
        val h = Harness()
        val output = Output()
        val token = h.handoff.begin { output }!!
        h.handoff.end(token)
        h.handoff.stop("route_stopped")
        h.timeouts.single()()
        assertEquals(1, output.releases)
        assertEquals(listOf("replay_ready"), h.reasons)
    }

    @Test fun failedCreationLeavesNoOldOutputRunning() {
        val h = Harness()
        val output = Output()
        h.handoff.begin { output }
        assertNull(h.handoff.begin { throw IllegalStateException("unavailable") })
        assertEquals(1, output.releases)
        h.handoff.stop("route_stopped")
        assertEquals(1, output.releases)
    }

    @Test fun stoppingRouteReleasesCurrentOutputAndLeavesNewerTokenSafe() {
        val h = Harness()
        val first = Output()
        h.handoff.begin { first }
        h.handoff.stop("route_stopped")
        val second = Output()
        val next = h.handoff.begin { second }!!
        h.timeouts[0]()
        assertEquals(1, first.releases)
        assertEquals(0, second.releases)
        h.handoff.end(next)
        assertEquals(1, second.releases)
    }

    @Test fun schedulerFailureReleasesCreatedOutput() {
        val output = Output()
        val handoff = LessonAudioHandoff(
            schedule = { _, _ -> throw IllegalStateException("worker stopped") },
            diagnostic = { _, _ -> },
        )
        assertNull(handoff.begin { output })
        assertEquals(1, output.releases)
    }

    @Test fun delayedReplayEndCannotStopAReplacementOrSurviveRouteTeardown() {
        val h = Harness()
        val first = Output()
        val old = h.handoff.begin { first }!!
        h.handoff.endAfterReplayStarted(old)
        assertEquals(listOf(3000L, 100L), h.delays)
        assertEquals(0, first.releases)
        val second = Output()
        val next = h.handoff.begin { second }!!
        h.timeouts[1]()
        assertEquals(1, first.releases)
        assertEquals(0, second.releases)
        h.handoff.endAfterReplayStarted(next)
        h.handoff.stop("route_stopped")
        h.timeouts.last()()
        assertEquals(1, second.releases)
    }
}
