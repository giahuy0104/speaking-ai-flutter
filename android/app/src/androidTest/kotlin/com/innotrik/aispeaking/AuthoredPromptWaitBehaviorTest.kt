package com.innotrik.aispeaking

import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regression coverage for the authored-clip gain wait/coalesce logic in
 * VoicePromptBridge (the bounded wait before an unmeasured authored clip's
 * first play, in-flight measurement coalescing across duplicate requests,
 * and cancel-safety when a new clip replaces one still waiting). Exercises
 * the real method channel entry point, not a reimplementation. Content is
 * synthetic WAV generated in-test (decodes via the fast analyzeWave() path)
 * so this suite needs no pre-staged device files.
 */
class AuthoredPromptWaitBehaviorTest {
    private val noOpMessenger = object : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }

    private fun field(target: Any, name: String) =
        VoicePromptBridge::class.java.getDeclaredField(name).apply { isAccessible = true }.get(target)

    @Suppress("UNCHECKED_CAST")
    private fun levelWorkerOf(bridge: VoicePromptBridge) = field(bridge, "levelWorker") as ExecutorService

    @Suppress("UNCHECKED_CAST")
    private fun waitersOf(bridge: VoicePromptBridge) =
        field(bridge, "authoredLevelWaiters") as MutableMap<String, MutableList<*>>

    @Suppress("UNCHECKED_CAST")
    private fun cacheOf(bridge: VoicePromptBridge) = field(bridge, "authoredPromptLevels") as MutableMap<String, *>

    private fun clearLogcat() {
        Runtime.getRuntime().exec(arrayOf("logcat", "-c")).waitFor()
    }

    private fun dumpLogcat(): String {
        val process = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-s", "HomiDiag:I"))
        val output = process.inputStream.bufferedReader().readText()
        process.waitFor()
        return output
    }

    private fun countEventForId(log: String, event: String, id: String): Int =
        log.lines().count { it.contains("\"event\":\"$event\"") && it.contains("\"id\":\"$id\"") }

    private fun resultCountingDown(latch: CountDownLatch) = object : MethodChannel.Result {
        override fun success(result: Any?) = latch.countDown()
        override fun error(code: String, message: String?, details: Any?) = latch.countDown()
        override fun notImplemented() = latch.countDown()
    }

    private fun play(bridge: VoicePromptBridge, bytes: ByteArray): CountDownLatch {
        val latch = CountDownLatch(1)
        val call = MethodCall("playAuthoredAudioAndWait", mapOf("bytes" to bytes, "gainDb" to 8.0))
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            bridge.onMethodCall(call, resultCountingDown(latch))
        }
        return latch
    }

    private fun newBridge(): VoicePromptBridge {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val bridge = VoicePromptBridge(context, noOpMessenger)
        Thread.sleep(500) // let TextToSpeech.OnInitListener finish on the main looper.
        return bridge
    }

    private fun dispose(bridge: VoicePromptBridge) {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { bridge.dispose() }
    }

    /** A short, valid, playable mono PCM16 WAV tone -- decodes via the fast analyzeWave() path. */
    private fun toneWaveBytes(
        frequencyHz: Int,
        sampleRate: Int = 16000,
        durationMs: Int = 120,
        byteRateOverride: Int? = null,
    ): ByteArray {
        val samples = sampleRate * durationMs / 1000
        val dataSize = samples * 2
        val buffer = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(36 + dataSize)
        buffer.put("WAVEfmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1) // PCM
        buffer.putShort(1) // mono
        buffer.putInt(sampleRate)
        buffer.putInt(byteRateOverride ?: (sampleRate * 2)) // byteRate = sampleRate * blockAlign
        buffer.putShort(2) // blockAlign
        buffer.putShort(16) // bits
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataSize)
        repeat(samples) { i ->
            val value = (sin(2 * Math.PI * frequencyHz * i / sampleRate) * 12000).toInt().toShort()
            buffer.putShort(value)
        }
        return buffer.array()
    }

    @Test
    fun timeoutFallbackAppliesOnceAndLateResultDoesNotChangePlayingGain() {
        val bridge = newBridge()
        val bytes = toneWaveBytes(440)
        val levelWorker = levelWorkerOf(bridge)
        val gate = CountDownLatch(1)
        // Occupy the single decode thread so the real analyze() task queued
        // behind it cannot finish before the 300ms external wait expires --
        // a controlled, deterministic delay instead of hunting a slow asset.
        levelWorker.execute { gate.await(5, TimeUnit.SECONDS) }
        clearLogcat()

        val latch = play(bridge, bytes)
        Thread.sleep(600) // past AUTHORED_LEVEL_WAIT_MS=300ms while decode stays gated
        gate.countDown() // let the real decode run now; it resolves "late"
        assertTrue("AndWait result never completed", latch.await(10, TimeUnit.SECONDS))
        Thread.sleep(300) // let the late mainHandler.post from the decode settle

        val log = dumpLogcat()
        val id = "authored-prompt-1"
        assertEquals(
            "fallback gain must be applied exactly once",
            1,
            countEventForId(log, "prompt.level.applied", id),
        )
        assertTrue(
            "fallback event must report measured:false and gainDb/fallbackDb:0 (org.json serializes 0.0 as \"0\")",
            log.lines().single { it.contains("\"id\":\"$id\"") && it.contains("prompt.level.applied") }
                .let { it.contains("\"measured\":false") && it.contains("\"gainDb\":0") && it.contains("\"fallbackDb\":0") },
        )
        assertEquals(
            "playback must start exactly once, at the fallback gain",
            1,
            countEventForId(log, "prompt.native.started", id),
        )
        assertEquals(
            "the late decode result must still populate the cache for next time",
            1,
            cacheOf(bridge).size,
        )
        dispose(bridge)
    }

    @Test
    fun stopDuringWaitPreventsStaleClipAndDoesNotAffectNewClip() {
        val bridge = newBridge()
        val bytesA = toneWaveBytes(440)
        val bytesB = toneWaveBytes(660, durationMs = 250)
        val levelWorker = levelWorkerOf(bridge)
        val gate = CountDownLatch(1)
        // A's decode is gated so it cannot resolve before we interrupt it.
        levelWorker.execute { gate.await(5, TimeUnit.SECONDS) }
        clearLogcat()

        val latchA = play(bridge, bytesA) // utterance "authored-prompt-1", enters the wait
        Thread.sleep(100) // confirm it reached onPrepared/the wait state, well under 300ms
        val latchB = play(bridge, bytesB) // interrupts A: releasePromptPlayback() + new play, utterance "authored-prompt-2"
        gate.countDown() // allow A's (now stale) decode, then B's, to run

        assertTrue("A's AndWait never resolved", latchA.await(10, TimeUnit.SECONDS))
        assertTrue("B's AndWait never resolved", latchB.await(10, TimeUnit.SECONDS))
        Thread.sleep(300)

        val log = dumpLogcat()
        assertEquals(
            "the stopped clip (A) must never start playback",
            0,
            countEventForId(log, "prompt.native.started", "authored-prompt-1"),
        )
        assertEquals(
            "the stopped clip (A) must never have a gain decision logged",
            0,
            countEventForId(log, "prompt.level.applied", "authored-prompt-1"),
        )
        assertEquals(
            "the new clip (B) must start exactly once",
            1,
            countEventForId(log, "prompt.native.started", "authored-prompt-2"),
        )
        assertEquals(
            "the new clip (B) must get its own gain decision exactly once, unaffected by A",
            1,
            countEventForId(log, "prompt.level.applied", "authored-prompt-2"),
        )
        dispose(bridge)
    }

    @Test
    fun duplicateRequestsForSameContentCoalesceAndWaitersAreCleanedUp() {
        val bridge = newBridge()
        val bytes = toneWaveBytes(440)
        val levelWorker = levelWorkerOf(bridge)
        val gate = CountDownLatch(1)
        levelWorker.execute { gate.await(5, TimeUnit.SECONDS) }
        clearLogcat()

        val latch1 = play(bridge, bytes) // registers the one in-flight measurement
        Thread.sleep(100)
        val latch2 = play(bridge, bytes) // same content again before the first resolves
        Thread.sleep(100)

        val waitersMidFlight = waitersOf(bridge)
        assertEquals("exactly one content key should be in flight", 1, waitersMidFlight.size)
        assertEquals(
            "both requests must join the one in-flight decode, not start a second",
            2,
            waitersMidFlight.values.first().size,
        )

        gate.countDown()
        assertTrue("first AndWait never resolved", latch1.await(10, TimeUnit.SECONDS))
        assertTrue("second AndWait never resolved", latch2.await(10, TimeUnit.SECONDS))
        Thread.sleep(300)

        assertTrue(
            "waiters must be cleared on completion, not held indefinitely",
            waitersOf(bridge).isEmpty(),
        )
        assertEquals(
            "exactly one decode outcome should be cached for this content",
            1,
            cacheOf(bridge).size,
        )
        dispose(bridge)
    }

    @Test
    fun measurementErrorBeforeOnPreparedAppliesFallbackOnceAndAllowsRetry() {
        val bridge = newBridge()
        // A deliberately wrong byteRate: Android's own WAV extractor derives
        // playback framing from sampleRate/channels/bits and plays this fine
        // (confirmed below by the AndWait completing), but
        // AndroidPlaybackLoudness.analyzeWave() strictly requires
        // byteRate == sampleRate * blockAlign and rejects it immediately --
        // a fast, deterministic measurement error using the exact bytes
        // being played, not a separately seeded one.
        val bytes = toneWaveBytes(440, byteRateOverride = 1)
        clearLogcat()

        val latch1 = play(bridge, bytes)
        assertTrue("AndWait never resolved (clip must still play despite the bad byteRate)", latch1.await(10, TimeUnit.SECONDS))
        Thread.sleep(200)

        val log = dumpLogcat()
        val id1 = "authored-prompt-1"
        assertEquals(
            "fallback must be applied exactly once, not left waiting on a dead task",
            1,
            countEventForId(log, "prompt.level.applied", id1),
        )
        assertTrue(
            "fallback event must report measured:false and gainDb/fallbackDb:0 (org.json serializes 0.0 as \"0\")",
            log.lines().single { it.contains("\"id\":\"$id1\"") && it.contains("prompt.level.applied") }
                .let { it.contains("\"measured\":false") && it.contains("\"gainDb\":0") && it.contains("\"fallbackDb\":0") },
        )
        assertEquals(
            "playback must start exactly once, at the fallback gain",
            1,
            countEventForId(log, "prompt.native.started", id1),
        )
        assertTrue("a failed measurement must not be cached as a result", cacheOf(bridge).isEmpty())
        assertTrue(
            "a resolved (failed) measurement must not linger as an in-flight waiter entry",
            waitersOf(bridge).isEmpty(),
        )

        // A later, separate play of the SAME content must still attempt its
        // own measurement -- not be permanently blocked by a stale "still
        // running" belief left over from the first attempt's error.
        clearLogcat()
        val latch2 = play(bridge, bytes)
        assertTrue("second AndWait never resolved", latch2.await(10, TimeUnit.SECONDS))
        Thread.sleep(200)
        assertEquals(
            "a later play must attempt its own measurement again, not skip it forever",
            1,
            countEventForId(dumpLogcat(), "prompt.level.applied", "authored-prompt-2"),
        )
        dispose(bridge)
    }
}
