package com.innotrik.aispeaking

import android.Manifest
import android.content.Intent
import android.content.pm.ResolveInfo
import android.content.pm.ServiceInfo
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Looper
import android.speech.RecognitionService
import android.speech.RecognizerIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.AudioDeviceInfoBuilder
import org.robolectric.shadows.ShadowSpeechRecognizer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], shadows = [AndroidSpeechMicrophoneSourceTest.Capture::class])
class AndroidSpeechMicrophoneSourceTest {
    private lateinit var bridge: AndroidSpeechRecognizerBridge
    private lateinit var manager: AudioManager
    private lateinit var focus: AndroidAudioFocusCoordinator

    @Before fun setUp() {
        Capture.failStart = false
        Capture.lastSource = -1
        val app = RuntimeEnvironment.getApplication()
        shadowOf(app).grantPermissions(Manifest.permission.RECORD_AUDIO)
        shadowOf(app.packageManager).addResolveInfoForIntent(
            Intent(RecognitionService.SERVICE_INTERFACE),
            ResolveInfo().apply { serviceInfo = ServiceInfo().apply {
                packageName = "test.recognizer"; name = "RecognitionService"
            } },
        )
        manager = app.getSystemService(AudioManager::class.java)
        focus = AndroidAudioFocusCoordinator(manager)
        bridge = AndroidSpeechRecognizerBridge(HomiAndroidHost(app), NoopMessenger, focus)
    }

    @After fun tearDown() { bridge.dispose() }

    @Test fun connectedScoUsesAppPcmInsteadOfProviderMicrophone() {
        val sco = AudioDeviceInfoBuilder.newBuilder().setType(AudioDeviceInfo.TYPE_BLUETOOTH_SCO).build()
        shadowOf(manager).setInputDevices(listOf(sco))
        shadowOf(manager).setAvailableCommunicationDevices(listOf(sco))
        assertTrue(manager.setCommunicationDevice(sco))
        val reply = start()
        assertNull(reply.error)
        assertEquals(true, reply.value)
        val intent = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).lastRecognizerIntent
        assertTrue(intent.hasExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE))
        assertEquals(1, intent.getIntExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, -1))
        assertEquals(MediaRecorder.AudioSource.VOICE_COMMUNICATION, Capture.lastSource)
        assertTrue(focus.isHeld)
    }

    @Test fun missingScoInputDoesNotStartProviderOwnedCapture() {
        focus.acquire("main")
        val sco = AudioDeviceInfoBuilder.newBuilder().setType(AudioDeviceInfo.TYPE_BLUETOOTH_SCO).build()
        shadowOf(manager).setAvailableCommunicationDevices(listOf(sco))
        assertTrue(manager.setCommunicationDevice(sco))
        assertEquals("SPEECH_START_FAILED", start().error)
        assertNull(shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).lastRecognizerIntent)
        assertFalse(focus.isHeld)
    }

    @Test fun failedPhoneCaptureDoesNotFallBackToProviderMicrophone() {
        focus.acquire("main")
        Capture.failStart = true
        assertEquals("SPEECH_START_FAILED", start().error)
        assertNull(shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).lastRecognizerIntent)
        assertFalse(focus.isHeld)
    }

    @Test fun phoneMicrophoneAlsoUsesAppPcmWithoutChangingItsAudioSource() {
        assertNull(start().error)
        val intent = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).lastRecognizerIntent
        assertTrue(intent.hasExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE))
        assertEquals(MediaRecorder.AudioSource.VOICE_RECOGNITION, Capture.lastSource)
    }

    @Test @Config(sdk = [32]) fun olderAndroidRetainsProviderCapture() {
        assertNull(start().error)
        val intent = shadowOf(ShadowSpeechRecognizer.getLatestSpeechRecognizer()).lastRecognizerIntent
        assertFalse(intent.hasExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE))
        assertEquals(-1, Capture.lastSource)
    }

    @Test fun queuedSourceFailureAfterIntentionalStopDoesNotCancelPendingFinalResult() {
        focus.acquire("main")
        var interruptions = 0
        focus.onInterrupted = { interruptions++ }
        assertNull(start().error)
        queueSourceFailure()
        bridge.onMethodCall(MethodCall("speech.stop", null), Reply())
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, interruptions)
        assertTrue(focus.isHeld)
    }

    @Test fun queuedOldSourceFailureCannotCancelReplacementCapture() {
        assertNull(start().error)
        queueSourceFailure()
        assertNull(start().error)
        var interruptions = 0
        focus.onInterrupted = { interruptions++ }
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, interruptions)
        assertTrue(focus.isHeld)
    }

    private fun queueSourceFailure() {
        val sourceField = AndroidSpeechRecognizerBridge::class.java.getDeclaredField("appMicrophone")
        sourceField.isAccessible = true
        val source = sourceField.get(bridge) as AppMicrophoneAudioSource
        val callbackField = AppMicrophoneAudioSource::class.java.getDeclaredField("onFailure")
        callbackField.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        val callback = callbackField.get(source) as () -> Unit
        callback()
    }

    private fun start() = Reply().also {
        bridge.onMethodCall(MethodCall("speech.start", mapOf("turnId" to 1, "commandMode" to true)), it)
    }

    private class Reply : MethodChannel.Result {
        var value: Any? = null
        var error: String? = null
        override fun success(result: Any?) { value = result }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() = Unit
    }

    private object NoopMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }

    @Implements(AudioRecord::class)
    class Capture {
        @Implementation fun __constructor__(source: Int, rate: Int, channels: Int, encoding: Int, bytes: Int) {
            lastSource = source
        }
        @Implementation fun getState() = AudioRecord.STATE_INITIALIZED
        @Implementation fun setPreferredDevice(device: AudioDeviceInfo?) = true
        @Implementation fun startRecording() { if (failStart) throw IllegalStateException("busy") }
        @Implementation fun getRecordingState() = AudioRecord.RECORDSTATE_RECORDING
        @Implementation fun read(buffer: ByteArray, offset: Int, count: Int): Int { Thread.sleep(10); return 0 }
        @Implementation fun stop() = Unit
        @Implementation fun release() = Unit
        companion object {
            var failStart = false
            var lastSource = -1
            @Implementation @JvmStatic fun getMinBufferSize(rate: Int, channels: Int, encoding: Int) = 3200
        }
    }
}
