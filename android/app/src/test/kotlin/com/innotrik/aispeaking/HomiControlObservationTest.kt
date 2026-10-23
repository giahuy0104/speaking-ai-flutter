package com.innotrik.aispeaking

import org.junit.Assert.*
import org.junit.Test

class HomiControlObservationTest {
    @Test fun hmD001PacketsMapOnlyObservedButtons() {
        val mainShort = byteArrayOf(1, 1, 1, 0, 0x1c, 0, 0x4f, 0, 0, 0, 0, 0)
        val mainLong = byteArrayOf(1, 1, 2, 0, 0x1d, 0, 0x4f, 0, 0, 0, 0, 0)
        val downLong = byteArrayOf(1, 4, 2, 0, 0x1e, 0, 0x4f, 0, 0, 0, 0, 0)
        val upLong = byteArrayOf(1, 3, 2, 0, 0x1f, 0, 0x4f, 0, 0, 0, 0, 0)
        val powerShort = byteArrayOf(1, 2, 1, 0, 0x29, 0, 0x47, 0, 0xf1.toByte(), 0x60, 0x36, 0)
        assertEquals("shortPress", HomiControlObservation.bleMetadata(mainShort)["gesture"])
        assertEquals("longPress", HomiControlObservation.bleMetadata(mainLong)["gesture"])
        assertEquals("volumeDown", HomiControlObservation.bleMetadata(downLong)["button"])
        assertEquals("volumeUp", HomiControlObservation.bleMetadata(upLong)["button"])
        assertEquals("power", HomiControlObservation.bleMetadata(powerShort)["button"])
        assertEquals("shortPress", HomiControlObservation.bleMetadata(powerShort)["gesture"])
        assertEquals("observedHmD001", HomiControlObservation.bleMetadata(upLong)["protocol"])
        assertTrue(HomiControlObservation.isObservedMainPacket(mainShort))
        assertTrue(HomiControlObservation.isObservedMainPacket(mainLong))
        assertFalse(HomiControlObservation.isObservedMainPacket(downLong))
        assertFalse(HomiControlObservation.isObservedMainPacket(powerShort))
        assertEquals(79, HomiControlObservation.batteryPercent(mainLong))
        assertEquals(79, HomiControlObservation.batteryPercent(downLong))
        assertEquals(71, HomiControlObservation.batteryPercent(powerShort))
    }

    @Test fun observedHmD001MainShortKeepsExactRawBytes() {
        val bytes = byteArrayOf(1, 1, 1, 0, 0x7f, 0, 79, 0, 0, 0, 0, 0)
        val event = HomiControlObservation.bleMetadata(bytes)
        assertEquals("main", event["button"])
        assertEquals("shortPress", event["gesture"])
        assertEquals("observedHmD001", event["protocol"])
        assertEquals("ble", event["source"])
        assertEquals("01 01 01 00 7F 00 4F 00 00 00 00 00", event["rawPayload"])
    }

    @Test fun observedMainPacketCarriesBatteryPercentage() {
        val bytes = byteArrayOf(1, 1, 1, 0, 0x19, 0, 0x14, 0, 0, 0, 0, 0)
        assertEquals(20, HomiControlObservation.batteryPercent(bytes))
        assertNull(HomiControlObservation.batteryPercent(byteArrayOf(1, 1, 0x19, 2)))
    }

    @Test fun unknownAndDraftPacketsStayUnknownWithoutDiscardingRaw() {
        listOf(
            byteArrayOf(),
            byteArrayOf(1, 1, 0, 1),
            byteArrayOf(1, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0),
            byteArrayOf(1, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0),
        ).forEach { bytes ->
            val event = HomiControlObservation.bleMetadata(bytes)
            assertEquals("unknown", event["button"])
            assertEquals("unknown", event["gesture"])
            assertEquals("unknown", event["protocol"])
            assertNotNull(event["rawPayload"])
        }
    }

    @Test fun powerAndVolumeAreNotMediaCommands() {
        listOf(24, 25, 26, 164, 223, 224).forEach {
            assertNull(HomiControlObservation.mediaCommand(it))
        }
    }

    @Test fun mediaCodesDescribeCommandsNotPhysicalButtons() {
        assertEquals("nextTrack", HomiControlObservation.mediaCommand(87))
        assertEquals("previousTrack", HomiControlObservation.mediaCommand(88))
        assertEquals("togglePlayPause", HomiControlObservation.mediaCommand(85))
        assertEquals("headsetHook", HomiControlObservation.mediaCommand(79))
        assertNull(HomiControlObservation.mediaCommand(999))
    }

    @Test fun volumeCanBeObservedSeparatelyButPowerCannot() {
        assertEquals("volumeUp", HomiControlObservation.diagnosticVolumeKey(24))
        assertEquals("volumeDown", HomiControlObservation.diagnosticVolumeKey(25))
        assertNull(HomiControlObservation.diagnosticVolumeKey(26))
        assertNull(HomiControlObservation.diagnosticVolumeKey(87))
    }

    @Test fun downDoesNotInventShortBeforeLongOrInferLongFromElapsedTime() {
        assertEquals("unknown", HomiControlObservation.observedGesture(0, false))
        assertEquals("longPress", HomiControlObservation.observedGesture(0, true))
        assertEquals("release", HomiControlObservation.observedGesture(1, false))
        assertEquals("release", HomiControlObservation.observedGesture(1, true))
        assertEquals("unknown", HomiControlObservation.observedGesture(2, false))
    }

    @Test fun observerIsDisabledByDefaultAndOutsideForegroundContext() {
        val context = HomiControlContext()
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
        val duplicates = HomiControlKeyDuplicates()
        assertFalse(duplicates.isDuplicate("device:key:down:1:1:0"))
        assertTrue(duplicates.isDuplicate("device:key:down:1:1:0"))
        assertFalse(duplicates.isDuplicate("device:key:up:1:2:0"))
        assertFalse(duplicates.isDuplicate("device:key:down:3:3:0"))
    }

    @Test fun duplicateMemoryIsBoundedAndClearedWithContext() {
        val duplicates = HomiControlKeyDuplicates(capacity = 2)
        assertFalse(duplicates.isDuplicate("a"))
        assertFalse(duplicates.isDuplicate("b"))
        assertFalse(duplicates.isDuplicate("c"))
        assertTrue(duplicates.isDuplicate("b"))
        assertFalse(duplicates.isDuplicate("a"))
        duplicates.clear()
        assertFalse(duplicates.isDuplicate("a"))
    }
}
