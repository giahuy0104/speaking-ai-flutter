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
        if (nowMs >= deadlineMs) return Result.TIMED_OUT
        if (!confirmed) {
            confirmedSinceMs = null
            return Result.WAITING
        }
        val since = confirmedSinceMs ?: nowMs.also { confirmedSinceMs = it }
        return if (nowMs - since >= settleMs) Result.READY else Result.WAITING
    }
}
