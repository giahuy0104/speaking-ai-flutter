package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import org.json.JSONObject
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
    @Config(sdk = [31, 34])
    fun radioCycleDuringScanReleasesPendingScanAndAllowsFreshUnfilteredRetry() {
        val first = call("scan", mapOf("foreground" to true, "timeoutMs" to 8_000))
        val oldCallback = field("scanCallback") as ScanCallback
        idleFor(500)
        shadowOf(adapter()).setEnabled(false)
        for (state in listOf(BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF)) {
            context.sendBroadcast(Intent(BluetoothAdapter.ACTION_STATE_CHANGED).apply {
                putExtra(BluetoothAdapter.EXTRA_STATE, state)
            })
            idle()
        }
        assertEquals(1, first.completions)
        assertEquals("idle", statuses.last()["phase"])
        assertNull(field("scanCallback"))
        shadowOf(adapter()).setEnabled(true)
        context.sendBroadcast(Intent(BluetoothAdapter.ACTION_STATE_CHANGED).apply {
            putExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.STATE_ON)
        })
        idle()
        assertEquals("idle", statuses.last()["phase"])
        val retry = call("scan", mapOf("foreground" to true, "timeoutMs" to 8_000))
        val scanner = shadowOf(adapter().bluetoothLeScanner)
        assertTrue(scanner.activeScans.single().scanFilters().isNullOrEmpty())
        assertTrue(gatts().isEmpty())
        // A callback from the pre-toggle scan must not complete the new attempt.
        oldCallback.onScanFailed(ScanCallback.SCAN_FAILED_INTERNAL_ERROR)
        assertEquals(0, retry.completions)
        assertEquals("scanning", statuses.last()["phase"])
        val name = "HM-D001".toByteArray()
        val bytes = byteArrayOf((name.size + 1).toByte(), 9) + name + byteArrayOf(0)
        val record = ScanRecord::class.java.getDeclaredMethod("parseFromBytes", ByteArray::class.java)
            .invoke(null, bytes) as ScanRecord
        (field("scanCallback") as ScanCallback).onScanResult(
            ScanSettings.CALLBACK_TYPE_ALL_MATCHES,
            ScanResult(adapter().getRemoteDevice(address), record, -40, 0L),
        )
        idleFor(7_600)
        assertEquals(0, retry.completions)
        idleFor(400)
        assertEquals(1, retry.completions)
        val device = (retry.value as List<*>).single() as Map<*, *>
        assertEquals("HM-D001", device["name"])
        assertEquals(true, device["isLikelyAiv0"])
        assertTrue(scanner.activeScans.isEmpty())
    }

    @Test
    fun weakerScanResponseRetainsHomiNameAndServiceAcrossLaterPackets() {
        val reply = call("scan", mapOf("timeoutMs" to 2_000))
        val callback = field("scanCallback") as ScanCallback
        val device = adapter().getRemoteDevice(address)
        fun packet(bytes: ByteArray, rssi: Int) {
            val record = ScanRecord::class.java.getDeclaredMethod("parseFromBytes", ByteArray::class.java)
                .invoke(null, bytes) as ScanRecord
            callback.onScanResult(ScanSettings.CALLBACK_TYPE_ALL_MATCHES, ScanResult(device, record, rssi, 0L))
        }
        packet(byteArrayOf(2, 1, 6, 0), -30)
        val uuid = "9e3b00014a7c4d6f8b215c17a2d94010".chunked(2).map { it.toInt(16).toByte() }.reversed().toByteArray()
        val name = "HM-D001".toByteArray()
        packet(byteArrayOf(17, 7) + uuid + byteArrayOf((name.size + 1).toByte(), 9) + name + byteArrayOf(0), -60)
        packet(byteArrayOf(2, 1, 6, 0), -25)
        idleFor(2_000)
        val result = (reply.value as List<*>).single() as Map<*, *>
        assertEquals("HM-D001", result["name"])
        assertEquals(true, result["advertisesControlService"])
        assertEquals(true, result["isLikelyAiv0"])
        assertEquals(-25, result["rssi"])
    }

    @Test
    fun foregroundScanUsesLowLatencyAndBackgroundRetainsDefaultMode() {
        val scanner = shadowOf(adapter().bluetoothLeScanner)
        call("scan", mapOf("timeoutMs" to 8_000, "foreground" to true))
        assertEquals(ScanSettings.SCAN_MODE_LOW_LATENCY, scanner.activeScans.single().scanSettings()!!.scanMode)
        assertEquals(0L, scanner.activeScans.single().scanSettings()!!.reportDelayMillis)
        call("cancelConnectionAttempt")
        assertTrue(scanner.activeScans.isEmpty())
        call("scan", mapOf("timeoutMs" to 4_000))
        assertEquals(ScanSettings.SCAN_MODE_LOW_POWER, scanner.activeScans.single().scanSettings()!!.scanMode)
    }

    @Test
    fun connectionTimeoutDoesNotClaimProtocolMismatch() {
        val reply = call("connect", mapOf("deviceId" to address))
        idleFor(15_000)
        assertEquals("BLE_CONNECTION_TIMEOUT", reply.errorCode)
        assertEquals(1, reply.completions)
    }

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

    @Test
    fun cccdFailureNeverPublishesMainReady() {
        call("connect", mapOf("deviceId" to address, "attemptId" to "cccd-failure"))
        val gatt = gatts().last()
        val descriptor = mainDescriptor()
        (field("gattCallback") as BluetoothGattCallback).onDescriptorWrite(
            gatt, descriptor, BluetoothGatt.GATT_FAILURE,
        )
        idle()
        assertFalse(statuses.any { it["phase"] == "connected" })
        val records = diagnosticRecords("cccd-failure")
        assertTrue(records.any { it.optString("event") == "gatt.cccd.result" && it.getInt("status") == BluetoothGatt.GATT_FAILURE })
        assertFalse(records.any { it.optString("event") == "main.ready" })
    }

    @Test
    fun cccdSuccessPublishesReadyOnlyForCurrentGattAndKeepsOldAttemptId() {
        val first = call("connect", mapOf("deviceId" to address, "attemptId" to "cccd-old"))
        val oldGatt = gatts().last()
        call("cancelConnectionAttempt")
        val retry = call("connect", mapOf("deviceId" to address, "attemptId" to "cccd-new"))
        val descriptor = mainDescriptor()
        val callback = field("gattCallback") as BluetoothGattCallback
        callback.onDescriptorWrite(oldGatt, descriptor, BluetoothGatt.GATT_SUCCESS)
        idle()
        assertEquals("CONNECT_CANCELLED", first.errorCode)
        assertEquals(0, retry.completions)
        assertFalse(statuses.any { it["phase"] == "connected" })
        val oldRecords = diagnosticRecords("cccd-old")
        assertTrue(oldRecords.any { it.optString("event") == "gatt.cccd.result" && !it.getBoolean("currentGatt") })
        assertFalse(oldRecords.any { it.optString("event") == "main.ready" })
        callback.onDescriptorWrite(gatts().last(), descriptor, BluetoothGatt.GATT_SUCCESS)
        idle()
        assertEquals(1, retry.completions)
        assertEquals("connected", (retry.value as Map<*, *>)["phase"])
        assertEquals("connected", statuses.last()["phase"])
        assertTrue(diagnosticRecords("cccd-new").any { it.optString("event") == "main.ready" && it.getBoolean("cccdConfirmed") })
    }

    @Test
    fun cancelledScanCannotTagNewScanWithItsAttemptOrFailure() {
        call("scan", mapOf("timeoutMs" to 2_000, "attemptId" to "scan-old"))
        val oldCallback = field("scanCallback") as ScanCallback
        call("cancelConnectionAttempt")
        val retry = call("scan", mapOf("timeoutMs" to 2_000, "attemptId" to "scan-new"))
        oldCallback.onScanFailed(ScanCallback.SCAN_FAILED_INTERNAL_ERROR)
        idleFor(2_000)
        assertEquals(1, retry.completions)
        val records = diagnosticRecords("scan-new")
        assertTrue(records.any { it.optString("event") == "scan.complete" })
        assertFalse(records.any { it.optString("event") == "scan.failed" })
    }

    private fun mainDescriptor(): BluetoothGattDescriptor {
        val button = characteristic("9E3B0002-4A7C-4D6F-8B21-5C17A2D94010")
        val descriptor = BluetoothGattDescriptor(
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
            BluetoothGattDescriptor.PERMISSION_WRITE,
        )
        button.addDescriptor(descriptor)
        setField("buttonCharacteristic", button)
        setField("stateCharacteristic", characteristic("9E3B0003-4A7C-4D6F-8B21-5C17A2D94010"))
        return descriptor
    }

    private fun diagnosticRecords(attempt: String): List<JSONObject> =
        File(context.getExternalFilesDir(null), "ble-diagnostic.jsonl")
            .readLines().map(::JSONObject).filter { it.optString("attemptId") == attempt }

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
