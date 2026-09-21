package com.innotrik.aispeaking

/** A route must settle continuously, and every negotiation has a deadline. */
internal class HfpRouteReadiness(
    startedAtMs: Long,
    private val timeoutMs: Long = 5000L,
    private val settleMs: Long = 150L,
) {
    enum class Result { WAITING, READY, TIMED_OUT }

    private val deadlineMs = startedAtMs + timeoutMs
    private var confirmedSinceMs: Long? = null

    fun poll(nowMs: Long, confirmed: Boolean): Result {
        if (!confirmed) {
            confirmedSinceMs = null
        } else {
            val since = confirmedSinceMs ?: nowMs.also { confirmedSinceMs = it }
            if (nowMs - since >= settleMs) return Result.READY
        }
        // Accept a route that was already confirmed before the deadline even
        // when an OEM Binder call delayed this poll until just afterwards.
        return if (nowMs >= deadlineMs) Result.TIMED_OUT else Result.WAITING
    }
}
