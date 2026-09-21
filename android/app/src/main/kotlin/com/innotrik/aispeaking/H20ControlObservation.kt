package com.innotrik.aispeaking

/** Observations, not a firmware decoder or a lesson-command mapper. */
internal object H20ControlObservation {
    fun isObservedMainPacket(bytes: ByteArray): Boolean =
        bytes.size == 12 &&
            (bytes[0].toInt() and 0xff) == 1 &&
            (bytes[1].toInt() and 0xff) == 1 &&
            (bytes[3].toInt() and 0xff) == 1

    fun batteryPercent(bytes: ByteArray): Int? {
        if (!isObservedMainPacket(bytes)) return null
        val raw = (bytes[6].toInt() and 0xff) or ((bytes[7].toInt() and 0xff) shl 8)
        return raw.coerceIn(0, 100)
    }

    fun bleMetadata(bytes: ByteArray): Map<String, Any> {
        val observed = isObservedMainPacket(bytes)
        return mapOf(
            "source" to "ble",
            "platform" to "android",
            "button" to if (observed) "main" else "unknown",
            "gesture" to if (observed) "shortPress" else "unknown",
            "protocol" to if (observed) "observedV1" else "unknown",
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
