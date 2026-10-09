package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import java.nio.ByteBuffer
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowBluetoothGatt

/** A GATT whose link comes up but whose service discovery never answers. */
@Implements(BluetoothGatt::class)
class HangingDiscoveryGatt : ShadowBluetoothGatt() {
    @Implementation
    override fun discoverServices(): Boolean = true
}

/**
 * Tester evidence 2026-10-09 (Xiaomi, HM-D001): after Bluetooth was switched
 * off and on from the home screen the GATT link came back but service
 * discovery never answered, and the 15 s timeout ended automatic recovery with
 * "quá thời gian 15 giây" until the app was resumed by hand.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], shadows = [HangingDiscoveryGatt::class])
class Aiv0BleControlBridgeRecoveryTest {
    private val address = "AA:BB:CC:DD:EE:01"
    private lateinit var context: Context
    private lateinit var bridge: Aiv0BleControlBridge
    private val statuses = mutableListOf<Map<*, *>>()

    @Before
    fun setUp() {
        val application = RuntimeEnvironment.getApplication()
        context = application
        shadowOf(application).grantPermissions(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
        shadowOf(context.packageManager)
            .setSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE, true)
        shadowOf(adapter()).setEnabled(true)
        context.getSharedPreferences("homi_android_runtime", Context.MODE_PRIVATE)
            .edit()
            .putString("h20_ble_device_id", address)
            .putString("h20_ble_device_name", "HM-D001")
            .commit()
        bridge = Aiv0BleControlBridge(HomiAndroidHost(context), NoopMessenger)
        bridge.onListen(
            null,
            object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    (event as? Map<*, *>)?.let(statuses::add)
                }

                override fun error(code: String?, message: String?, details: Any?) = Unit

                override fun endOfStream() = Unit
            },
        )
    }

    @Test
    fun stalledDiscoveryAfterBluetoothReturnsTakesTheNextRetry() {
        bridge.onBackgroundSessionStarted()
        idle()
        assertEquals(1, gatts().size)

        broadcastAdapterState(BluetoothAdapter.STATE_OFF)
        assertEquals("idle", lastPhase())
        broadcastAdapterState(BluetoothAdapter.STATE_ON)
        assertEquals("reconnecting", lastPhase())
        idleFor(Duration.ofSeconds(1))
        assertEquals(2, gatts().size)

        // The link comes up; HangingDiscoveryGatt never answers discoverServices().
        shadowOf(gatts()[1]).notifyConnection(address)
        idleFor(Duration.ofSeconds(15))

        assertEquals("after timeout: ${lastMessage()}", "reconnecting", lastPhase())
        idleFor(Duration.ofSeconds(1))
        assertEquals("next attempt opened", 3, gatts().size)
    }

    private fun adapter(): BluetoothAdapter =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private fun gatts(): List<BluetoothGatt> =
        shadowOf(adapter().getRemoteDevice(address)).bluetoothGatts

    private fun broadcastAdapterState(state: Int) {
        context.sendBroadcast(
            Intent(BluetoothAdapter.ACTION_STATE_CHANGED)
                .putExtra(BluetoothAdapter.EXTRA_STATE, state),
        )
        idle()
    }

    private fun lastPhase(): Any? = statuses.last()["phase"]

    private fun lastMessage(): Any? = statuses.last()["message"]

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun idleFor(duration: Duration) = shadowOf(Looper.getMainLooper()).idleFor(duration)

    private object NoopMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) = Unit

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) = Unit
    }
}
