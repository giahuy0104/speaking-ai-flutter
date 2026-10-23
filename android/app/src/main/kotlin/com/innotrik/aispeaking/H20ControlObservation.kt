package com.innotrik.aispeaking

/** Observations, not a firmware decoder or a lesson-command mapper. */
internal object H20ControlObservation {
    private fun isLegacyMainPacket(bytes: ByteArray): Boolean =
        bytes.size == 12 &&
            (bytes[0].toInt() and 0xff) == 1 &&
            (bytes[1].toInt() and 0xff) == 1 &&
            (bytes[3].toInt() and 0xff) == 1

    private fun isHmD001Packet(bytes: ByteArray): Boolean =
        bytes.size == 12 &&
            (bytes[0].toInt() and 0xff) == 1 &&
            (bytes[1].toInt() and 0xff) in setOf(1, 2, 3, 4) &&
            (bytes[2].toInt() and 0xff) in setOf(1, 2) &&
            ((bytes[1].toInt() and 0xff) != 2 || (bytes[2].toInt() and 0xff) == 1) &&
            bytes[3].toInt() == 0 &&
            bytes[7].toInt() == 0 &&
            (bytes[6].toInt() and 0xff) <= 100

    fun isObservedMainPacket(bytes: ByteArray): Boolean =
        isLegacyMainPacket(bytes) ||
            (isHmD001Packet(bytes) && (bytes[1].toInt() and 0xff) == 1)

    fun batteryPercent(bytes: ByteArray): Int? {
        // HM-D001 reports its battery in every button packet, not only MAIN.
        if (!isLegacyMainPacket(bytes) && !isHmD001Packet(bytes)) return null
        val raw = (bytes[6].toInt() and 0xff) or ((bytes[7].toInt() and 0xff) shl 8)
        return raw.coerceIn(0, 100)
    }

    fun bleMetadata(bytes: ByteArray): Map<String, Any> {
        val legacy = isLegacyMainPacket(bytes)
        val hmD001 = isHmD001Packet(bytes)
        val button = if (hmD001) when (bytes[1].toInt() and 0xff) {
            1 -> "main"
            2 -> "power"
            3 -> "volumeUp"
            else -> "volumeDown"
        } else if (legacy) "main" else "unknown"
        return mapOf(
            "source" to "ble",
            "platform" to "android",
            "button" to button,
            "gesture" to if (hmD001) {
                if (bytes[2].toInt() == 1) "shortPress" else "longPress"
            } else if (legacy) "shortPress" else "unknown",
            "protocol" to if (hmD001) "observedHmD001" else if (legacy) "observedV1" else "unknown",
            "rawPayload" to bytes.joinToString(" ") {
                (it.toInt() and 0xff).toString(16).padStart(2, '0').uppercase()
            },
        )
    }

    // Android KEYCODE values. Keep this policy free of framework dependencies
    // so unit tests can verify that phone Power/Volume are never intercepted.
    fun mediaCommand(keyCode: Int): String? = when (keyCode) {
        79 -> "headsetHook"
        85 -> "togglePlayPause"
        86 -> "stop"
        87 -> "nextTrack"
        88 -> "previousTrack"
        89 -> "rewind"
        90 -> "fastForward"
        126 -> "play"
        127 -> "pause"
        else -> null
    }

    fun diagnosticVolumeKey(keyCode: Int): String? = when (keyCode) {
        24 -> "volumeUp"
        25 -> "volumeDown"
        else -> null
    }

    fun observedGesture(action: Int, nativeLongPress: Boolean): String = when {
        action == 1 -> "release"
        action == 0 && nativeLongPress -> "longPress"
        // DOWN alone cannot prove SHORT: it may subsequently become LONG.
        else -> "unknown"
    }
}

internal class H20ControlContext {
    var learningActive = false
    var diagnosticsActive = false
    var foreground = false
    val mediaObservationActive: Boolean
        get() = foreground && (learningActive || diagnosticsActive)
}

/** The same native KeyEvent can arrive at Activity and MediaSession. */
internal class H20ControlKeyDuplicates(private val capacity: Int = 64) {
    private val seen = linkedSetOf<String>()

    fun isDuplicate(fingerprint: String): Boolean {
        if (!seen.add(fingerprint)) return true
        while (seen.size > capacity) seen.remove(seen.first())
        return false
    }

    fun clear() = seen.clear()
}
