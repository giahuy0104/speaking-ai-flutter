package com.innotrik.aispeaking

import org.junit.Assert.*
import org.junit.Test

class H20ControlObservationTest {
    @Test fun hmD001PacketsMapOnlyObservedButtons() {
        val mainShort = byteArrayOf(1, 1, 1, 0, 0x1c, 0, 0x4f, 0, 0, 0, 0, 0)
        val mainLong = byteArrayOf(1, 1, 2, 0, 0x1d, 0, 0x4f, 0, 0, 0, 0, 0)
        val downLong = byteArrayOf(1, 4, 2, 0, 0x1e, 0, 0x4f, 0, 0, 0, 0, 0)
        val upLong = byteArrayOf(1, 3, 2, 0, 0x1f, 0, 0x4f, 0, 0, 0, 0, 0)
        val powerShort = byteArrayOf(1, 2, 1, 0, 0x29, 0, 0x47, 0, 0xf1.toByte(), 0x60, 0x36, 0)
        assertEquals("shortPress", H20ControlObservation.bleMetadata(mainShort)["gesture"])
        assertEquals("longPress", H20ControlObservation.bleMetadata(mainLong)["gesture"])
        assertEquals("volumeDown", H20ControlObservation.bleMetadata(downLong)["button"])
        assertEquals("volumeUp", H20ControlObservation.bleMetadata(upLong)["button"])
        assertEquals("power", H20ControlObservation.bleMetadata(powerShort)["button"])
        assertEquals("shortPress", H20ControlObservation.bleMetadata(powerShort)["gesture"])
        assertEquals("observedHmD001", H20ControlObservation.bleMetadata(upLong)["protocol"])
        assertTrue(H20ControlObservation.isObservedMainPacket(mainShort))
        assertTrue(H20ControlObservation.isObservedMainPacket(mainLong))
        assertFalse(H20ControlObservation.isObservedMainPacket(downLong))
        assertFalse(H20ControlObservation.isObservedMainPacket(powerShort))
        assertEquals(79, H20ControlObservation.batteryPercent(mainLong))
    }

    @Test fun observedMainShortKeepsExactRawBytes() {
        val bytes = byteArrayOf(1, 1, 0x7f, 1, 0, 0, 0, 0, 0, 0, 0, 0xff.toByte())
        val event = H20ControlObservation.bleMetadata(bytes)
        assertEquals("main", event["button"])
        assertEquals("shortPress", event["gesture"])
        assertEquals("observedV1", event["protocol"])
        assertEquals("ble", event["source"])
        assertEquals("01 01 7F 01 00 00 00 00 00 00 00 FF", event["rawPayload"])
    }

    @Test fun observedMainPacketCarriesBatteryPercentage() {
        val bytes = byteArrayOf(1, 1, 0x19, 1, 1, 0, 0x14, 0, 0, 0, 0, 0)
        assertEquals(20, H20ControlObservation.batteryPercent(bytes))
        assertNull(H20ControlObservation.batteryPercent(byteArrayOf(1, 1, 0x19, 2)))
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
