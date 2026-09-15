package com.innotrik.aispeaking

import android.annotation.SuppressLint
import android.companion.CompanionDeviceService
import android.os.Build
import androidx.annotation.RequiresApi

/** Lets Android raise HOMI's process priority while the associated H20 is near. */
@SuppressLint("MissingPermission")
@RequiresApi(Build.VERSION_CODES.S)
class HomiCompanionDeviceService : CompanionDeviceService() {
    @Suppress("DEPRECATION")
    override fun onDeviceAppeared(address: String) {
        if (BackgroundLearningService.wasRequested(this)) {
            BackgroundLearningService.startFromCompanion(this)
        }
    }

    @Suppress("DEPRECATION")
    override fun onDeviceDisappeared(address: String) = Unit
}
