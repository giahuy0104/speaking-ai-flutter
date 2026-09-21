package com.innotrik.aispeaking

import org.junit.Assert.assertEquals
import org.junit.Test

class HfpRouteReadinessTest {
    @Test fun transientDisconnectDoesNotFinishOrCancelNegotiation() {
        val route = HfpRouteReadiness(0)
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(45, false))
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(300, true))
        assertEquals(HfpRouteReadiness.Result.READY, route.poll(500, true))
    }

    @Test fun droppedRouteDuringSettleMustBeConfirmedAgain() {
        val route = HfpRouteReadiness(0)
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(100, true))
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(200, false))
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(300, true))
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(400, true))
        assertEquals(HfpRouteReadiness.Result.READY, route.poll(500, true))
    }

    @Test fun unstableRouteCannotLeaveStartPendingForever() {
        val route = HfpRouteReadiness(0)
        for (time in 0L..4900L step 100) route.poll(time, time % 200L == 0L)
        assertEquals(HfpRouteReadiness.Result.TIMED_OUT, route.poll(5000, true))
    }

    @Test fun activeRouteCanRecoverInsideTheBluetoothGraceWindow() {
        val route = HfpRouteReadiness(0, timeoutMs = 1500, settleMs = 150)
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(700, false))
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(900, true))
        assertEquals(HfpRouteReadiness.Result.READY, route.poll(1100, true))
    }

    @Test fun persistentActiveRouteLossExpiresTheRecoveryWindow() {
        val route = HfpRouteReadiness(0, timeoutMs = 1500, settleMs = 150)
        assertEquals(HfpRouteReadiness.Result.WAITING, route.poll(1400, false))
        assertEquals(HfpRouteReadiness.Result.TIMED_OUT, route.poll(1500, false))
    }
}
