package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.time.Duration
import java.util.UUID
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
@Config(sdk = [34])
class Aiv0ConnectionCancellationTest {
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
        shadowOf(context.packageManager).setSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE, true)
        shadowOf(adapter()).setEnabled(true)
        bridge = Aiv0BleControlBridge(HomiAndroidHost(context), NoopMessenger)
        bridge.onListen(null, object : EventChannel.EventSink {
            override fun success(event: Any?) { (event as? Map<*, *>)?.let(statuses::add) }
            override fun error(code: String?, message: String?, details: Any?) = Unit
            override fun endOfStream() = Unit
        })
    }

    @After
    fun tearDown() { bridge.dispose() }

    @Test
    fun cancelledScanTimeoutCannotStopImmediateRetryScan() {
        val first = call("scan", mapOf("timeoutMs" to 2_000))
        idleFor(500)
        assertEquals(1, call("cancelConnectionAttempt").completions)
        assertEquals(1, first.completions)
        val retry = call("scan", mapOf("timeoutMs" to 8_000))
        idleFor(1_600)
        assertEquals("scanning", statuses.last()["phase"])
        assertEquals("old scan timeout must not complete the new scan", 0, retry.completions)
        idleFor(6_400)
        assertEquals(1, retry.completions)
        assertEquals(1, first.completions)
    }

    @Test
    fun cancelSettlesConnectOnceAndAllowsImmediateRetry() {
        val first = call("connect", mapOf("deviceId" to address))
        val oldGatt = gatts().last()
        call("cancelConnectionAttempt")
        assertEquals("CONNECT_CANCELLED", first.errorCode)
        val retry = call("connect", mapOf("deviceId" to address))
        assertEquals(0, retry.completions)
        val replacement = gatts().last()
        shadowOf(oldGatt).notifyDisconnection(address)
        idle()
        assertSame(replacement, field("bluetoothGatt"))
        call("cancelConnectionAttempt")
        idleFor(60_000)
        assertEquals(1, first.completions)
        assertEquals(1, retry.completions)
        assertEquals("CONNECT_CANCELLED", retry.errorCode)
        assertEquals(2, gatts().size)
    }

    @Test
    fun cancelStopsScheduledNativeReconnect() {
        call("connect", mapOf("deviceId" to address))
        (field("gattCallback") as BluetoothGattCallback).onConnectionStateChange(
            gatts().last(), BluetoothGatt.GATT_SUCCESS, BluetoothProfile.STATE_DISCONNECTED,
        )
        idle()
        assertEquals("reconnecting", statuses.last()["phase"])
        call("cancelConnectionAttempt")
        idleFor(60_000)
        assertEquals(1, gatts().size)
        assertEquals("idle", statuses.last()["phase"])
    }

    @Test
    fun cancelRetainsVerifiedBleLinkWhileHfpSearchIsPending() {
        call("connect", mapOf("deviceId" to address))
        val gatt = gatts().last()
        setField("connectResult", null)
        setField("phase", "connected")
        setField("buttonCharacteristic", characteristic("9E3B0002-4A7C-4D6F-8B21-5C17A2D94010"))
        setField("stateCharacteristic", characteristic("9E3B0003-4A7C-4D6F-8B21-5C17A2D94010"))
        call("cancelConnectionAttempt")
        assertSame(gatt, field("bluetoothGatt"))
        assertEquals("connected", statuses.last()["phase"])
        assertEquals(true, field("shouldReconnect"))
    }

    @Test
    fun cancelSettlesBondAndWriteCallbacks() {
        val bond = Reply()
        val write = Reply()
        setField("bondResult", bond)
        setField("pendingWriteResult", write)
        call("cancelConnectionAttempt")
        idleFor(60_000)
        assertEquals(1, bond.completions)
        assertEquals(false, bond.value)
        assertEquals(1, write.completions)
        assertEquals("CONNECT_CANCELLED", write.errorCode)
        assertNull(field("bondResult"))
        assertNull(field("pendingWriteResult"))
    }

    @Test
    fun serviceStopUsesSameCancellationAndDoesNotStrandConnect() {
        val first = call("connect", mapOf("deviceId" to address))
        bridge.onBackgroundSessionStopped()
        idle()
        assertEquals("CONNECT_CANCELLED", first.errorCode)
        val next = call("connect", mapOf("deviceId" to address))
        assertEquals(0, next.completions)
        assertEquals(2, gatts().size)
    }

    private fun characteristic(id: String) = BluetoothGattCharacteristic(UUID.fromString(id), 0, 0)
    private fun field(name: String): Any? = Aiv0BleControlBridge::class.java.getDeclaredField(name).run {
        isAccessible = true
        get(bridge)
    }
    private fun setField(name: String, value: Any?) {
        Aiv0BleControlBridge::class.java.getDeclaredField(name).run {
            isAccessible = true
            set(bridge, value)
        }
    }
    private fun call(method: String, args: Map<String, Any?>? = null): Reply = Reply().also {
        bridge.onMethodCall(MethodCall(method, args), it)
    }
    private fun adapter(): BluetoothAdapter =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private fun gatts(): List<BluetoothGatt> = shadowOf(adapter().getRemoteDevice(address)).bluetoothGatts
    private fun idle() = shadowOf(Looper.getMainLooper()).idle()
    private fun idleFor(milliseconds: Long) =
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds))

    private class Reply : MethodChannel.Result {
        var completions = 0
        var errorCode: String? = null
        var value: Any? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(code: String, message: String?, details: Any?) { completions++; errorCode = code }
        override fun notImplemented() { completions++ }
    }
    private object NoopMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }
}
