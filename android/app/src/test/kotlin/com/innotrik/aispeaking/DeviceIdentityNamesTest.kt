package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DeviceIdentityNamesTest {
    private lateinit var context: Context
    private lateinit var hfp: HfpAudioBridge
    private lateinit var ble: Aiv0BleControlBridge

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
        shadowOf(context.getSystemService(BluetoothManager::class.java).adapter).setEnabled(true)
        context.getSharedPreferences("homi_android_runtime", Context.MODE_PRIVATE)
            .edit().clear().commit()
        hfp = HfpAudioBridge(HomiAndroidHost(context), NoopMessenger)
        ble = Aiv0BleControlBridge(HomiAndroidHost(context), NoopMessenger)
    }

    @After
    fun tearDown() {
        hfp.dispose()
        ble.dispose()
    }

    @Test
    fun unnamedBleIsNotRenamedOrClassifiedAsH20() {
        val device = device("AA:BB:CC:DD:EE:01")
        @Suppress("DEPRECATION")
        val scan = ScanResult(device, null, -40, 0)
        Aiv0BleControlBridge::class.java.getDeclaredMethod("addScanResult", ScanResult::class.java)
            .apply { isAccessible = true }
            .invoke(ble, scan)
        val devices = Aiv0BleControlBridge::class.java.getDeclaredField("scanDevices")
            .apply { isAccessible = true }
            .get(ble) as Map<*, *>
        val found = devices.values.single()!!
        val values = found.javaClass.getDeclaredMethod("toMap")
            .apply { isAccessible = true }
            .invoke(found) as Map<*, *>
        assertEquals("", values["name"])
        assertEquals(false, values["isLikelyAiv0"])
    }

    @Test
    fun unnamedMicrophoneKeepsRawNameEmptyForAppLocalization() {
        assertEquals("", name(device("AA:BB:CC:DD:EE:01")))
    }

    @Test
    fun realH20NameIsPreserved() {
        val device = device("AA:BB:CC:DD:EE:01")
        shadowOf(device).setName("H20")
        assertEquals("H20", name(device))
    }

    @Test
    fun twoUnknownNamesAreNotEvidenceOfTheSameHeadset() {
        val selected = device("AA:BB:CC:DD:EE:01")
        val other = device("AA:BB:CC:DD:EE:02")
        HfpAudioBridge::class.java.getDeclaredField("selectedDevice")
            .apply { isAccessible = true }
            .set(hfp, selected)
        val event = Intent(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            .putExtra(BluetoothDevice.EXTRA_DEVICE, other)
        val matches = HfpAudioBridge::class.java.getDeclaredMethod(
            "isSelectedDeviceEvent",
            Intent::class.java,
        ).apply { isAccessible = true }.invoke(hfp, event) as Boolean
        assertFalse(matches)
    }

    @Test
    fun aDifferentAddressWithTheSameNameDoesNotAffectTheSelectedHeadset() {
        val selected = device("AA:BB:CC:DD:EE:01")
        val other = device("AA:BB:CC:DD:EE:02")
        shadowOf(selected).setName("HM-D001")
        shadowOf(other).setName("HM-D001")
        HfpAudioBridge::class.java.getDeclaredField("selectedDevice")
            .apply { isAccessible = true }.set(hfp, selected)
        val event = Intent(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            .putExtra(BluetoothDevice.EXTRA_DEVICE, other)
        val matches = HfpAudioBridge::class.java.getDeclaredMethod(
            "isSelectedDeviceEvent",
            Intent::class.java,
        ).apply { isAccessible = true }.invoke(hfp, event) as Boolean
        assertFalse(matches)
    }

    @Test
    fun explicitBleDisconnectSurvivesServiceAndBridgeRestart() {
        val preferences = context.getSharedPreferences("homi_android_runtime", Context.MODE_PRIVATE)
        preferences.edit()
            .putString("h20_ble_device_id", "AA:BB:CC:DD:EE:01")
            .putString("h20_ble_device_name", "HM-D001")
            .commit()
        ble.onMethodCall(MethodCall("disconnect", null), Result())
        assertTrue(preferences.getBoolean("h20_ble_manual_disconnect", false))
        ble.dispose()
        ble = Aiv0BleControlBridge(HomiAndroidHost(context), NoopMessenger)
        ble.onBackgroundSessionStarted()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(shadowOf(device("AA:BB:CC:DD:EE:01")).bluetoothGatts.isEmpty())
        assertEquals("HM-D001", preferences.getString("h20_ble_device_name", null))
    }

    @Test
    fun cancelDoesNotOptOutAndAnExplicitConnectReenablesRecovery() {
        val preferences = context.getSharedPreferences("homi_android_runtime", Context.MODE_PRIVATE)
        ble.onMethodCall(MethodCall("cancelConnectionAttempt", null), Result())
        assertFalse(preferences.getBoolean("h20_ble_manual_disconnect", false))
        ble.onMethodCall(MethodCall("disconnect", null), Result())
        ble.onMethodCall(
            MethodCall("connect", mapOf("deviceId" to "AA:BB:CC:DD:EE:01")),
            Result(),
        )
        assertFalse(preferences.getBoolean("h20_ble_manual_disconnect", true))
        ble.onMethodCall(MethodCall("cancelConnectionAttempt", null), Result())
        assertFalse(preferences.getBoolean("h20_ble_manual_disconnect", true))
    }

    @Test
    fun cancelRejectsAQueuedHfpConnectAndPreservesTheExistingSelection() {
        val selected = device("AA:BB:CC:DD:EE:01")
        val selectedField = HfpAudioBridge::class.java.getDeclaredField("selectedDevice")
            .apply { isAccessible = true }
        selectedField.set(hfp, selected)
        val connectResult = Result()
        hfp.onMethodCall(
            MethodCall("connect", mapOf("deviceId" to "AA:BB:CC:DD:EE:02")),
            connectResult,
        )
        hfp.onMethodCall(MethodCall("cancelConnectionAttempt", null), Result())
        val routeThread = HfpAudioBridge::class.java.getDeclaredField("routeThread")
            .apply { isAccessible = true }.get(hfp) as HandlerThread
        shadowOf(routeThread.looper).idle()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("HFP_CONNECT_CANCELLED", connectResult.errorCode)
        assertEquals(selected, selectedField.get(hfp))
    }

    private fun device(address: String): BluetoothDevice =
        context.getSystemService(BluetoothManager::class.java).adapter.getRemoteDevice(address)

    private fun name(device: BluetoothDevice): Any? =
        HfpAudioBridge::class.java.getDeclaredMethod("safeName", BluetoothDevice::class.java)
            .apply { isAccessible = true }
            .invoke(hfp, device)

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

    private class Result : MethodChannel.Result {
        var errorCode: String? = null
        override fun success(value: Any?) = Unit
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() = Unit
    }
}
