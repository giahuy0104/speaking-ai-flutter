package com.innotrik.aispeaking

/**
 * A prompt or ready cue picks its audio route once, when it starts. While the
 * app owns the H20 route but SCO is momentarily down, give SCO a short grace
 * period instead of sending the whole clip to the phone speaker.
 */
internal object PromptScoWait {
    const val POLL_MS = 100L
    const val MAX_WAIT_MS = 1000L

    fun shouldWait(
        forcePhoneSpeaker: Boolean,
        h20RouteOwned: Boolean,
        scoActive: Boolean,
        waitedMs: Long,
    ): Boolean =
        !forcePhoneSpeaker && h20RouteOwned && !scoActive && waitedMs < MAX_WAIT_MS
}
