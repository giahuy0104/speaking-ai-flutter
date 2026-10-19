package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BluetoothEnableRequestTest {
    private lateinit var context: Context
    private lateinit var host: HomiAndroidHost
    private lateinit var activity: Activity
    private lateinit var bridge: Aiv0BleControlBridge

    @Before
    fun setUp() {
        val application = RuntimeEnvironment.getApplication()
        context = application
        shadowOf(application).grantPermissions(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
        shadowOf(context.packageManager).setSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE, true)
        shadowOf(adapter()).setEnabled(false)
        host = HomiAndroidHost(context)
        attachActivity(Activity::class.java)
        bridge = Aiv0BleControlBridge(host, NoopMessenger)
    }

    @After
    fun tearDown() = bridge.dispose()

    @Test
    fun firstPermissionRequestUsesRuntimePromptWithoutOpeningSettings() {
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.BLUETOOTH_SCAN)
        assertEquals(false, call("bluetoothPermissionRequiresSettings").value)
        val reply = call("requestPermissions")
        val request = shadowOf(activity).lastRequestedPermission
        assertEquals(7395, request.requestCode)
        assertTrue(request.requestedPermissions.contains(Manifest.permission.BLUETOOTH_SCAN))
        assertEquals(0, reply.completions)
        assertEquals("android.content.pm.action.REQUEST_PERMISSIONS", shadowOf(activity).nextStartedActivity.action)
    }

    @Test
    fun temporaryDenialCanAskAgainButBlockedDenialRequiresSettings() {
        attachActivity(RationaleActivity::class.java)
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.BLUETOOTH_SCAN)
        (activity as RationaleActivity).showRationale = true
        call("requestPermissions")
        bridge.onRequestPermissionsResult(7395, intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals(false, call("bluetoothPermissionRequiresSettings").value)
        (activity as RationaleActivity).showRationale = false
        call("requestPermissions")
        bridge.onRequestPermissionsResult(7395, intArrayOf(PackageManager.PERMISSION_DENIED))
        assertEquals(true, call("bluetoothPermissionRequiresSettings").value)
        assertEquals("android.content.pm.action.REQUEST_PERMISSIONS", shadowOf(activity).nextStartedActivity.action)
        shadowOf(RuntimeEnvironment.getApplication()).grantPermissions(Manifest.permission.BLUETOOTH_SCAN)
        assertEquals(false, call("bluetoothPermissionRequiresSettings").value)
    }

    @Test
    fun interruptedPermissionRequestIsNotPermanentDenial() {
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.BLUETOOTH_SCAN)
        call("requestPermissions")
        bridge.onRequestPermissionsResult(7395, intArrayOf())
        assertEquals(false, call("bluetoothPermissionRequiresSettings").value)
        assertEquals("android.content.pm.action.REQUEST_PERMISSIONS", shadowOf(activity).nextStartedActivity.action)
    }

    @Test
    fun offAdapterUsesSystemEnableDialogWithoutOpeningSettings() {
        val reply = call("requestEnableBluetooth")
        val launched = shadowOf(host.currentActivity!!).nextStartedActivityForResult
        assertEquals(BluetoothAdapter.ACTION_REQUEST_ENABLE, launched.intent.action)
        assertEquals(7396, launched.requestCode)
        assertEquals(0, reply.completions)
        shadowOf(adapter()).setEnabled(true)
        assertTrue(bridge.onActivityResult(7396, Activity.RESULT_OK, null))
        assertEquals(true, reply.value)
        assertEquals(1, reply.completions)
        assertEquals("poweredOn", call("bluetoothAdapterState").value)
    }

    @Test
    fun acceptedDialogCannotClaimSuccessWhileRadioStillOff() {
        val reply = call("requestEnableBluetooth")
        bridge.onActivityResult(7396, Activity.RESULT_OK, null)
        assertEquals(false, reply.value)
        assertEquals("poweredOff", call("bluetoothAdapterState").value)
    }

    @Test
    fun deniedEnableDoesNotBlockNextRequest() {
        val first = call("requestEnableBluetooth")
        bridge.onActivityResult(7396, Activity.RESULT_CANCELED, null)
        assertEquals(false, first.value)
        val retry = call("requestEnableBluetooth")
        assertNull(retry.errorCode)
        assertEquals(0, retry.completions)
        shadowOf(adapter()).setEnabled(true)
        bridge.onActivityResult(7396, Activity.RESULT_OK, null)
        assertEquals(true, retry.value)
        assertEquals(1, first.completions)
    }

    @Test
    fun duplicateRequestDoesNotLaunchAnotherDialog() {
        val first = call("requestEnableBluetooth")
        shadowOf(host.currentActivity!!).nextStartedActivityForResult
        assertEquals("ENABLE_BLUETOOTH_IN_PROGRESS", call("requestEnableBluetooth").errorCode)
        assertNull(shadowOf(host.currentActivity!!).nextStartedActivityForResult)
        bridge.onActivityResult(7396, Activity.RESULT_CANCELED, null)
        assertEquals(1, first.completions)
    }

    @Test
    fun alreadyPoweredOnCompletesWithoutDialog() {
        shadowOf(adapter()).setEnabled(true)
        assertEquals(true, call("requestEnableBluetooth").value)
        assertNull(shadowOf(host.currentActivity!!).nextStartedActivityForResult)
    }

    @Test
    fun missingPermissionReportsUnauthorizedAndNeverLaunchesDialog() {
        shadowOf(RuntimeEnvironment.getApplication()).denyPermissions(Manifest.permission.BLUETOOTH_CONNECT)
        assertEquals("unauthorized", call("bluetoothAdapterState").value)
        assertEquals("PERMISSION_REQUIRED", call("requestEnableBluetooth").errorCode)
        assertNull(shadowOf(host.currentActivity!!).nextStartedActivityForResult)
        assertEquals(1, call("initialize").completions)
    }

    @Test
    fun unsupportedDeviceDoesNotOfferAnEnableDialog() {
        shadowOf(context.packageManager).setSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE, false)
        assertEquals("unsupported", call("bluetoothAdapterState").value)
        assertEquals("BLE_UNSUPPORTED", call("requestEnableBluetooth").errorCode)
        assertNull(shadowOf(host.currentActivity!!).nextStartedActivityForResult)
    }

    @Test
    fun transitioningAdapterDoesNotPretendToBeOnOrOff() {
        shadowOf(adapter()).setState(BluetoothAdapter.STATE_TURNING_ON)
        assertEquals("resetting", call("bluetoothAdapterState").value)
        shadowOf(adapter()).setState(BluetoothAdapter.STATE_TURNING_OFF)
        assertEquals("resetting", call("bluetoothAdapterState").value)
    }

    @Test
    fun deviceWithoutBluetoothServiceCanStillOpenAppAndReportUnsupported() {
        val noBluetoothContext = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun getSystemService(name: String): Any? =
                if (name == Context.BLUETOOTH_SERVICE) null else super.getSystemService(name)
        }
        bridge.dispose()
        bridge = Aiv0BleControlBridge(HomiAndroidHost(noBluetoothContext), NoopMessenger)
        assertEquals("unsupported", call("bluetoothAdapterState").value)
        assertEquals("BLE_UNSUPPORTED", call("requestEnableBluetooth").errorCode)
        val legacy = InnotrikBleAudioBridge(HomiAndroidHost(noBluetoothContext), NoopMessenger)
        try {
            val initialized = Reply()
            legacy.onMethodCall(MethodCall("initialize", null), initialized)
            assertEquals("unsupported", (initialized.value as Map<*, *>)["phase"])
        } finally {
            legacy.dispose()
        }
    }

    @Test
    fun enableRequiresForegroundActivity() {
        host.detach(host.currentActivity!!)
        assertEquals("VISIBLE_ACTIVITY_REQUIRED", call("requestEnableBluetooth").errorCode)
    }

    @Test
    fun deniedPermissionSettingsTargetsOnlyThisAppsDetails() {
        assertEquals(true, call("openPermissionSettings").value)
        val intent = shadowOf(activity).nextStartedActivity
        assertEquals(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, intent.action)
        assertEquals("package:${context.packageName}", intent.data.toString())
        assertEquals("poweredOff", call("bluetoothAdapterState").value)
    }

    @Test
    fun permissionSettingsReturnsFalseWithoutForegroundActivity() {
        host.detach(activity)
        assertEquals(false, call("openPermissionSettings").value)
        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Test
    fun unavailablePermissionSettingsSettlesFalseInsteadOfThrowing() {
        attachActivity(MissingSettingsActivity::class.java)
        val reply = call("openPermissionSettings")
        assertEquals(false, reply.value)
        assertEquals(1, reply.completions)
    }

    @Test
    fun blockedPermissionSettingsSettlesFalseInsteadOfThrowing() {
        attachActivity(BlockedSettingsActivity::class.java)
        val reply = call("openPermissionSettings")
        assertEquals(false, reply.value)
        assertEquals(1, reply.completions)
    }

    @Test
    fun failedDialogLaunchSettlesAndAllowsRetry() {
        attachActivity(MissingEnableActivity::class.java)
        val failed = call("requestEnableBluetooth")
        assertEquals("ENABLE_BLUETOOTH_UNAVAILABLE", failed.errorCode)
        assertEquals(1, failed.completions)
        attachActivity(Activity::class.java)
        val retry = call("requestEnableBluetooth")
        assertNull(retry.errorCode)
        assertEquals(0, retry.completions)
        bridge.onActivityResult(7396, Activity.RESULT_CANCELED, null)
        assertEquals(1, retry.completions)
    }

    @Test
    fun permissionRevokedDuringDialogLaunchDoesNotStrandRequest() {
        attachActivity(DeniedEnableActivity::class.java)
        assertEquals("PERMISSION_REQUIRED", call("requestEnableBluetooth").errorCode)
        attachActivity(Activity::class.java)
        assertNull(call("requestEnableBluetooth").errorCode)
    }

    @Test
    fun successfulEnableCallbackPreservesConnectionThatRecoveredFirst() {
        val reply = call("requestEnableBluetooth")
        shadowOf(adapter()).setEnabled(true)
        setField("phase", "connected")
        setField("message", "Verified MAIN connected")
        bridge.onActivityResult(7396, Activity.RESULT_OK, null)
        assertEquals(true, reply.value)
        val snapshot = call("status").value as Map<*, *>
        assertEquals("connected", snapshot["phase"])
        assertEquals("Verified MAIN connected", snapshot["message"])
        bridge.onActivityResult(7396, Activity.RESULT_CANCELED, null)
        assertEquals("connected", (call("status").value as Map<*, *>)["phase"])
        assertEquals(1, reply.completions)
    }

    @Test
    fun disposalSettlesRequestAndIgnoresLateActivityResult() {
        val reply = call("requestEnableBluetooth")
        bridge.dispose()
        assertEquals("DISPOSED", reply.errorCode)
        shadowOf(adapter()).setEnabled(true)
        bridge.onActivityResult(7396, Activity.RESULT_OK, null)
        assertEquals(1, reply.completions)
    }

    private fun adapter(): BluetoothAdapter =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private fun <T : Activity> attachActivity(type: Class<T>) {
        activity = Robolectric.buildActivity(type).setup().get()
        host.attach(activity)
    }
    private fun call(method: String): Reply = Reply().also {
        bridge.onMethodCall(MethodCall(method, null), it)
    }
    private fun setField(name: String, value: Any?) {
        Aiv0BleControlBridge::class.java.getDeclaredField(name).run {
            isAccessible = true
            set(bridge, value)
        }
    }

    class RationaleActivity : Activity() {
        var showRationale = false
        override fun shouldShowRequestPermissionRationale(permission: String): Boolean = showRationale
    }
    class MissingEnableActivity : Activity() {
        override fun startActivityForResult(intent: Intent?, requestCode: Int) {
            throw ActivityNotFoundException("No system Bluetooth activity")
        }
    }
    class DeniedEnableActivity : Activity() {
        override fun startActivityForResult(intent: Intent?, requestCode: Int) {
            throw SecurityException("Bluetooth permission revoked")
        }
    }
    class MissingSettingsActivity : Activity() {
        override fun startActivity(intent: Intent?) {
            throw ActivityNotFoundException("No app settings activity")
        }
    }
    class BlockedSettingsActivity : Activity() {
        override fun startActivity(intent: Intent?) {
            throw SecurityException("App settings disabled by policy")
        }
    }
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
