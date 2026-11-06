package com.innotrik.aispeaking

/** A conservative playback check; absence of music is not proof of silence. */
internal class MediaPlaybackQuietGate(
    private val isMusicActive: () -> Boolean,
    private val nowMs: () -> Long,
    private val schedule: (Long, () -> Unit) -> Unit,
) {
    enum class Result { QUIET, ACTIVE, CANCELLED }
    private var pending: ((Result) -> Unit)? = null
    private var generation = 0L

    fun awaitQuiet(completion: (Result) -> Unit) {
        cancel()
        val ticket = ++generation
        pending = completion
        val started = nowMs()
        var quietSince: Long? = null
        fun check() {
            if (ticket != generation || pending == null) return
            val now = nowMs()
            val active = isMusicActive()
            if (active) {
                quietSince = null
            } else if (quietSince == null) {
                quietSince = now
            }
            val outcome = when {
                !active && now - quietSince!! >= 100L -> Result.QUIET
                now - started >= 750L -> Result.ACTIVE
                else -> null
            }
            if (outcome != null) {
                val callback = pending
                pending = null
                callback?.invoke(outcome)
            } else {
                schedule(50L, ::check)
            }
        }
        check()
    }

    fun cancel() {
        generation++
        val callback = pending
        pending = null
        callback?.invoke(Result.CANCELLED)
    }
}
