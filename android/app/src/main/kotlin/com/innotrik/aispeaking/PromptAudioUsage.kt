package com.innotrik.aispeaking

/**
 * Android keeps a separate volume for call audio and for media audio, and a
 * handset plays call audio through its earpiece. A prompt therefore uses the
 * call stream only while the H20 call route carries it. On the phone alone
 * every prompt shares the media stream, so two lines of one conversation
 * cannot come out at two levels.
 */
internal object PromptAudioUsage {
    fun usesCallStream(
        forcePhoneSpeaker: Boolean,
        forceMediaPlayback: Boolean,
        h20RouteOwned: Boolean,
        scoActive: Boolean,
    ): Boolean =
        !forcePhoneSpeaker && (scoActive || (h20RouteOwned && !forceMediaPlayback))
}
