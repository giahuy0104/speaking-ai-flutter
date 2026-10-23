package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [31, 34])
class HomiClassicDiscoveryTest {
    private lateinit var context: Context
    private lateinit var adapter: BluetoothAdapter
    private lateinit var discovery: HomiClassicDiscovery
    private val address = "AA:BB:CC:DD:EE:01"

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(
            Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
        )
        adapter = context.getSystemService(BluetoothManager::class.java).adapter
        shadowOf(adapter).setEnabled(true)
        discovery = HomiClassicDiscovery(context)
    }

    @After
    fun tearDown() { discovery.cancel() }

    @Test
    fun discoversUnpairedHomiAndIgnoresUnnamedOrUnrelatedDevices() {
        val reply = Reply()
        discovery.start(reply, 15_000)
        assertTrue(adapter.isDiscovering)
        broadcast(BluetoothAdapter.ACTION_DISCOVERY_STARTED)
        found(address, "HM-D001")
        found("AA:BB:CC:DD:EE:02", "")
        found("AA:BB:CC:DD:EE:03", "Other headset")
        broadcast(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        val devices = reply.value as List<*>
        assertEquals(1, devices.size)
        assertEquals(address, (devices.single() as Map<*, *>)["id"])
        assertEquals("HM-D001", (devices.single() as Map<*, *>)["name"])
        assertFalse(adapter.isDiscovering)
        assertEquals(BluetoothDevice.BOND_NONE, adapter.getRemoteDevice(address).bondState)
        idleFor(30_000)
        assertEquals(1, reply.completions)
    }

    @Test
    fun cancellationSettlesOnceAndOldTimeoutCannotCompleteRetry() {
        val first = Reply()
        discovery.start(first, 2_000)
        idleFor(500)
        discovery.cancel()
        assertEquals("CONNECT_CANCELLED", first.errorCode)
        assertFalse(adapter.isDiscovering)
        val retry = Reply()
        discovery.start(retry, 15_000)
        // A finish queued by cancellation belongs to the preceding discovery.
        broadcast(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        idleFor(2_000)
        assertEquals(0, retry.completions)
        found(address, "HM-D001")
        idleFor(13_000)
        assertEquals(1, retry.completions)
        assertEquals(1, (retry.value as List<*>).size)
        assertEquals(1, first.completions)
    }

    @Test
    fun cancellingObserverDoesNotStopDiscoveryStartedBySettings() {
        assertTrue(adapter.startDiscovery())
        val reply = Reply()
        discovery.start(reply, 15_000)
        discovery.cancel()
        assertTrue(adapter.isDiscovering)
        assertEquals("CONNECT_CANCELLED", reply.errorCode)
        adapter.cancelDiscovery()
    }

    @Test
    fun concurrentDiscoveryIsRejectedWithoutReplacingOriginalResult() {
        val first = Reply()
        discovery.start(first, 15_000)
        val second = Reply()
        discovery.start(second, 15_000)
        assertEquals("SCAN_IN_PROGRESS", second.errorCode)
        idleFor(15_000)
        assertEquals(emptyList<Any>(), first.value)
        assertEquals(1, first.completions)
    }

    private fun found(id: String, name: String) {
        context.sendBroadcast(Intent(BluetoothDevice.ACTION_FOUND).apply {
            putExtra(BluetoothDevice.EXTRA_DEVICE, adapter.getRemoteDevice(id))
            putExtra(BluetoothDevice.EXTRA_NAME, name)
            putExtra(BluetoothDevice.EXTRA_RSSI, (-40).toShort())
        })
        shadowOf(Looper.getMainLooper()).idle()
    }
    private fun broadcast(action: String) {
        context.sendBroadcast(Intent(action))
        shadowOf(Looper.getMainLooper()).idle()
    }
    private fun idleFor(ms: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(ms))
    private class Reply : MethodChannel.Result {
        var completions = 0
        var value: Any? = null
        var errorCode: String? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(code: String, message: String?, details: Any?) { completions++; errorCode = code }
        override fun notImplemented() { throw AssertionError("Unexpected method") }
    }
}
