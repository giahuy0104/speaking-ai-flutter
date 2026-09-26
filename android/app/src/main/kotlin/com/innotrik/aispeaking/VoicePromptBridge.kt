package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.AudioDeviceInfo
import android.os.Build
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
import java.util.concurrent.Executors
import kotlin.math.pow
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
        val forcePhoneSpeaker: Boolean = false,
        val forceMediaPlayback: Boolean = false,
    )

    private val appContext = context.applicationContext
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val methodChannel = MethodChannel(messenger, "ailingo_voice_prompt")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var textToSpeech: TextToSpeech? = null
    private var initialized = false
    private var pendingPrompt: PendingPrompt? = null
    private var awaitedUtteranceId: String? = null
    private var awaitedResult: MethodChannel.Result? = null
    private var readyCuePlayer: MediaPlayer? = null
    private var readyCueCompletion: Runnable? = null
    private val readyCueResults = mutableListOf<MethodChannel.Result>()
    var isH20RouteOwned: () -> Boolean = { false }
    private val levelWorker = Executors.newSingleThreadExecutor()
    private var synthesizedPromptId: String? = null
    private var synthesizedPromptFile: File? = null
    private var synthesizedPromptGainMillibels = 0
    private var synthesizedPromptForcePhoneSpeaker = false
    private var synthesizedPromptForceMediaPlayback = false
    private var synthesizedPromptLevelKey: String? = null
    // Matched levels of authored clips by content; main thread only.
    private val authoredPromptLevels =
        object : LinkedHashMap<String, PlaybackLoudnessResult>(16, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, PlaybackLoudnessResult>?,
            ) = size > 64
        }
    private var promptPlaybackId: String? = null
    private var promptPlaybackFile: File? = null
    private var promptPlayer: MediaPlayer? = null
    private var promptLoudnessEnhancer: LoudnessEnhancer? = null
    private var utteranceSequence = 0L
    private var diagnosticCueSequence = 0L

    init {
        AudioDiagnostics.event("diagnostics.native.ready", mapOf("build" to "audio-fix-v2"))
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
                forcePhoneSpeaker = it.forcePhoneSpeaker,
                forceMediaPlayback = it.forceMediaPlayback,
            )
        }
        pendingPrompt = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "analyzePlaybackLevel" -> analyzePlaybackLevel(call, result)
            "playAuthoredAudioAndWait" -> playAuthoredAudio(call, result)
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                val forcePhoneSpeaker = call.argument<Boolean>("forcePhoneSpeaker") == true
                val forceMediaPlayback = call.argument<Boolean>("forceMediaPlayback") == true
                if (text.isNotEmpty()) {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        gainDb,
                        forcePhoneSpeaker = forcePhoneSpeaker,
                        forceMediaPlayback = forceMediaPlayback,
                    )
                }
                result.success(null)
            }
            "speakAndWait" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                val forcePhoneSpeaker = call.argument<Boolean>("forcePhoneSpeaker") == true
                val forceMediaPlayback = call.argument<Boolean>("forceMediaPlayback") == true
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
                        forcePhoneSpeaker = forcePhoneSpeaker,
                        forceMediaPlayback = forceMediaPlayback,
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
        forcePhoneSpeaker: Boolean = false,
        forceMediaPlayback: Boolean = false,
    ) {
        if (!initialized) {
            completePendingPrompt()
            pendingPrompt = PendingPrompt(
                text,
                localeTag,
                gainDb,
                completion,
                speechRate,
                pitch,
                forcePhoneSpeaker,
                forceMediaPlayback,
            )
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
        engine.setAudioAttributes(
            voicePromptAudioAttributes(
                forcePhoneSpeaker = forcePhoneSpeaker,
                forceMediaPlayback = forceMediaPlayback,
            ),
        )
        val languageResult = engine.setLanguage(requestedLocale)
        if (
            languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            engine.setLanguage(Locale("vi", "VN"))
        }
        utteranceSequence += 1
        val utteranceId = "voice-prompt-$utteranceSequence"
        AudioDiagnostics.output("tts.synthesis.request", audioManager, mapOf("id" to utteranceId, "gainDb" to gainDb, "characters" to text.length))
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
        synthesizedPromptForcePhoneSpeaker = forcePhoneSpeaker
        synthesizedPromptForceMediaPlayback = forceMediaPlayback
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

    private fun analyzePlaybackLevel(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val asset = call.argument<String>("asset")
        levelWorker.execute {
            val measured = runCatching {
                val file = if (asset != null && asset.startsWith("assets/") && !asset.contains("..")) {
                    val stamp = appContext.packageManager.getPackageInfo(appContext.packageName, 0).lastUpdateTime
                    val key = java.security.MessageDigest.getInstance("SHA-256")
                        .digest(asset.toByteArray()).joinToString("") { "%02x".format(it) }
                    File(appContext.cacheDir, "level-$stamp-$key.audio").also { target ->
                        if (!target.exists()) {
                            appContext.assets.open("flutter_assets/$asset").use { input ->
                                target.outputStream().use { output -> input.copyTo(output) }
                            }
                        }
                    }
                } else if (path != null) File(path) else null
                file?.let(AndroidPlaybackLoudness::analyze)?.toMap()
            }.getOrNull()
            mainHandler.post { result.success(measured) }
        }
    }

    private fun isScoRouteActive(): Boolean {
        @Suppress("DEPRECATION")
        val bluetoothScoOn = audioManager.isBluetoothScoOn
        return (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
            audioManager.communicationDevice?.type ==
            android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO) || bluetoothScoOn
    }

    private fun voicePromptAudioAttributes(
        forcePhoneSpeaker: Boolean = false,
        forceMediaPlayback: Boolean = false,
    ): AudioAttributes {
        val activeScoRoute = isScoRouteActive()
        val usage =
            if (!forcePhoneSpeaker && (activeScoRoute || !forceMediaPlayback)) {
                AudioAttributes.USAGE_VOICE_COMMUNICATION
            } else {
                AudioAttributes.USAGE_MEDIA
            }
        return AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .setUsage(usage)
            .build()
    }

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
        synthesizedPromptForcePhoneSpeaker =
            call.argument<Boolean>("forcePhoneSpeaker") == true
        synthesizedPromptForceMediaPlayback =
            call.argument<Boolean>("forceMediaPlayback") == true
        synthesizedPromptLevelKey = "${bytes.size}:${bytes.contentHashCode()}"
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

    private fun playSynthesizedPrompt(utteranceId: String, scoWaitedMs: Long = 0L) {
        if (scoWaitedMs == 0L) {
            AudioDiagnostics.event("prompt.native.prepare", mapOf("id" to utteranceId))
        }
        if (utteranceId != synthesizedPromptId) {
            return
        }
        if (
            PromptScoWait.shouldWait(
                synthesizedPromptForcePhoneSpeaker,
                isH20RouteOwned(),
                isScoRouteActive(),
                scoWaitedMs,
            )
        ) {
            mainHandler.postDelayed(
                { playSynthesizedPrompt(utteranceId, scoWaitedMs + PromptScoWait.POLL_MS) },
                PromptScoWait.POLL_MS,
            )
            return
        }
        val audioFile = synthesizedPromptFile
        val gainMillibels = synthesizedPromptGainMillibels
        val levelKey = synthesizedPromptLevelKey
        synthesizedPromptId = null
        synthesizedPromptFile = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptLevelKey = null
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
                voicePromptAudioAttributes(
                    forcePhoneSpeaker = synthesizedPromptForcePhoneSpeaker,
                    forceMediaPlayback = synthesizedPromptForceMediaPlayback,
                ),
            )
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !synthesizedPromptForcePhoneSpeaker
            ) {
                audioManager.communicationDevice
                    ?.takeIf { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                    ?.let { player.setPreferredDevice(it) }
            }
            player.setDataSource(audioFile.absolutePath)
            player.setVolume(1.0f, 1.0f)
            player.setOnPreparedListener { preparedPlayer ->
                if (promptPlayer !== preparedPlayer || promptPlaybackId != utteranceId) {
                    return@setOnPreparedListener
                }
                var levelApplied = false
                fun startWithLevel(measured: PlaybackLoudnessResult?) {
                    if (levelApplied || promptPlayer !== preparedPlayer || promptPlaybackId != utteranceId) return
                    levelApplied = true
                    try {
                        val gainDb = measured?.gainDb ?: (gainMillibels / 100.0).coerceIn(0.0, 8.0)
                        val volume = 10.0.pow(gainDb.coerceAtMost(0.0) / 20.0).toFloat()
                        preparedPlayer.setVolume(volume, volume)
                        promptLoudnessEnhancer = try {
                            LoudnessEnhancer(preparedPlayer.audioSessionId).apply {
                                setTargetGain((gainDb.coerceAtLeast(0.0) * 100).roundToInt())
                                enabled = true
                            }
                        } catch (_: RuntimeException) { null }
                        AudioDiagnostics.event("prompt.level.applied", mapOf("id" to utteranceId, "gainDb" to gainDb, "measured" to (measured != null)))
                        preparedPlayer.start()
                        AudioDiagnostics.output("prompt.native.started", audioManager, mapOf("id" to utteranceId, "gainDb" to gainDb, "durationMs" to preparedPlayer.duration, "sessionId" to preparedPlayer.audioSessionId))
                    } catch (error: RuntimeException) {
                        finishPromptPlayback(utteranceId, error.message ?: "Unable to start prompt.")
                    }
                }
                if (levelKey != null) {
                    // Authored clips are fixed assets whose MP3 decode rarely fits
                    // the wait below. Start now; measure in the background so the
                    // clip's next playback starts with its matched level.
                    val cached = authoredPromptLevels[levelKey]
                    startWithLevel(cached)
                    if (cached == null) {
                        levelWorker.execute {
                            val measured = runCatching {
                                AndroidPlaybackLoudness.analyze(
                                    audioFile,
                                    AndroidPlaybackLoudness.BACKGROUND_DECODE_NS,
                                )
                            }.getOrNull() ?: return@execute
                            mainHandler.post { authoredPromptLevels[levelKey] = measured }
                        }
                    }
                    return@setOnPreparedListener
                }
                // A slow OEM codec must not reintroduce a seconds-long wait.
                val levelTimeout = Runnable { startWithLevel(null) }
                mainHandler.postDelayed(levelTimeout, 450L)
                levelWorker.execute {
                    val measured = runCatching { AndroidPlaybackLoudness.analyze(audioFile) }.getOrNull()
                    mainHandler.post {
                        mainHandler.removeCallbacks(levelTimeout)
                        startWithLevel(measured)
                    }
                }
            }
            player.setOnCompletionListener {
                AudioDiagnostics.event("prompt.native.audio_completed", mapOf("id" to utteranceId))
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
        synthesizedPromptLevelKey = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptForcePhoneSpeaker = false
        synthesizedPromptForceMediaPlayback = false
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
        // Concurrent requests share this one sound and its completion.
        if (readyCuePlayer != null) {
            readyCueResults.add(result)
            AudioDiagnostics.event("cue.native.coalesced", mapOf("cueId" to diagnosticCueSequence))
            return
        }
        diagnosticCueSequence += 1
        val cueId = diagnosticCueSequence
        val player = try { MediaPlayer() } catch (error: RuntimeException) {
            result.error("READY_CUE_UNAVAILABLE", error.message, null)
            return
        }
        readyCuePlayer = player
        readyCueResults.add(result)
        prepareSpeechReadyCue(player, cueId)
    }

    private fun prepareSpeechReadyCue(player: MediaPlayer, cueId: Long, scoWaitedMs: Long = 0L) {
        if (readyCuePlayer !== player) return
        if (PromptScoWait.shouldWait(false, isH20RouteOwned(), isScoRouteActive(), scoWaitedMs)) {
            mainHandler.postDelayed(
                { prepareSpeechReadyCue(player, cueId, scoWaitedMs + PromptScoWait.POLL_MS) },
                PromptScoWait.POLL_MS,
            )
            return
        }
        try {
            val file = File(appContext.cacheDir, "speech-ready-v2.wav")
            val waveform = ReadyCueWaveform.wavBytes()
            if (!file.exists() || file.length() != waveform.size.toLong()) {
                file.writeBytes(waveform)
            }
            player.setAudioAttributes(voicePromptAudioAttributes(forceMediaPlayback = true))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.communicationDevice?.takeIf { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
                    ?.let { player.setPreferredDevice(it) }
            }
            player.setDataSource(file.absolutePath)
            player.setVolume(1f, 1f) // PCM already generated at the common target.
            player.setOnPreparedListener {
                if (readyCuePlayer !== player) return@setOnPreparedListener
                AudioDiagnostics.output("cue.native.start", audioManager, mapOf("cueId" to cueId, "sessionId" to player.audioSessionId))
                try {
                    player.start() // Exactly one start; no hidden retry on a second renderer.
                } catch (_: RuntimeException) {
                    completeReadyCue("READY_CUE_UNAVAILABLE")
                    return@setOnPreparedListener
                }
                // Some Android 12 Bluetooth SCO implementations play this
                // 120 ms WAV but never deliver MediaPlayer.onCompletion. Once
                // start succeeds, use the known cue length plus a generous
                // route/drain/tail allowance as a successful completion gate.
                // The hard prepare timeout below still fails closed when the
                // player never starts at all.
                readyCueCompletion?.let(mainHandler::removeCallbacks)
                val drainGuard = Runnable {
                    if (readyCuePlayer === player) {
                        AudioDiagnostics.event(
                            "cue.native.drain_guard",
                            mapOf(
                                "cueId" to cueId,
                                "isPlaying" to runCatching { player.isPlaying }.getOrNull(),
                                "deviceType" to runCatching { player.routedDevice?.type }.getOrNull(),
                                "deviceId" to runCatching { player.routedDevice?.id }.getOrNull(),
                            ),
                        )
                        completeReadyCue()
                    }
                }
                readyCueCompletion = drainGuard
                mainHandler.postDelayed(drainGuard, 700L)
                mainHandler.postDelayed({
                    if (readyCuePlayer === player) {
                        runCatching {
                            AudioDiagnostics.event("cue.native.routed", mapOf("cueId" to cueId, "deviceType" to player.routedDevice?.type, "deviceId" to player.routedDevice?.id))
                        }
                    }
                }, 40L)
            }
            player.setOnCompletionListener {
                if (readyCuePlayer !== player) return@setOnCompletionListener
                readyCueCompletion?.let(mainHandler::removeCallbacks)
                // Keep the existing acoustic-tail guard before lesson recording.
                val tail = Runnable { if (readyCuePlayer === player) completeReadyCue() }
                readyCueCompletion = tail
                mainHandler.postDelayed(tail, 180L)
            }
            player.setOnErrorListener { _, what, extra ->
                if (readyCuePlayer === player) {
                    AudioDiagnostics.event("cue.native.error", mapOf("cueId" to cueId, "what" to what, "extra" to extra))
                    completeReadyCue("READY_CUE_UNAVAILABLE")
                }
                true
            }
            val timeout = Runnable { if (readyCuePlayer === player) completeReadyCue("READY_CUE_TIMEOUT") }
            readyCueCompletion = timeout
            mainHandler.postDelayed(timeout, 3000L)
            player.prepareAsync()
        } catch (_: Exception) {
            completeReadyCue("READY_CUE_UNAVAILABLE")
        }
    }

    private fun completeReadyCue(errorCode: String? = null) {
        if (readyCuePlayer != null || readyCueResults.isNotEmpty()) {
            AudioDiagnostics.event("cue.native.complete", mapOf("cueId" to diagnosticCueSequence, "errorCode" to errorCode))
        }
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        val player = readyCuePlayer
        readyCuePlayer = null
        runCatching { player?.release() }
        val completions = readyCueResults.toList()
        readyCueResults.clear()
        for (completion in completions) {
            if (errorCode == null) completion.success(null)
            else completion.error(errorCode, "Không thể phát tín hiệu sẵn sàng trên đường âm thanh đã chọn.", null)
        }
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
        completeReadyCue("HFP_ROUTE_LOST")
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
        levelWorker.shutdown()
    }
}
