package com.innotrik.aispeaking

import java.util.ArrayDeque
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HfpRouteDispatchTest {
    private class Queue : Executor {
        private val commands = ArrayDeque<Runnable>()
        var running = false
            private set

        override fun execute(command: Runnable) { commands.addLast(command) }

        fun next() {
            running = true
            try { commands.removeFirst().run() } finally { running = false }
        }

        fun isEmpty() = commands.isEmpty()
    }

    @Test fun platformRequestReturnsBeforeBlockingRouteQueryStarts() {
        val route = Queue()
        val platform = Queue()
        val dispatch = HfpRouteDispatch(route, platform) { route.running }
        var queried = false
        dispatch.run { assertTrue(route.running); queried = true }
        assertFalse(queried)
        route.next()
        assertTrue(queried)
    }

    @Test fun statusIsReadOnceOnRouteWorkerAndDeliveredOnlyOnPlatformThread() {
        val route = Queue()
        val platform = Queue()
        val dispatch = HfpRouteDispatch(route, platform) { route.running }
        var queryCount = 0
        var received: Int? = null
        dispatch.publish(
            readRoute = { assertTrue(route.running); ++queryCount },
            deliver = { assertTrue(platform.running); received = it },
        )
        assertEquals(0, queryCount)
        assertEquals(null, received)
        route.next()
        assertEquals(1, queryCount)
        assertEquals(null, received)
        platform.next()
        assertEquals(1, received)
    }

    @Test fun nestedRouteWorkPreservesOrderWithoutRequeueingOrDeadlocking() {
        val route = Queue()
        val dispatch = HfpRouteDispatch(route, Queue()) { route.running }
        val events = mutableListOf<String>()
        dispatch.run {
            events += "start"
            dispatch.run { events += "confirm" }
            events += "complete"
        }
        dispatch.run { events += "stop" }
        route.next()
        assertEquals(listOf("start", "confirm", "complete"), events)
        route.next()
        assertEquals(listOf("start", "confirm", "complete", "stop"), events)
        assertTrue(route.isEmpty())
    }

    @Test fun cancelledSubscriberCanRejectAlreadyQueuedSnapshot() {
        val route = Queue()
        val platform = Queue()
        val dispatch = HfpRouteDispatch(route, platform) { route.running }
        var subscribed = true
        var delivered = false
        dispatch.publish(readRoute = { "confirmed" }, deliver = {
            if (subscribed) delivered = true
        })
        route.next()
        subscribed = false
        platform.next()
        assertFalse(delivered)
    }

    @Test fun channelReplyCannotOvertakeQueuedRouteStatus() {
        val route = Queue()
        val platform = Queue()
        val dispatch = HfpRouteDispatch(route, platform) { route.running }
        val events = mutableListOf<String>()
        dispatch.run {
            dispatch.publish(readRoute = { "connecting" }, deliver = { events += it })
            dispatch.publish(readRoute = { "ready" }, deliver = { events += it })
            dispatch.complete { events += "reply" }
        }
        route.next()
        assertTrue(events.isEmpty())
        repeat(3) { platform.next() }
        assertEquals(listOf("connecting", "ready", "reply"), events)
    }
}
