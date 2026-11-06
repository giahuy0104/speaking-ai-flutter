package com.innotrik.aispeaking

import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioTrack

/** Owns only the bounded silent output between a lesson take and its replay. */
internal class LessonAudioHandoff(
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val diagnostic: (String, Map<String, Any?>) -> Unit,
) {
    internal interface Output {
        fun release()
    }

    private data class Active(
        val token: Long,
        val output: Output,
        var cancelTimeout: (() -> Unit)? = null,
        var cancelEnd: (() -> Unit)? = null,
    )
    private var sequence = 0L
    private var active: Active? = null

    fun begin(create: () -> Output): Long? {
        stop("replaced")
        val token = ++sequence
        try {
            val next = Active(token, create())
            active = next
            next.cancelTimeout = schedule(3000L) { end(token, "timeout") }
            diagnostic("lesson.handoff.started", mapOf("token" to token, "maximumMs" to 3000))
            return token
        } catch (_: Exception) {
            end(token, "unavailable")
            return null
        }
    }

    fun end(token: Long, reason: String = "replay_ready") {
        val current = active ?: return
        if (current.token != token) return
        active = null
        runCatching { current.cancelTimeout?.invoke() }
        runCatching { current.cancelEnd?.invoke() }
        runCatching { current.output.release() }
        diagnostic("lesson.handoff.stopped", mapOf("token" to token, "reason" to reason))
    }

    fun endAfterReplayStarted(token: Long) {
        val current = active ?: return
        if (current.token != token) return
        // Dart's play-start reply can precede the hardware track by a few ms.
        // Keep a short overlap without delaying its MethodChannel response.
        runCatching { current.cancelEnd?.invoke() }
        try {
            current.cancelEnd = schedule(100L) { end(token) }
        } catch (_: Exception) {
            end(token)
        }
    }

    fun stop(reason: String) {
        active?.let { end(it.token, reason) }
    }
}

/** No focus, microphone, mode or route ownership is acquired by this output. */
internal fun createLessonHandoffOutput(device: AudioDeviceInfo): LessonAudioHandoff.Output =
    createLessonHandoffOutput { it.setPreferredDevice(device) }

internal fun createLessonHandoffOutput(selectOutput: (AudioTrack) -> Boolean): LessonAudioHandoff.Output {
    var track: AudioTrack? = null
    try {
        val frames = 1600
        val silence = ByteArray(frames * 2)
        val output = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(16000)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(frames * 2)
            .build()
        track = output
        check(selectOutput(output))
        check(output.write(silence, 0, silence.size) == silence.size)
        // Static tracks remain STATE_NO_STATIC_DATA until the first write.
        check(output.state == AudioTrack.STATE_INITIALIZED)
        check(output.setLoopPoints(0, frames, -1) == AudioTrack.SUCCESS)
        output.play()
        check(output.playState == AudioTrack.PLAYSTATE_PLAYING)
        return object : LessonAudioHandoff.Output {
            override fun release() {
                try {
                    output.stop()
                } finally {
                    output.release()
                }
            }
        }
    } catch (error: Exception) {
        track?.let { output ->
            runCatching { output.stop() }
            runCatching { output.release() }
        }
        throw error
    }
}
