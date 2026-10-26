package com.innotrik.aispeaking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthoredPromptLevelTest {
    /**
     * Hồi quy cho lỗi số đo runtime đè lên manifest: đảo lại thứ tự ưu tiên là
     * test này đỏ. Trước đây clip nghe một mức ở lần phát đầu và một mức khác
     * từ lần thứ hai, đúng thứ manifest sinh ra để loại bỏ.
     */
    @Test fun manifestGainOutranksARuntimeMeasurement() {
        assertEquals(
            -6.3,
            AuthoredPromptLevel.gainDb(manifestGainDb = -6.3, measuredGainDb = -5.4),
            0.0001,
        )
    }

    @Test fun aClipTheManifestDoesNotCoverStillUsesItsMeasurement() {
        assertEquals(
            4.2,
            AuthoredPromptLevel.gainDb(manifestGainDb = null, measuredGainDb = 4.2),
            0.0001,
        )
    }

    @Test fun nothingMeasuredFallsBackToTheCallerSNumber() {
        assertEquals(
            AuthoredPromptLevel.DEFAULT_GAIN_DB,
            AuthoredPromptLevel.gainDb(manifestGainDb = null, measuredGainDb = null),
            0.0001,
        )
        assertEquals(
            1.5,
            AuthoredPromptLevel.gainDb(
                manifestGainDb = null,
                measuredGainDb = null,
                fallbackGainDb = 1.5,
            ),
            0.0001,
        )
    }

    /** Manifest đã có số thì không giải mã lại — vừa thừa vừa gây lệch mức. */
    @Test fun onlyAClipWithoutAManifestGainIsDecoded() {
        assertFalse(AuthoredPromptLevel.shouldMeasure(-6.3))
        assertFalse(AuthoredPromptLevel.shouldMeasure(0.0))
        assertTrue(AuthoredPromptLevel.shouldMeasure(null))
    }
}
