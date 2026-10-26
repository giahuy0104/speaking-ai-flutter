package com.innotrik.aispeaking

/** Drops callbacks queued by a cancelled/replaced recognizer turn. */
internal class SpeechRecognitionTurnGate(
    private val generation: Int,
    private val currentGeneration: () -> Int,
) {
    private var finished = false

    fun accepts(terminal: Boolean = false): Boolean {
        if (finished || generation != currentGeneration()) return false
        if (terminal) finished = true
        return true
    }
}
