package com.innotrik.aispeaking

import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** One process-wide focus request, retained until every unique operation releases it. */
class AndroidAudioFocusCoordinator(private val audioManager: AudioManager) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val owners = mutableSetOf<String>()
    private var request: AudioFocusRequest? = null
    private var listener: AudioManager.OnAudioFocusChangeListener? = null
    private var generation = 0L
    private var ownerSequence = 0L
    var onInterrupted: (String) -> Unit = {}

    val isHeld: Boolean get() = owners.isNotEmpty()

    fun newOwner(prefix: String): String = "$prefix:${++ownerSequence}"

    fun acquire(ownerId: String, transientExclusive: Boolean = true): Boolean {
        if (ownerId.isBlank()) return false
        if (owners.isNotEmpty()) {
            owners.add(ownerId)
            return true
        }
        val expectedGeneration = ++generation
        val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
            if (expectedGeneration != generation || change >= 0) return@OnAudioFocusChangeListener
            // Invalidate before notifying consumers: a late GAIN or callback from
            // this request must never restart a paused lesson or retire a new turn.
            interrupt("audio_focus_loss")
        }
        listener = focusListener
        val gain = if (transientExclusive) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            else AudioManager.AUDIOFOCUS_GAIN
        val granted = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(gain)
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .setWillPauseWhenDucked(true)
                    .setOnAudioFocusChangeListener(focusListener, mainHandler)
                    .build()
                request = focusRequest
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, gain)
            }
        }.getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        if (granted != AudioManager.AUDIOFOCUS_REQUEST_GRANTED || expectedGeneration != generation) {
            releaseAll()
            return false
        }
        owners.add(ownerId)
        return true
    }

    fun release(ownerId: String) {
        if (owners.remove(ownerId) && owners.isEmpty()) releaseAll()
    }

    fun interrupt(reason: String) {
        releaseAll()
        onInterrupted(reason)
    }

    fun releaseAll() {
        generation += 1
        owners.clear()
        val oldRequest = request
        val oldListener = listener
        request = null
        listener = null
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && oldRequest != null) {
                audioManager.abandonAudioFocusRequest(oldRequest)
            } else if (oldListener != null) {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(oldListener)
            }
        }
    }
}
