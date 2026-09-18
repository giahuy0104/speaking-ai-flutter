package com.innotrik.aispeaking

import android.media.AudioManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject

/** Enabled explicitly with adb shell setprop log.tag.HomiDiag DEBUG. */
internal object AudioDiagnostics {
    fun event(event: String, fields: Map<String, Any?> = emptyMap()) {
        if (!Log.isLoggable("HomiDiag", Log.DEBUG)) return
        runCatching {
            val data = JSONObject()
                .put("event", event)
                .put("utcMs", System.currentTimeMillis())
                .put("elapsedMs", SystemClock.elapsedRealtime())
            fields.forEach { (key, value) -> data.put(key, value ?: JSONObject.NULL) }
            Log.i("HomiDiag", data.toString())
        }
    }

    fun output(event: String, manager: AudioManager, fields: Map<String, Any?> = emptyMap()) {
        if (!Log.isLoggable("HomiDiag", Log.DEBUG)) return
        runCatching {
            @Suppress("DEPRECATION")
            val sco = manager.isBluetoothScoOn
            val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) manager.communicationDevice else null
            event(event, fields + mapOf(
                "mode" to manager.mode,
                "sco" to sco,
                "communicationDeviceType" to device?.type,
                "communicationDeviceId" to device?.id,
                "mediaVolume" to manager.getStreamVolume(AudioManager.STREAM_MUSIC),
                "mediaMax" to manager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
                "callVolume" to manager.getStreamVolume(AudioManager.STREAM_VOICE_CALL),
                "callMax" to manager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL),
            ))
        }
    }
}
