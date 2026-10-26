package com.innotrik.aispeaking

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Bounded, user-initiated discovery for an unpaired HOMI absent from BLE adverts. */
@SuppressLint("MissingPermission")
internal class HomiClassicDiscovery(private val context: Context) {
    private val adapter: BluetoothAdapter?
        get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var receiver: BroadcastReceiver? = null
    private var timeout: Runnable? = null
    private var ownsDiscovery = false
    private var discoveryStarted = false
    private val devices = linkedMapOf<String, Map<String, Any?>>()

    fun start(result: MethodChannel.Result, timeoutMs: Long) {
        if (pending != null) {
            result.error("SCAN_IN_PROGRESS", "Đang tìm HOMI chưa ghép đôi.", null)
            return
        }
        pending = result
        devices.clear()
        val callback = object : BroadcastReceiver() {
            @Suppress("DEPRECATION")
            override fun onReceive(context: Context?, intent: Intent?) {
                if (receiver !== this) return
                when (intent?.action) {
                    BluetoothAdapter.ACTION_DISCOVERY_STARTED -> discoveryStarted = true
                    BluetoothDevice.ACTION_FOUND, BluetoothDevice.ACTION_NAME_CHANGED -> {
                        val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                            ?: return
                        val name = intent.getStringExtra(BluetoothDevice.EXTRA_NAME)
                            ?.trim()?.takeIf { it.isNotEmpty() }
                            ?: runCatching { device.name?.trim() }.getOrNull().orEmpty()
                        val normalized = name.lowercase(Locale.ROOT)
                        val likely = normalized == "hm-d001" || normalized.contains("hm-d001") ||
                            normalized.contains("aiv0") || normalized.contains("innotrik")
                        // Never offer an unnamed nearby radio as a HOMI candidate.
                        if (!likely) return
                        val rssi = if (intent.hasExtra(BluetoothDevice.EXTRA_RSSI)) {
                            intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                        } else {
                            devices[device.address]?.get("rssi") as? Int ?: Short.MIN_VALUE.toInt()
                        }
                        devices[device.address] = mapOf(
                            "id" to device.address, "name" to name, "rssi" to rssi,
                            "isLikelyAiv0" to true, "advertisesControlService" to false,
                        )
                        BleDiagnostics.event(this@HomiClassicDiscovery.context, "classic.device", devices[device.address]!!)
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> if (discoveryStarted) finish()
                }
            }
        }
        receiver = callback
        val filter = IntentFilter(BluetoothDevice.ACTION_FOUND).apply {
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                // Bluetooth broadcasts originate in a separate system process.
                context.registerReceiver(callback, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                context.registerReceiver(callback, filter)
            }
            // Reuse system discovery if Settings already started it; do not
            // cancel a scan this operation does not own.
            discoveryStarted = adapter?.isDiscovering == true
            if (!discoveryStarted) {
                ownsDiscovery = adapter?.startDiscovery() == true
                if (!ownsDiscovery) {
                    fail("CLASSIC_SCAN_FAILED", "Android không bắt đầu được lượt tìm HOMI.")
                    return
                }
            }
            BleDiagnostics.event(context, "classic.request", mapOf("owned" to ownsDiscovery))
            val task = Runnable { if (pending === result) finish() }
            timeout = task
            handler.postDelayed(task, timeoutMs.coerceIn(2_000L, 15_000L))
        } catch (error: Exception) {
            fail("CLASSIC_SCAN_FAILED", "Không thể tìm HOMI: ${error.message}")
        }
    }

    fun cancel() = fail("CONNECT_CANCELLED", "Đã hủy tìm HOMI.")

    private fun finish() {
        val result = pending ?: return
        pending = null
        cleanup()
        BleDiagnostics.event(context, "classic.complete", mapOf("count" to devices.size))
        result.success(devices.values.toList())
    }

    private fun fail(code: String, message: String) {
        val result = pending
        pending = null
        cleanup()
        result?.error(code, message, null)
    }

    private fun cleanup() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
        val oldReceiver = receiver
        receiver = null
        oldReceiver?.let { runCatching { context.unregisterReceiver(it) } }
        if (ownsDiscovery) runCatching { adapter?.cancelDiscovery() }
        ownsDiscovery = false
        discoveryStarted = false
    }
}
