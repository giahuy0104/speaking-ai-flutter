package com.innotrik.aispeaking

import android.media.AudioTrack
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31])
class LessonAudioHandoffOutputTest {
    @Test fun staticOutputIsInitializedByWritingBeforePlaying() {
        lateinit var track: AudioTrack
        val output = createLessonHandoffOutput {
            track = it
            true
        }
        try {
            assertEquals(AudioTrack.STATE_INITIALIZED, track.state)
            assertEquals(AudioTrack.PLAYSTATE_PLAYING, track.playState)
        } finally {
            output.release()
        }
        assertEquals(AudioTrack.STATE_UNINITIALIZED, track.state)
    }

    @Test fun rejectedSelectedDeviceReleasesPartiallyCreatedTrack() {
        lateinit var track: AudioTrack
        try {
            createLessonHandoffOutput {
                track = it
                false
            }
            fail("Expected output selection failure")
        } catch (_: IllegalStateException) {
            assertEquals(AudioTrack.STATE_UNINITIALIZED, track.state)
        }
    }
}
