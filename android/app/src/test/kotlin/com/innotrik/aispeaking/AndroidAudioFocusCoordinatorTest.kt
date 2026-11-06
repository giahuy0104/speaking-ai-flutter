package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AndroidAudioFocusCoordinatorTest {
    private lateinit var manager: AudioManager
    private lateinit var focus: AndroidAudioFocusCoordinator

    @Before
    fun setUp() {
        manager = RuntimeEnvironment.getApplication().getSystemService(Context.AUDIO_SERVICE) as AudioManager
        focus = AndroidAudioFocusCoordinator(manager)
    }

    @Test
    fun mainRetainsFocusAcrossPromptCaptureAndResponseGaps() {
        assertTrue(focus.acquire("main:1"))
        val request = shadowOf(manager).lastAudioFocusRequest
        assertEquals(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE, request.durationHint)
        assertEquals(AudioAttributes.CONTENT_TYPE_SPEECH, request.audioFocusRequest.audioAttributes.contentType)
        assertTrue(request.audioFocusRequest.willPauseWhenDucked())
        for (phase in listOf("prompt", "capture", "response")) {
            assertTrue(focus.acquire(phase))
            focus.release(phase)
            assertTrue(focus.isHeld)
            assertSame(request, shadowOf(manager).lastAudioFocusRequest)
            assertNull(shadowOf(manager).lastAbandonedAudioFocusRequest)
        }
        focus.release("main:1")
        assertFalse(focus.isHeld)
        assertSame(request.audioFocusRequest, shadowOf(manager).lastAbandonedAudioFocusRequest)
    }

    @Test
    fun lossInvalidatesEveryOwnerAndGainNeverResumesButNewActionCanAcquire() {
        for (loss in listOf(AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)) {
            var interruptions = 0
            focus.onInterrupted = { assertFalse(focus.isHeld); interruptions++ }
            focus.acquire("old-main")
            focus.acquire("old-capture")
            val oldListener = shadowOf(manager).lastAudioFocusRequest.listener
            oldListener.onAudioFocusChange(loss)
            assertEquals(1, interruptions)
            assertFalse(focus.isHeld)
            oldListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)
            assertFalse(focus.isHeld)
            assertTrue(focus.acquire("new-main"))
            oldListener.onAudioFocusChange(loss)
            focus.release("old-main")
            focus.release("old-capture")
            assertTrue(focus.isHeld)
            assertEquals(1, interruptions)
            focus.release("new-main")
        }
    }

    @Test
    fun deniedRequestAndBlankOwnerNeverAuthorizePlayback() {
        assertFalse(focus.acquire(" "))
        shadowOf(manager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        assertFalse(focus.acquire("denied"))
        assertFalse(focus.isHeld)
        shadowOf(manager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
        assertTrue(focus.acquire("retry"))
        focus.release("denied")
        assertTrue(focus.isHeld)
    }

    @Test
    fun microphoneRouteFailureInvalidatesMainAndCaptureBeforeNotifying() {
        focus.acquire("main")
        focus.acquire("capture")
        val oldListener = shadowOf(manager).lastAudioFocusRequest.listener
        var interruptions = 0
        focus.onInterrupted = {
            assertEquals("microphone_route_loss", it)
            assertFalse(focus.isHeld)
            interruptions++
        }
        focus.interrupt("microphone_route_loss")
        assertEquals(1, interruptions)
        assertTrue(focus.acquire("replacement"))
        oldListener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        focus.release("capture")
        focus.release("main")
        assertTrue(focus.isHeld)
        assertEquals(1, interruptions)
    }

    @Test
    fun lessonOwnerRequestsSustainedFocusAndNormalReleaseDoesNotInterrupt() {
        var interruptions = 0
        focus.onInterrupted = { interruptions++ }
        assertTrue(focus.acquire("lesson", transientExclusive = false))
        val request = shadowOf(manager).lastAudioFocusRequest
        assertEquals(AudioManager.AUDIOFOCUS_GAIN, request.durationHint)
        focus.release("lesson")
        request.listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        assertEquals(0, interruptions)
    }

    @Test
    fun staleMainCompletionCannotReleaseReplacementTurn() {
        val bridge = VoicePromptBridge(RuntimeEnvironment.getApplication(), NoopMessenger, focus)
        try {
            val first = call(bridge, "beginMainTurn").value as String
            val second = call(bridge, "beginMainTurn").value as String
            assertNotEquals(first, second)
            call(bridge, "endMainTurn", mapOf("turnId" to first))
            assertTrue(focus.isHeld)
            call(bridge, "endMainTurn", mapOf("turnId" to second))
            assertFalse(focus.isHeld)
        } finally { bridge.dispose() }
    }

    @Test
    fun persistentMediaRejectsMainAndReleasesItsFocus() {
        shadowOf(manager).setIsMusicActive(true)
        val bridge = VoicePromptBridge(RuntimeEnvironment.getApplication(), NoopMessenger, focus)
        try {
            val begin = call(bridge, "beginMainTurn")
            assertEquals(0, begin.completions)
            shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(650))
            assertEquals("EXTERNAL_MEDIA_ACTIVE", begin.errorCode)
            assertEquals(1, begin.completions)
            assertFalse(focus.isHeld)
        } finally { bridge.dispose() }
    }

    @Test
    fun stoppedPendingMediaCheckCannotReleaseANewerMain() {
        shadowOf(manager).setIsMusicActive(true)
        val bridge = VoicePromptBridge(RuntimeEnvironment.getApplication(), NoopMessenger, focus)
        try {
            val old = call(bridge, "beginMainTurn")
            call(bridge, "stop")
            assertEquals("MAIN_TURN_CANCELLED", old.errorCode)
            shadowOf(manager).setIsMusicActive(false)
            val current = call(bridge, "beginMainTurn")
            assertNotNull(current.value)
            shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1))
            assertEquals(1, old.completions)
            assertEquals(1, current.completions)
            assertTrue(focus.isHeld)
        } finally { bridge.dispose() }
    }

    @Test
    fun deniedMainFailsWithPlatformErrorAndInterruptedPendingPromptCannotContinue() {
        val bridge = VoicePromptBridge(RuntimeEnvironment.getApplication(), NoopMessenger, focus)
        try {
            shadowOf(manager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
            assertEquals("AUDIO_FOCUS_DENIED", call(bridge, "beginMainTurn").errorCode)
            shadowOf(manager).setNextFocusRequestResponse(AudioManager.AUDIOFOCUS_REQUEST_GRANTED)
            call(bridge, "beginMainTurn")
            focus.onInterrupted = { bridge.stopForAudioFocusLoss() }
            val prompt = call(bridge, "speakAndWait", mapOf("text" to "Hello"))
            shadowOf(manager).lastAudioFocusRequest.listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)
            assertEquals("AUDIO_FOCUS_LOST", prompt.errorCode)
            assertEquals(1, prompt.completions)
            assertFalse(focus.isHeld)
        } finally { bridge.dispose() }
    }

    private fun call(bridge: VoicePromptBridge, method: String, args: Map<String, Any?>? = null): Reply =
        Reply().also {
            bridge.onMethodCall(MethodCall(method, args), it)
            if (method == "beginMainTurn") {
                shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(100))
            }
        }

    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var completions = 0
        override fun success(result: Any?) { value = result; completions++ }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code; completions++ }
        override fun notImplemented() { completions++ }
    }

    private object NoopMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }
}
