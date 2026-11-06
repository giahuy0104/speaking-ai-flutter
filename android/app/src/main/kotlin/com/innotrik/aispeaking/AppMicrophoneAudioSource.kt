package com.innotrik.aispeaking

import android.media.AudioFormat
import android.media.AudioDeviceInfo
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Captures the selected microphone inside the app and streams it to the
 * recognizer through an `EXTRA_AUDIO_SOURCE` pipe, keeping microphone and
 * audio focus ownership in the same process.
 */
internal class AppMicrophoneAudioSource(
    private val sampleRate: Int,
    private val onFrame: (buffer: ByteArray, count: Int) -> Unit,
    private val preferredInput: AudioDeviceInfo? = null,
    private val onRouteReady: (deviceId: Int?, deviceType: Int?) -> Unit = { _, _ -> },
    private val onFailure: () -> Unit = {},
) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private var writeSide: ParcelFileDescriptor? = null

    @Volatile
    private var running = false

    /**
     * Opens the microphone and returns the descriptor the recognizer reads, or
     * null when the microphone or the requested input could not be opened.
     */
    fun start(): ParcelFileDescriptor? {
        val minBuffer =
            AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
        if (minBuffer <= 0) return null
        val recorder =
            try {
                AudioRecord(
                    if (preferredInput != null) MediaRecorder.AudioSource.VOICE_COMMUNICATION
                    else MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minBuffer, frameBytes * 4),
                )
            } catch (_: Exception) {
                return null
            }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return null
        }
        val routeAccepted = try {
            preferredInput == null || recorder.setPreferredDevice(preferredInput)
        } catch (_: RuntimeException) {
            false
        }
        if (!routeAccepted) {
            recorder.release()
            return null
        }
        val pipe =
            try {
                ParcelFileDescriptor.createPipe()
            } catch (_: Exception) {
                recorder.release()
                return null
            }
        try {
            recorder.startRecording()
        } catch (_: RuntimeException) {
            recorder.release()
            pipe.forEach { runCatching { it.close() } }
            return null
        }
        if (recorder.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            recorder.release()
            pipe.forEach { runCatching { it.close() } }
            return null
        }
        record = recorder
        writeSide = pipe[1]
        running = true
        thread = Thread({ pump(recorder, pipe[1]) }, "homi-app-microphone").also { it.start() }
        return pipe[0]
    }

    private fun pump(recorder: AudioRecord, write: ParcelFileDescriptor) {
        val buffer = ByteArray(frameBytes)
        val route = AppMicrophoneRouteGate(preferredInput?.id)
        val startedAt = SystemClock.elapsedRealtime()
        var reportedRoute = false
        try {
            ParcelFileDescriptor.AutoCloseOutputStream(write).use { output ->
                while (running) {
                    val count = try {
                        recorder.read(buffer, 0, buffer.size)
                    } catch (_: RuntimeException) {
                        if (running) onFailure()
                        break
                    }
                    if (count < 0) {
                        if (running) onFailure()
                        break
                    }
                    if (count == 0) continue
                    if (!running) break
                    val device = try {
                        recorder.routedDevice
                    } catch (_: RuntimeException) {
                        if (running) onFailure()
                        break
                    }
                    when (route.check(device?.id, SystemClock.elapsedRealtime() - startedAt)) {
                        AppMicrophoneRouteGate.Decision.WAIT -> continue
                        AppMicrophoneRouteGate.Decision.FAIL -> {
                            if (running) onFailure()
                            break
                        }
                        AppMicrophoneRouteGate.Decision.ACCEPT -> Unit
                    }
                    if (!reportedRoute) {
                        reportedRoute = true
                        onRouteReady(device?.id, device?.type)
                    }
                    output.write(buffer, 0, count)
                    onFrame(buffer, count)
                }
                output.flush()
            }
        } catch (_: Exception) {
            // The recognizer can close its end before delivering a successful
            // final result. A closed pipe alone is not a microphone failure.
        }
    }

    /** Stops capture and closes the writer so the recognizer sees end of stream. */
    fun stop() {
        running = false
        val recorder = record
        record = null
        try {
            recorder?.stop()
        } catch (_: IllegalStateException) {
        }
        recorder?.release()
        val pump = thread
        thread = null
        pump?.join(STOP_JOIN_MS)
        if (pump?.isAlive == true) {
            // The pump owns the stream and closes it on exit; force the end of
            // stream only when it did not come back in time.
            runCatching { writeSide?.close() }
        }
        writeSide = null
    }

    private companion object {
        /** 50 ms of 16 kHz mono PCM16. */
        const val frameBytes = 1600
        const val STOP_JOIN_MS = 500L
    }
}

/** Discard startup frames until routing settles; never accept a different mic. */
internal class AppMicrophoneRouteGate(private val expectedDeviceId: Int?) {
    enum class Decision { WAIT, ACCEPT, FAIL }
    private var confirmed = false

    fun check(actualDeviceId: Int?, elapsedMs: Long): Decision {
        if (expectedDeviceId == null || actualDeviceId == expectedDeviceId) {
            confirmed = true
            return Decision.ACCEPT
        }
        return if (confirmed || elapsedMs >= 1500L) Decision.FAIL else Decision.WAIT
    }
}

/** Level helpers for little-endian PCM16 frames. */
internal object PcmLevel {
    /** RMS of the frame in dBFS, floored at -60 for silence. */
    fun dbfs(buffer: ByteArray, count: Int): Double {
        var sum = 0.0
        var samples = 0
        var index = 0
        while (index + 1 < count) {
            val sample =
                ((buffer[index + 1].toInt() shl 8) or (buffer[index].toInt() and 0xff))
                    .toShort()
                    .toDouble() / 32768.0
            sum += sample * sample
            samples += 1
            index += 2
        }
        if (samples == 0) return SILENCE_DBFS
        val rms = sqrt(sum / samples)
        if (rms <= 0.0) return SILENCE_DBFS
        return maxOf(SILENCE_DBFS, 20.0 * log10(rms))
    }

    /**
     * Maps dBFS onto the -2..10 range that `RecognitionListener.onRmsChanged`
     * reports, which the Dart side already converts into its amplitude stream.
     */
    fun recognizerRmsDb(dbfs: Double): Double =
        -2.0 + 12.0 * ((dbfs - SILENCE_DBFS) / -SILENCE_DBFS).coerceIn(0.0, 1.0)

    private const val SILENCE_DBFS = -60.0
}
