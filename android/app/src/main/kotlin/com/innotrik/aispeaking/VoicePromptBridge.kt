package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.media.audiofx.LoudnessEnhancer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

class VoicePromptBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    TextToSpeech.OnInitListener {
    private data class PendingPrompt(
        val text: String,
        val locale: String,
        val gainDb: Double,
        val completion: MethodChannel.Result?,
        val speechRate: Float = 0.92f,
        val pitch: Float = 1.0f,
    )

    private val appContext = context.applicationContext
    private val methodChannel = MethodChannel(messenger, "ailingo_voice_prompt")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var textToSpeech: TextToSpeech? = null
    private var initialized = false
    private var pendingPrompt: PendingPrompt? = null
    private var awaitedUtteranceId: String? = null
    private var awaitedResult: MethodChannel.Result? = null
    private var readyCueGenerator: ToneGenerator? = null
    private var readyCueCompletion: Runnable? = null
    private var readyCueResult: MethodChannel.Result? = null
    private var synthesizedPromptId: String? = null
    private var synthesizedPromptFile: File? = null
    private var synthesizedPromptGainMillibels = 0
    private var promptPlaybackId: String? = null
    private var promptPlaybackFile: File? = null
    private var promptPlayer: MediaPlayer? = null
    private var promptLoudnessEnhancer: LoudnessEnhancer? = null
    private var utteranceSequence = 0L

    init {
        methodChannel.setMethodCallHandler(this)
        textToSpeech = TextToSpeech(appContext, this)
    }

    override fun onInit(status: Int) {
        initialized = status == TextToSpeech.SUCCESS
        if (!initialized) {
            pendingPrompt?.completion?.error(
                "TTS_UNAVAILABLE",
                "Text to speech is unavailable.",
                null,
            )
            pendingPrompt = null
            return
        }
        textToSpeech?.apply {
            setSpeechRate(0.92f)
            // Keep the direct TextToSpeech fallback on the same communication
            // stream as synthesized-file playback. Otherwise an OEM TTS engine
            // that rejects file synthesis can jump from H20 to the phone.
            setAudioAttributes(voicePromptAudioAttributes())
            setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        handleTtsDone(utteranceId)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        handleTtsFailure(utteranceId, "TTS synthesis failed.")
                    }

                    override fun onStop(
                        utteranceId: String?,
                        interrupted: Boolean,
                    ) {
                        handleTtsStopped(utteranceId)
                    }
                },
            )
        }
        pendingPrompt?.let {
            speak(
                it.text,
                it.locale,
                it.gainDb,
                completion = it.completion,
                speechRate = it.speechRate,
                pitch = it.pitch,
            )
        }
        pendingPrompt = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "playAuthoredAudioAndWait" -> playAuthoredAudio(call, result)
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                if (text.isNotEmpty()) {
                    speak(text, locale.ifEmpty { "vi-VN" }, gainDb)
                }
                result.success(null)
            }
            "speakAndWait" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                if (text.isEmpty()) {
                    result.success(null)
                } else {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        gainDb,
                        completion = result,
                        speechRate = (call.argument<Number>("speechRate")?.toFloat() ?: 0.92f)
                            .coerceIn(0.5f, 1.5f),
                        pitch = (call.argument<Number>("pitch")?.toFloat() ?: 1.0f)
                            .coerceIn(0.8f, 1.2f),
                    )
                }
            }
            "playSpeechReadyCue" -> playSpeechReadyCue(result)
            "stop" -> {
                completePendingPrompt()
                completeActiveAwaited()
                completeReadyCue()
                textToSpeech?.stop()
                clearSynthesizedPrompt()
                releasePromptPlayback()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun speak(
        text: String,
        localeTag: String,
        gainDb: Double,
        completion: MethodChannel.Result? = null,
        speechRate: Float = 0.92f,
        pitch: Float = 1.0f,
    ) {
        if (!initialized) {
            completePendingPrompt()
            pendingPrompt = PendingPrompt(text, localeTag, gainDb, completion, speechRate, pitch)
            return
        }
        val engine = textToSpeech
        if (engine == null) {
            completion?.error("TTS_UNAVAILABLE", "Text to speech is unavailable.", null)
            return
        }
        completeReadyCue()
        completeActiveAwaited()
        engine.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        val requestedLocale = Locale.forLanguageTag(localeTag)
        // Reset every utterance: translation style cannot leak into Core,
        // Challenge, vocabulary, or the MAIN assistant's feedback.
        engine.setSpeechRate(speechRate)
        engine.setPitch(pitch)
        val languageResult = engine.setLanguage(requestedLocale)
        if (
            languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            engine.setLanguage(Locale("vi", "VN"))
        }
        utteranceSequence += 1
        val utteranceId = "voice-prompt-$utteranceSequence"
        if (completion != null) {
            awaitedUtteranceId = utteranceId
            awaitedResult = completion
        }
        val speechParameters = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        val outputFile = File(appContext.cacheDir, "$utteranceId.wav")
        outputFile.delete()
        synthesizedPromptId = utteranceId
        synthesizedPromptFile = outputFile
        synthesizedPromptGainMillibels = (gainDb * 100.0).roundToInt()
        val status =
            engine.synthesizeToFile(text, speechParameters, outputFile, utteranceId)
        if (status == TextToSpeech.ERROR) {
            clearSynthesizedPrompt()
            // Keep prompts functional on TTS engines that do not implement
            // file synthesis, although this fallback cannot receive the boost.
            val fallbackStatus =
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, speechParameters, utteranceId)
            if (fallbackStatus == TextToSpeech.ERROR) {
                completeAwaited(utteranceId, "TTS playback failed.")
            }
        }
    }

    private fun requestedGainDb(call: MethodCall): Double =
        (call.argument<Number>("gainDb")?.toDouble() ?: 8.0).coerceIn(0.0, 12.0)

    private fun voicePromptAudioAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .build()

    private fun playAuthoredAudio(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty() || bytes.size > 2 * 1024 * 1024) {
            result.error("INVALID_PROMPT_AUDIO", "Invalid authored prompt bytes.", null)
            return
        }
        // Reuse the local communication-route player and completion/cancellation
        // lifecycle so authored MP3 and TTS preserve the same H20 ownership.
        completePendingPrompt()
        completeActiveAwaited()
        completeReadyCue()
        textToSpeech?.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        utteranceSequence += 1
        val utteranceId = "authored-prompt-$utteranceSequence"
        awaitedUtteranceId = utteranceId
        awaitedResult = result
        val file = File(appContext.cacheDir, "$utteranceId.mp3")
        synthesizedPromptId = utteranceId
        synthesizedPromptFile = file
        synthesizedPromptGainMillibels = (requestedGainDb(call) * 100.0).roundToInt()
        try {
            file.writeBytes(bytes)
            playSynthesizedPrompt(utteranceId)
        } catch (_: Exception) {
            clearSynthesizedPrompt()
            completeAwaited(utteranceId, "Unable to prepare authored prompt audio.")
        }
    }

    private fun handleTtsDone(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                playSynthesizedPrompt(utteranceId)
            } else {
                completeAwaited(utteranceId)
            }
        }
    }

    private fun handleTtsFailure(
        utteranceId: String?,
        error: String,
    ) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                clearSynthesizedPrompt()
            }
            completeAwaited(utteranceId, error)
        }
    }

    private fun handleTtsStopped(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                clearSynthesizedPrompt()
            }
            completeAwaited(utteranceId)
        }
    }

    private fun playSynthesizedPrompt(utteranceId: String) {
        if (utteranceId != synthesizedPromptId) {
            return
        }
        val audioFile = synthesizedPromptFile
        val gainMillibels = synthesizedPromptGainMillibels
        synthesizedPromptId = null
        synthesizedPromptFile = null
        synthesizedPromptGainMillibels = 0
        if (audioFile == null || !audioFile.exists() || audioFile.length() == 0L) {
            audioFile?.delete()
            completeAwaited(utteranceId, "TTS produced no playable audio.")
            return
        }

        releasePromptPlayback()
        val player = MediaPlayer()
        promptPlaybackId = utteranceId
        promptPlaybackFile = audioFile
        promptPlayer = player
        try {
            player.setAudioAttributes(
                voicePromptAudioAttributes(),
            )
            player.setDataSource(audioFile.absolutePath)
            player.setVolume(1.0f, 1.0f)
            player.setOnPreparedListener { preparedPlayer ->
                if (promptPlayer !== preparedPlayer || promptPlaybackId != utteranceId) {
                    return@setOnPreparedListener
                }
                promptLoudnessEnhancer = try {
                    LoudnessEnhancer(preparedPlayer.audioSessionId).apply {
                        setTargetGain(gainMillibels)
                        enabled = true
                    }
                } catch (_: RuntimeException) {
                    null
                }
                preparedPlayer.start()
            }
            player.setOnCompletionListener {
                mainHandler.post { finishPromptPlayback(utteranceId) }
            }
            player.setOnErrorListener { _, _, _ ->
                mainHandler.post {
                    finishPromptPlayback(utteranceId, "TTS playback failed.")
                }
                true
            }
            player.prepareAsync()
        } catch (error: Exception) {
            finishPromptPlayback(
                utteranceId,
                error.message ?: "TTS playback failed.",
            )
        }
    }

    private fun finishPromptPlayback(
        utteranceId: String,
        error: String? = null,
    ) {
        if (utteranceId != promptPlaybackId) {
            return
        }
        releasePromptPlayback()
        completeAwaited(utteranceId, error)
    }

    private fun clearSynthesizedPrompt() {
        synthesizedPromptId = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptFile?.delete()
        synthesizedPromptFile = null
    }

    private fun releasePromptPlayback() {
        promptPlaybackId = null
        promptLoudnessEnhancer?.release()
        promptLoudnessEnhancer = null
        promptPlayer?.release()
        promptPlayer = null
        promptPlaybackFile?.delete()
        promptPlaybackFile = null
    }

    private fun completeAwaited(
        utteranceId: String?,
        error: String? = null,
    ) {
        mainHandler.post {
            if (utteranceId == null || utteranceId != awaitedUtteranceId) {
                return@post
            }
            val completion = awaitedResult
            awaitedUtteranceId = null
            awaitedResult = null
            if (error == null) {
                completion?.success(null)
            } else {
                completion?.error("TTS_PLAYBACK_FAILED", error, null)
            }
        }
    }

    private fun completePendingPrompt() {
        pendingPrompt?.completion?.success(null)
        pendingPrompt = null
    }

    private fun completeActiveAwaited() {
        val completion = awaitedResult
        awaitedUtteranceId = null
        awaitedResult = null
        completion?.success(null)
    }

    private fun playSpeechReadyCue(result: MethodChannel.Result) {
        completeReadyCue()
        val streamType = readyCueStreamType()
        var generator = try {
            ToneGenerator(streamType, 100).also {
                readyCueGenerator = it
            }
        } catch (error: RuntimeException) {
            result.error("READY_CUE_UNAVAILABLE", error.message, null)
            return
        }
        val toneStarted = try {
            generator.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
        } catch (_: RuntimeException) {
            false
        }
        if (!toneStarted) {
            // Recreate once instead of silently losing the cue on an OEM route
            // transition. The first instance is never reused across turns.
            runCatching { generator.release() }
            readyCueGenerator = null
            generator = try {
                ToneGenerator(streamType, 100).also {
                    readyCueGenerator = it
                }
            } catch (error: RuntimeException) {
                result.error("READY_CUE_UNAVAILABLE", error.message, null)
                return
            }
            val retryStarted = try {
                generator.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
            } catch (_: RuntimeException) {
                false
            }
            if (!retryStarted) {
                result.error("READY_CUE_UNAVAILABLE", "Unable to play the ready cue.", null)
                return
            }
        }
        readyCueResult = result
        // Complete after the tone tail; callers arm VAD only after this cue.
        val completion = Runnable { completeReadyCue() }
        readyCueCompletion = completion
        mainHandler.postDelayed(completion, 150L)
    }

    private fun readyCueStreamType(): Int {
        val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        val bluetoothScoOn = audioManager.isBluetoothScoOn
        // The cue is played after H20 recording starts. STREAM_MUSIC may then
        // remain on the phone while the active SCO route carries voice-call
        // audio, which made the "ting" intermittent on the headset.
        return if (
            audioManager.mode == AudioManager.MODE_IN_COMMUNICATION ||
                bluetoothScoOn
        ) {
            AudioManager.STREAM_VOICE_CALL
        } else {
            AudioManager.STREAM_MUSIC
        }
    }

    private fun completeReadyCue() {
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        readyCueGenerator?.let { generator ->
            runCatching { generator.stopTone() }
            runCatching { generator.release() }
        }
        readyCueGenerator = null
        val completion = readyCueResult
        readyCueResult = null
        completion?.success(null)
    }

    fun stopForRouteLoss() {
        // Runs on the bridge's main thread before SCO is released. Complete
        // with an error so callers cannot interpret a cut-off prompt as heard.
        pendingPrompt?.completion?.error("HFP_ROUTE_LOST", "Kết nối âm thanh H20 bị gián đoạn. Hãy thử lại.", null)
        pendingPrompt = null
        val completion = awaitedResult
        awaitedResult = null
        awaitedUtteranceId = null
        completion?.error("HFP_ROUTE_LOST", "Kết nối âm thanh H20 bị gián đoạn. Hãy thử lại.", null)
        completeReadyCue()
        textToSpeech?.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
    }

    fun stopForBackgroundSession() {
        mainHandler.post {
            completePendingPrompt()
            completeActiveAwaited()
            completeReadyCue()
            textToSpeech?.stop()
            clearSynthesizedPrompt()
            releasePromptPlayback()
        }
    }

    fun dispose() {
        completePendingPrompt()
        completeActiveAwaited()
        completeReadyCue()
        textToSpeech?.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        initialized = false
        methodChannel.setMethodCallHandler(null)
        textToSpeech?.shutdown()
        textToSpeech = null
    }
}
