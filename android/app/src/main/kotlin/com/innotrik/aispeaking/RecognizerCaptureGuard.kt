package com.innotrik.aispeaking

/**
 * Remembers when a recognizer session that captured the microphone itself on
 * the HM-D001 SCO route ended. Google's service restores the audio mode a
 * little after its last callback, so [HfpAudioBridge] treats a route request
 * inside this window as "wait for that teardown first".
 */
internal object RecognizerCaptureGuard {
    const val HOLD_MS = 1200L

    @Volatile
    private var untilMs = 0L

    fun markEnded(nowMs: Long) {
        untilMs = nowMs + HOLD_MS
    }

    fun remainingMs(nowMs: Long): Long = (untilMs - nowMs).coerceAtLeast(0L)

    fun reset() {
        untilMs = 0L
    }
}
