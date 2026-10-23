package com.innotrik.aispeaking

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.ParcelFileDescriptor
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Captures the phone microphone inside the app and streams it to the Android
 * recognizer through an `EXTRA_AUDIO_SOURCE` pipe. Google's recognition
 * service plays its start/stop earcons on the notification stream only when it
 * opens the microphone itself; audio supplied by the app stays silent, so a
 * MAIN listening window no longer jumps far above the prompts around it.
 */
internal class AppMicrophoneAudioSource(
    private val sampleRate: Int,
    private val onFrame: (buffer: ByteArray, count: Int) -> Unit,
) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private var writeSide: ParcelFileDescriptor? = null

    @Volatile
    private var running = false

    /**
     * Opens the microphone and returns the descriptor the recognizer reads, or
     * null when the microphone could not be opened so the caller keeps the
     * recognizer's own capture.
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
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
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
        val pipe =
            try {
                ParcelFileDescriptor.createPipe()
            } catch (_: Exception) {
                recorder.release()
                return null
            }
        try {
            recorder.startRecording()
        } catch (_: IllegalStateException) {
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
        try {
            ParcelFileDescriptor.AutoCloseOutputStream(write).use { output ->
                while (running) {
                    val count = recorder.read(buffer, 0, buffer.size)
                    if (count < 0) break
                    if (count == 0) continue
                    output.write(buffer, 0, count)
                    onFrame(buffer, count)
                }
                output.flush()
            }
        } catch (_: Exception) {
            // Ending the turn tears the pipe down; nothing to report.
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
