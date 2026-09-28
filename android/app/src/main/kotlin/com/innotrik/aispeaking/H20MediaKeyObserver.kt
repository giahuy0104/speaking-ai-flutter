package com.innotrik.aispeaking

import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent

/** Scoped diagnostic adapter. Never requests audio focus or changes an audio route. */
internal class H20MediaKeyObserver(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val scope = H20ControlContext()
    private val duplicates = H20ControlKeyDuplicates()
    private var session: MediaSession? = null
    val active: Boolean get() = scope.mediaObservationActive

    fun setControlContext(learningActive: Boolean, diagnosticsActive: Boolean) {
        scope.learningActive = learningActive
        scope.diagnosticsActive = diagnosticsActive
        updateSession()
    }

    fun setForeground(foreground: Boolean) {
        scope.foreground = foreground
        updateSession()
    }

    private fun updateSession() {
        if (!active) {
            session?.isActive = false
            session?.release()
            session = null
            duplicates.clear()
            return
        }
        if (session != null) return
        session = MediaSession(context, "HomiH20ControlDiagnostics").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    if (mediaButtonIntent.action != Intent.ACTION_MEDIA_BUTTON) return false
                    val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                    } ?: return false
                    return observe(key, "mediaSession")
                }

                override fun onPlay() = observeCommand("play")
                override fun onPause() = observeCommand("pause")
                override fun onStop() = observeCommand("stop")
                override fun onSkipToNext() = observeCommand("nextTrack")
                override fun onSkipToPrevious() = observeCommand("previousTrack")
                override fun onFastForward() = observeCommand("fastForward")
                override fun onRewind() = observeCommand("rewind")
            }, Handler(Looper.getMainLooper()))
            @Suppress("DEPRECATION")
            setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setPlaybackState(PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or
                        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND,
                )
                // This adapter does not own a player; never claim playback.
                .setState(PlaybackState.STATE_PAUSED, 0L, 0f)
                .build())
            isActive = true
        }
    }

    fun observe(key: KeyEvent, receiver: String): Boolean {
        if (!active) return false
        val mediaCommand = H20ControlObservation.mediaCommand(key.keyCode)
        val volumeKey = if (scope.diagnosticsActive && receiver == "activity") {
            H20ControlObservation.diagnosticVolumeKey(key.keyCode)
        } else null
        val command = mediaCommand ?: volumeKey ?: return false
        val holdMs = (key.eventTime - key.downTime).coerceAtLeast(0)
        val duplicate = duplicates.isDuplicate(
            "${key.deviceId}:${key.keyCode}:${key.action}:${key.downTime}:${key.eventTime}:${key.repeatCount}",
        )
        emit(baseEvent(command) + mapOf(
            "gesture" to H20ControlObservation.observedGesture(key.action, key.isLongPress),
            "deviceId" to "android-input:${key.deviceId}",
            "keyCode" to key.keyCode,
            "action" to key.action,
            "repeatCount" to key.repeatCount,
            "holdDurationMs" to holdMs,
            "nativeLongPress" to key.isLongPress,
            "externalInputDevice" to (key.device?.isExternal == true),
            "receiver" to receiver,
            "duplicate" to duplicate,
            "rawPayload" to "keyCode=${key.keyCode} action=${key.action} repeat=${key.repeatCount} " +
                "holdMs=$holdMs flags=${key.flags} source=${key.source} receiver=$receiver",
        ))
        // Volume keys are observation-only, never captured by MediaSession.
        return mediaCommand != null
    }

    private fun observeCommand(command: String) {
        if (!active) return
        emit(baseEvent(command) + mapOf(
            "receiver" to "mediaSessionCommand",
            "rawPayload" to "MediaSession.$command",
        ))
    }

    private fun baseEvent(command: String): Map<String, Any?> = mapOf(
        "type" to "controlObservation",
        "source" to "androidMediaKey",
        "platform" to "android",
        // A media command is not proof of a physical H20 button or gesture.
        "button" to "unknown",
        "gesture" to "unknown",
        "protocol" to "unknown",
        "mediaCommand" to command,
        "receivedAtEpochMs" to System.currentTimeMillis(),
        "duplicate" to false,
    )

    fun dispose() {
        scope.learningActive = false
        scope.diagnosticsActive = false
        scope.foreground = false
        updateSession()
    }
}
