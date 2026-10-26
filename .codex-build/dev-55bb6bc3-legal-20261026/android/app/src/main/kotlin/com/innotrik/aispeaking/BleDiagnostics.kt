package com.innotrik.aispeaking

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

/** Explicitly enabled local diagnostics; no audio or control payloads are recorded. */
internal object BleDiagnostics {
    @Synchronized
    fun event(context: Context, event: String, fields: Map<String, Any?> = emptyMap()) {
        if (!Log.isLoggable("HomiBleDiag", Log.DEBUG)) return
        runCatching {
            val record = JSONObject(fields).put("event", event)
                .put("utcMs", System.currentTimeMillis()).toString()
            Log.i("HomiBleDiag", record)
            val directory = context.getExternalFilesDir(null) ?: return
            val file = File(directory, "ble-diagnostic.jsonl")
            if (file.length() > 2_000_000) {
                file.copyTo(File(directory, "ble-diagnostic.previous.jsonl"), overwrite = true)
                file.writeText("")
            }
            file.appendText(record + "\n")
        }
    }
}
