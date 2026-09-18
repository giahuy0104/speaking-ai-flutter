package com.innotrik.aispeaking

import org.junit.Assert.*
import org.junit.Test

class H20ControlObservationTest {
    @Test fun observedMainShortKeepsExactRawBytes() {
        val bytes = byteArrayOf(1, 1, 0x7f, 1, 0, 0, 0, 0, 0, 0, 0, 0xff.toByte())
        val event = H20ControlObservation.bleMetadata(bytes)
        assertEquals("main", event["button"])
        assertEquals("shortPress", event["gesture"])
        assertEquals("observedV1", event["protocol"])
        assertEquals("ble", event["source"])
        assertEquals("01 01 7F 01 00 00 00 00 00 00 00 FF", event["rawPayload"])
    }

    @Test fun unknownAndDraftPacketsStayUnknownWithoutDiscardingRaw() {
        listOf(
            byteArrayOf(),
            byteArrayOf(1, 1, 0, 1),
            byteArrayOf(1, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0),
            byteArrayOf(1, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0),
        ).forEach { bytes ->
            val event = H20ControlObservation.bleMetadata(bytes)
            assertEquals("unknown", event["button"])
            assertEquals("unknown", event["gesture"])
            assertEquals("unknown", event["protocol"])
            assertNotNull(event["rawPayload"])
        }
    }

    @Test fun powerAndVolumeAreNotMediaCommands() {
        listOf(24, 25, 26, 164, 223, 224).forEach {
            assertNull(H20ControlObservation.mediaCommand(it))
        }
    }

    @Test fun mediaCodesDescribeCommandsNotPhysicalButtons() {
        assertEquals("nextTrack", H20ControlObservation.mediaCommand(87))
        assertEquals("previousTrack", H20ControlObservation.mediaCommand(88))
        assertEquals("togglePlayPause", H20ControlObservation.mediaCommand(85))
        assertEquals("headsetHook", H20ControlObservation.mediaCommand(79))
        assertNull(H20ControlObservation.mediaCommand(999))
    }

    @Test fun volumeCanBeObservedSeparatelyButPowerCannot() {
        assertEquals("volumeUp", H20ControlObservation.diagnosticVolumeKey(24))
        assertEquals("volumeDown", H20ControlObservation.diagnosticVolumeKey(25))
        assertNull(H20ControlObservation.diagnosticVolumeKey(26))
        assertNull(H20ControlObservation.diagnosticVolumeKey(87))
    }

    @Test fun downDoesNotInventShortBeforeLongOrInferLongFromElapsedTime() {
        assertEquals("unknown", H20ControlObservation.observedGesture(0, false))
        assertEquals("longPress", H20ControlObservation.observedGesture(0, true))
        assertEquals("release", H20ControlObservation.observedGesture(1, false))
        assertEquals("release", H20ControlObservation.observedGesture(1, true))
        assertEquals("unknown", H20ControlObservation.observedGesture(2, false))
    }

    @Test fun observerIsDisabledByDefaultAndOutsideForegroundContext() {
        val context = H20ControlContext()
        assertFalse(context.mediaObservationActive)
        context.foreground = true
        assertFalse(context.mediaObservationActive)
        context.learningActive = true
        assertTrue(context.mediaObservationActive)
        context.foreground = false
        assertFalse(context.mediaObservationActive)
        context.learningActive = false
        context.diagnosticsActive = true
        assertFalse(context.mediaObservationActive)
        context.foreground = true
        assertTrue(context.mediaObservationActive)
        context.diagnosticsActive = false
        assertFalse(context.mediaObservationActive)
    }

    @Test fun sameKeyFromActivityAndSessionIsDuplicateButDistinctActionsAreNot() {
        val duplicates = H20ControlKeyDuplicates()
        assertFalse(duplicates.isDuplicate("device:key:down:1:1:0"))
        assertTrue(duplicates.isDuplicate("device:key:down:1:1:0"))
        assertFalse(duplicates.isDuplicate("device:key:up:1:2:0"))
        assertFalse(duplicates.isDuplicate("device:key:down:3:3:0"))
    }

    @Test fun duplicateMemoryIsBoundedAndClearedWithContext() {
        val duplicates = H20ControlKeyDuplicates(capacity = 2)
        assertFalse(duplicates.isDuplicate("a"))
        assertFalse(duplicates.isDuplicate("b"))
        assertFalse(duplicates.isDuplicate("c"))
        assertTrue(duplicates.isDuplicate("b"))
        assertFalse(duplicates.isDuplicate("a"))
        duplicates.clear()
        assertFalse(duplicates.isDuplicate("a"))
    }
}
