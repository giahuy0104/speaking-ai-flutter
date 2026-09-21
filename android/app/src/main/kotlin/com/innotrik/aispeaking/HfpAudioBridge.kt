package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executor

/**
 * Routes Android speech recognition through a Bluetooth Classic HFP/SCO mic.
 *
 * Public Android APIs do not let third-party apps connect the HFP profile.
 * This bridge lists paired HFP-capable devices, opens Bluetooth Settings when
 * the chosen profile is not connected yet, and selects the connected SCO input.
 */
class HfpAudioBridge(
    private val host: HomiAndroidHost,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_hfp_audio"
        private const val EVENT_CHANNEL = "ailingo_hfp_audio/events"
        private const val PERMISSION_REQUEST_CODE = 7393
        private const val AUDIO_ROUTE_SETTLE_MS = 150L
        private const val AUDIO_ROUTE_CONFIRM_INTERVAL_MS = 100L
        private const val AUDIO_ROUTE_REASSERT_DELAY_MS = 250L
        // Xiaomi/MediaTek can block setCommunicationDevice for more than two
        // seconds while SCO is renegotiated even though the HFP profile remains
        // connected. Match the initial route budget so that late, valid route
        // confirmation is not reported to Flutter as HFP_ROUTE_LOST.
        private const val ACTIVE_ROUTE_RECOVERY_TIMEOUT_MS = 5000L
        private const val AUDIO_ROUTE_LOSS_CLEANUP_DELAY_MS = 100L
        private const val AUDIO_ROUTE_CONFIRM_ATTEMPTS = 25
        private const val TAG = "HfpAudioBridge"

        private val HFP_UUIDS =
            setOf(
                UUID.fromString("00001108-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("0000111e-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("00001112-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("0000111f-0000-1000-8000-00805f9b34fb"),
            )
    }

    private val methodChannel = MethodChannel(messenger, CONTROL_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val appContext = host.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter
    private val audioManager =
        appContext.getSystemService(AudioManager::class.java)
    // AudioManager's binder calls can block for several seconds during SCO
    // negotiation on MIUI. Keep route state and ALL platform route operations
    // on one serial worker; Flutter/platform callbacks must remain responsive.
    private val routeThread = HandlerThread("homi-hfp-route").apply { start() }
    private val routeHandler = Handler(routeThread.looper)
    private val routeExecutor = Executor { command -> routeHandler.post(command) }
    private val routeDispatch = HfpRouteDispatch(routeExecutor, host.mainExecutor) {
        Looper.myLooper() == routeThread.looper
    }

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    private var headset: BluetoothHeadset? = null
    private var selectedDevice: BluetoothDevice? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingAudioRouteResult: MethodChannel.Result? = null
    private var pendingAudioRouteGeneration: Int? = null
    private var audioRouteRequestGeneration = 0
    private var phase = "idle"
    private var statusMessage: String? = null
    private var routeActive = false
    private var previousAudioMode = AudioManager.MODE_NORMAL
    private var audioModeOwned = false
    @Volatile private var disposed = false
    @Volatile private var disposalRequested = false
    private var routeReadiness: HfpRouteReadiness? = null
    private var activeRouteRecovery: HfpRouteReadiness? = null
    private var activeRouteRecoveryGeneration: Int? = null
    private var activeRouteRecoveryReason: String? = null
    var onUnexpectedRouteLoss: () -> Unit = {}
    private var communicationDeviceListener: AudioManager.OnCommunicationDeviceChangedListener? = null

    private val audioRouteTimeout =
        Runnable {
            val pending = pendingAudioRouteResult ?: return@Runnable
            pendingAudioRouteResult = null
            pendingAudioRouteGeneration = null
            audioRouteRequestGeneration += 1
            pending.error(
                "HFP_ROUTE_TIMEOUT",
                "Android không mở được đường mic HFP/SCO trong thời gian cho phép.",
                null,
            )
            stopAudioRouteInternal()
            phase = "error"
            statusMessage =
                "Không mở được mic HFP/SCO. Hãy ngắt và kết nối lại tai nghe."
            emitStatus()
        }

    private val bluetoothReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context?,
                intent: Intent?,
            ) {
                if (Looper.myLooper() != routeThread.looper) {
                    routeHandler.post { if (!disposed) onReceive(context, intent) }
                    return
                }
                if (disposed) return
                when (intent?.action) {
                    BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED -> {
                        if (!isSelectedDeviceEvent(intent)) {
                            Log.d(TAG, "Ignoring HFP audio event from a non-selected device")
                            return
                        }
                        when (
                            intent.getIntExtra(
                                BluetoothProfile.EXTRA_STATE,
                                BluetoothHeadset.STATE_AUDIO_DISCONNECTED,
                            )
                        ) {
                            BluetoothHeadset.STATE_AUDIO_CONNECTED -> {
                                // API 31+ has one polling chain per request. A
                                // broadcast must not create a second completion.
                                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                                    completePendingAudioRoute()
                                }
                            }
                            BluetoothHeadset.STATE_AUDIO_DISCONNECTED -> {
                                if (pendingAudioRouteResult != null) {
                                    routeActive = false
                                    // A delayed disconnect from the previous SCO
                                    // turn can arrive after setCommunicationDevice.
                                    // Re-assert the current request after the old
                                    // teardown settles; merely ignoring this event
                                    // leaves Android on the handset until timeout.
                                    Log.i(TAG, "Ignoring SCO disconnect during route negotiation")
                                    pendingAudioRouteGeneration?.let(
                                        ::reassertPendingCommunicationRouteAfterDisconnect,
                                    )
                                } else if (routeActive || audioModeOwned) {
                                    // AudioManager can retain the old SCO device
                                    // while its service tears down the route.
                                    // Only a live SCO link makes this a stale
                                    // disconnect from an earlier generation.
                                    if (isSelectedHeadsetAudioConnected()) return
                                    recoverUnexpectedAudioRoute(
                                        "Selected H20 SCO audio disconnected",
                                    )
                                } else {
                                    refreshSelectedDeviceStatus()
                                }
                            }
                        }
                    }
                    BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED -> {
                        if (!isSelectedDeviceEvent(intent)) {
                            Log.d(TAG, "Ignoring HFP connection event from a non-selected device")
                            return
                        }
                        val selected = selectedDevice
                        if (
                            selected != null &&
                            !isHeadsetConnected(selected) &&
                            pendingAudioRouteResult == null &&
                            (routeActive || audioModeOwned)
                        ) {
                            interruptLostAudioRoute("Selected H20 profile disconnected")
                        } else {
                            refreshSelectedDeviceStatus()
                        }
                    }
                }
            }
        }

    private fun reassertPendingCommunicationRouteAfterDisconnect(generation: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        routeHandler.postDelayed(
            {
                if (
                    disposed ||
                    pendingAudioRouteResult == null ||
                    pendingAudioRouteGeneration != generation ||
                    audioRouteRequestGeneration != generation ||
                    isSelectedCommunicationRouteConfirmed()
                ) {
                    return@postDelayed
                }
                val communicationDevice = selectedDevice?.let(::selectedCommunicationDevice)
                    ?: return@postDelayed
                Log.i(
                    TAG,
                    "Re-asserting H20 communication route after delayed SCO disconnect " +
                        "generation=$generation",
                )
                runCatching {
                    audioManager.setCommunicationDevice(communicationDevice)
                }.onFailure { error ->
                    Log.w(TAG, "Unable to re-assert H20 communication route", error)
                }
            },
            AUDIO_ROUTE_REASSERT_DELAY_MS,
        )
    }

    /**
     * Some Android Bluetooth stacks briefly move an active communication track
     * back to the handset while SCO renegotiates. The H20 profile remains
     * connected and accepts setCommunicationDevice again within about a second.
     * Treat that window as recoverable so a transport wobble does not abort the
     * lesson or surface HFP_ROUTE_LOST to Flutter.
     */
    private fun recoverUnexpectedAudioRoute(reason: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            interruptLostAudioRoute(reason)
            return
        }
        if (pendingAudioRouteResult != null) {
            pendingAudioRouteGeneration?.let(
                ::reassertPendingCommunicationRouteAfterDisconnect,
            )
            return
        }
        if (!routeActive || !audioModeOwned) {
            refreshSelectedDeviceStatus()
            return
        }
        val selected = selectedDevice
        if (selected == null || !isHeadsetConnected(selected)) {
            interruptLostAudioRoute(reason)
            return
        }
        if (activeRouteRecovery != null) return

        val generation = audioRouteRequestGeneration
        activeRouteRecovery = HfpRouteReadiness(
            startedAtMs = SystemClock.elapsedRealtime(),
            timeoutMs = ACTIVE_ROUTE_RECOVERY_TIMEOUT_MS,
            settleMs = AUDIO_ROUTE_SETTLE_MS,
        )
        activeRouteRecoveryGeneration = generation
        activeRouteRecoveryReason = reason
        Log.w(TAG, "$reason; re-asserting the connected H20 route")
        pollActiveRouteRecovery(generation)
    }

    private fun pollActiveRouteRecovery(generation: Int) {
        val recovery = activeRouteRecovery ?: return
        if (
            disposed ||
            activeRouteRecoveryGeneration != generation ||
            audioRouteRequestGeneration != generation ||
            pendingAudioRouteResult != null ||
            !routeActive ||
            !audioModeOwned
        ) {
            clearActiveRouteRecovery()
            return
        }

        val confirmed = isSelectedCommunicationRouteConfirmed()
        when (recovery.poll(SystemClock.elapsedRealtime(), confirmed)) {
            HfpRouteReadiness.Result.READY -> {
                Log.i(TAG, "H20 communication route recovered generation=$generation")
                clearActiveRouteRecovery()
                return
            }
            HfpRouteReadiness.Result.TIMED_OUT -> {
                val lostReason = activeRouteRecoveryReason
                    ?: "Selected H20 communication route was lost"
                clearActiveRouteRecovery()
                interruptLostAudioRoute(lostReason)
                return
            }
            HfpRouteReadiness.Result.WAITING -> Unit
        }

        val selected = selectedDevice
        if (selected == null || !isHeadsetConnected(selected)) {
            val lostReason = activeRouteRecoveryReason
                ?: "Selected H20 profile disconnected during route recovery"
            clearActiveRouteRecovery()
            interruptLostAudioRoute(lostReason)
            return
        }
        selectedCommunicationDevice(selected)?.let { communicationDevice ->
            runCatching {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.setCommunicationDevice(communicationDevice)
            }.onFailure { error ->
                Log.w(TAG, "Unable to re-assert active H20 communication route", error)
            }
        }
        routeHandler.postDelayed(
            { pollActiveRouteRecovery(generation) },
            AUDIO_ROUTE_CONFIRM_INTERVAL_MS,
        )
    }

    private fun clearActiveRouteRecovery() {
        activeRouteRecovery = null
        activeRouteRecoveryGeneration = null
        activeRouteRecoveryReason = null
    }

    private fun isSelectedHeadsetAudioConnected(): Boolean {
        val selected = selectedDevice ?: return false
        if (!hasConnectPermission()) return false
        return try {
            headset?.isAudioConnected(selected) == true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun interruptLostAudioRoute(reason: String) {
        Log.w(TAG, reason)
        if (pendingAudioRouteResult != null) {
            // A real profile/service loss must still fail its pending request.
            val generation = audioRouteRequestGeneration
            host.runOnMain {
                if (disposed) return@runOnMain
                onUnexpectedRouteLoss()
                runOnRoute {
                    if (!disposed && audioRouteRequestGeneration == generation) {
                        stopAudioRouteInternal()
                    }
                }
            }
            return
        }
        val generation = ++audioRouteRequestGeneration
        routeReadiness = null
        routeActive = false
        phase = if (selectedDevice == null) "idle" else "ready"
        statusMessage = "Kết nối âm thanh H20 bị gián đoạn. Hãy thử lại."
        // Publish loss before querying or mutating AudioManager: some OEMs
        // block its calls until SCO teardown ends. Dart must pause its player
        // during that interval instead of continuing on the phone speaker.
        emitStatus()
        host.runOnMain {
            if (disposed) return@runOnMain
            onUnexpectedRouteLoss()
            // Stop the prompt on its own thread BEFORE releasing SCO. A queued
            // cleanup must never tear down a newer request's route.
            routeHandler.postDelayed(
                {
                    if (!disposed &&
                        audioRouteRequestGeneration == generation &&
                        pendingAudioRouteResult == null && !routeActive
                    ) {
                        stopAudioRouteInternal(invalidateRequest = false)
                    }
                },
                AUDIO_ROUTE_LOSS_CLEANUP_DELAY_MS,
            )
        }
    }

    private val profileListener =
        object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(
                profile: Int,
                proxy: BluetoothProfile,
            ) {
                if (Looper.myLooper() != routeThread.looper) {
                    routeHandler.post { onServiceConnected(profile, proxy) }
                    return
                }
                if (profile != BluetoothProfile.HEADSET || disposed) return
                headset = proxy as? BluetoothHeadset
                refreshSelectedDeviceStatus()
            }

            override fun onServiceDisconnected(profile: Int) {
                if (Looper.myLooper() != routeThread.looper) {
                    routeHandler.post { onServiceDisconnected(profile) }
                    return
                }
                if (disposed) return
                if (profile != BluetoothProfile.HEADSET) return
                headset = null
                if (routeActive || audioModeOwned) {
                    interruptLostAudioRoute("HFP profile service disconnected")
                }
                phase = "idle"
                statusMessage = "Dịch vụ HFP vừa ngắt kết nối."
                emitStatus()
            }
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val listener = AudioManager.OnCommunicationDeviceChangedListener {
                // Re-read the current device: this callback too can be queued
                // behind a newer route request.
                if (!disposed && pendingAudioRouteResult == null && routeActive &&
                    !isSelectedCommunicationRouteConfirmed()
                ) {
                    recoverUnexpectedAudioRoute(
                        "Selected H20 communication route was lost",
                    )
                }
            }
            communicationDeviceListener = listener
            routeHandler.post {
                if (!disposed) {
                    audioManager.addOnCommunicationDeviceChangedListener(routeExecutor, listener)
                }
            }
        }
        adapter?.let { bluetoothAdapter ->
            runCatching {
                bluetoothAdapter.getProfileProxy(
                    appContext,
                    profileListener,
                    BluetoothProfile.HEADSET,
                )
            }
        }
        val filter =
            IntentFilter().apply {
                addAction(BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(
                bluetoothReceiver,
                filter,
                // These protected system actions come from the privileged
                // Bluetooth process, not the system UID. NOT_EXPORTED drops
                // them on Android 13+, delaying detection until route fallback.
                Context.RECEIVER_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(bluetoothReceiver, filter)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (disposed || disposalRequested) {
            result.error("HFP_DISPOSED", "Kết nối HFP đã đóng.", null)
            return
        }
        // Results and status events share the main queue: otherwise a worker
        // reply could overtake an older queued "connecting" status in Dart.
        val reply = object : MethodChannel.Result {
            override fun success(value: Any?) = routeDispatch.complete {
                if (disposed || disposalRequested) {
                    result.error("HFP_DISPOSED", "Kết nối HFP đã đóng.", null)
                } else {
                    result.success(value)
                }
            }
            override fun error(code: String, message: String?, details: Any?) =
                routeDispatch.complete { result.error(code, message, details) }
            override fun notImplemented() = routeDispatch.complete { result.notImplemented() }
        }
        runOnRoute {
            // Flutter's MethodChannel catches synchronous handler exceptions;
            // preserve that error reply after moving the work off its thread.
            try {
                handleRouteMethodCall(call, reply)
            } catch (error: Exception) {
                Log.e(TAG, "HFP route operation failed: ${call.method}", error)
                if (pendingAudioRouteResult === reply) {
                    pendingAudioRouteResult = null
                    pendingAudioRouteGeneration = null
                    routeReadiness = null
                    audioRouteRequestGeneration += 1
                }
                routeActive = false
                phase = "error"
                statusMessage = "Không thể chuẩn bị âm thanh H20. Hãy thử lại."
                emitStatus()
                reply.error("HFP_ROUTE_FAILED", "Không thể chuẩn bị âm thanh H20. Hãy thử lại.", null)
            }
        }
    }

    private fun handleRouteMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("HFP_DISPOSED", "Kết nối HFP đã đóng.", null)
            return
        }
        when (call.method) {
            "initialize" -> initialize(result)
            "requestPermissions" -> requestPermissions(result)
            "findDevices" -> findDevices(result)
            "connect" -> connect(call, result)
            "disconnect" -> disconnect(result)
            "startAudioRoute" -> startAudioRoute(result)
            "stopAudioRoute" -> {
                stopAudioRouteInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (!hasBluetoothFeature()) {
            phase = "unsupported"
            statusMessage = "Điện thoại không hỗ trợ Bluetooth HFP."
        } else if (!hasConnectPermission()) {
            phase = "permissionRequired"
            statusMessage = "Cần quyền Thiết bị ở gần/Bluetooth."
        } else if (!isAdapterEnabled()) {
            phase = "error"
            statusMessage = "Hãy bật Bluetooth trên điện thoại."
        } else {
            refreshSelectedDeviceStatus()
        }
        result.success(snapshot())
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasConnectPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "BLUETOOTH_PERMISSION_PENDING",
                "Ứng dụng đang chờ cấp quyền Bluetooth.",
                null,
            )
            return
        }
        pendingPermissionResult = result
        host.runOnMain {
            if (disposed) return@runOnMain
            if (!host.requestPermissions(
                    arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                    PERMISSION_REQUEST_CODE,
                )
            ) {
                runOnRoute {
                    if (pendingPermissionResult === result) {
                        pendingPermissionResult = null
                        result.error(
                            "VISIBLE_ACTIVITY_REQUIRED",
                            "Hãy mở HOMI để cấp quyền Bluetooth trước khi tiếp tục.",
                            null,
                        )
                    }
                }
            }
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        if (Looper.myLooper() != routeThread.looper) {
            routeHandler.post { onRequestPermissionsResult(requestCode, grantResults) }
            return true
        }
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted) {
            phase = "idle"
            statusMessage = null
            emitStatus()
        } else {
            phase = "permissionRequired"
            statusMessage = "Cần quyền Thiết bị ở gần/Bluetooth để dùng HFP."
            emitStatus()
        }
        pending?.success(granted)
        return true
    }

    private fun findDevices(result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        phase = "scanning"
        statusMessage = "Đang tìm thiết bị HFP đã ghép đôi…"
        emitStatus()
        try {
            val connectedAddresses = connectedHeadsets().map { it.address }.toSet()
            val devices =
                adapter
                    ?.bondedDevices
                    .orEmpty()
                    .filter { device -> isLikelyHfp(device, connectedAddresses) }
                    .sortedWith(
                        compareByDescending<BluetoothDevice> {
                            connectedAddresses.contains(it.address)
                        }.thenBy { safeName(it).lowercase() },
                    )
                    .map { device ->
                        mapOf(
                            "id" to device.address,
                            "name" to safeName(device),
                            // The HEADSET profile proxy can arrive a little
                            // after Flutter startup. Android 12+ already exposes
                            // the live SCO communication device during that
                            // window, so use the same complete check as connect().
                            "isConnected" to isHeadsetConnected(device),
                        )
                    }
            refreshSelectedDeviceStatus()
            result.success(devices)
        } catch (error: SecurityException) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
        }
    }

    private fun connect(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!ensureBluetoothReady(result)) return
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        if (deviceId.isEmpty()) {
            fail(result, "HFP_DEVICE_REQUIRED", "Chưa chọn thiết bị HFP.")
            return
        }
        phase = "connecting"
        statusMessage = "Đang kiểm tra kết nối HFP…"
        emitStatus()
        try {
            val device = adapter?.bondedDevices?.firstOrNull { it.address == deviceId }
            if (device == null) {
                fail(
                    result,
                    "HFP_DEVICE_NOT_PAIRED",
                    "Thiết bị HFP chưa được ghép đôi với điện thoại.",
                )
                return
            }
            selectedDevice = device
            if (!isHeadsetConnected(device)) {
                phase = "idle"
                statusMessage =
                    "Hãy kết nối thiết bị trong Cài đặt Bluetooth, rồi quay lại bấm Tìm HFP."
                emitStatus()
                host.runOnMain {
                    if (!disposed) {
                        host.startVisibleActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    }
                }
                result.error("HFP_NOT_CONNECTED", statusMessage, null)
                return
            }
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
            Log.i(TAG, "H20 HFP profile selected and connected")
            emitStatus()
            result.success(snapshot())
        } catch (error: SecurityException) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        stopAudioRouteInternal()
        selectedDevice = null
        phase = "idle"
        statusMessage = null
        emitStatus()
        result.success(null)
    }

    private fun startAudioRoute(result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        if (pendingAudioRouteResult != null) {
            result.error(
                "HFP_ROUTE_PENDING",
                "Android đang mở đường mic HFP/SCO.",
                null,
            )
            return
        }
        val device = selectedDevice
        if (device == null || !isHeadsetConnected(device)) {
            fail(
                result,
                "HFP_NOT_CONNECTED",
                "Hãy kết nối thiết bị HFP trước khi bắt đầu nhận diện.",
            )
            return
        }

        // Other recording clients can restore their earlier audio mode while
        // Android still reports the selected SCO device. Reclaim communication
        // mode and reconfirm the route before reusing it in that case.
        if (
            routeActive &&
            audioManager.mode == AudioManager.MODE_IN_COMMUNICATION &&
            isSelectedCommunicationRouteConfirmed()
        ) {
            phase = "recording"
            statusMessage = "Đang dùng mic và loa H20 trên đường HFP/SCO hai chiều."
            val status = snapshot()
            emitStatus(status)
            result.success(status)
            return
        }

        clearActiveRouteRecovery()
        val generation = ++audioRouteRequestGeneration
        routeReadiness = HfpRouteReadiness(SystemClock.elapsedRealtime())
        Log.i(TAG, "Starting HFP route generation=$generation")

        // Keep the mode that existed before this bridge first took ownership.
        // SCO can disconnect independently and flip routeActive to false while
        // MODE_IN_COMMUNICATION remains set. Overwriting previousAudioMode on
        // the next retry would then make the communication stream permanent,
        // which produces inconsistent volume on later H20 playback.
        if (!audioModeOwned) {
            previousAudioMode = audioManager.mode
            audioModeOwned = true
        }
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                pendingAudioRouteResult = result
                pendingAudioRouteGeneration = generation
                routeActive = false
                phase = "connecting"
                statusMessage = "Đang xác nhận mic và loa H20 trên đường HFP/SCO…"
                emitStatus()
                requestSelectedCommunicationDevice(
                    generation = generation,
                    attemptsRemaining = AUDIO_ROUTE_CONFIRM_ATTEMPTS,
                )
            } else {
                pendingAudioRouteResult = result
                pendingAudioRouteGeneration = generation
                phase = "discovering"
                statusMessage = "Đang mở đường mic HFP/SCO…"
                emitStatus()
                @Suppress("DEPRECATION")
                audioManager.startBluetoothSco()
                @Suppress("DEPRECATION")
                run { audioManager.isBluetoothScoOn = true }
                routeHandler.postDelayed(audioRouteTimeout, 5000L)
            }
    }

    private fun requestSelectedCommunicationDevice(
        generation: Int,
        attemptsRemaining: Int,
    ) {
        if (
            pendingAudioRouteResult == null ||
            pendingAudioRouteGeneration != generation ||
            audioRouteRequestGeneration != generation ||
            disposed
        ) {
            return
        }
        val selected = selectedDevice
        val communicationDevice = selected?.let(::selectedCommunicationDevice)
        if (communicationDevice != null) {
            if (
                (audioManager.communicationDevice?.id == communicationDevice.id &&
                    isSelectedHeadsetAudioConnected()) ||
                audioManager.setCommunicationDevice(communicationDevice)
            ) {
                waitForSelectedCommunicationDevice(
                    generation = generation,
                    attemptsRemaining = AUDIO_ROUTE_CONFIRM_ATTEMPTS,
                )
                return
            }
        }
        if (attemptsRemaining <= 0) {
            failPendingAudioRoute(
                generation = generation,
                code = "HFP_ROUTE_FAILED",
                message =
                    "Android chưa tìm thấy đúng đường mic và loa H20. Hãy kết nối lại thiết bị rồi thử lại.",
            )
            return
        }
        routeHandler.postDelayed(
            {
                requestSelectedCommunicationDevice(
                    generation = generation,
                    attemptsRemaining = attemptsRemaining - 1,
                )
            },
            AUDIO_ROUTE_CONFIRM_INTERVAL_MS,
        )
    }

    private fun completePendingAudioRoute() {
        val pending = pendingAudioRouteResult ?: return
        val generation = pendingAudioRouteGeneration ?: audioRouteRequestGeneration
        if (generation != audioRouteRequestGeneration) return
        routeActive = true
        phase = "recording"
        statusMessage = "Đang dùng mic và loa H20 trên đường HFP/SCO hai chiều."
        Log.i(TAG, "H20 HFP/SCO route active")
        emitStatus()
        routeHandler.postDelayed(
            {
                if (
                    pendingAudioRouteResult === pending &&
                    pendingAudioRouteGeneration == generation &&
                    audioRouteRequestGeneration == generation &&
                    routeActive
                ) {
                    pendingAudioRouteResult = null
                    pendingAudioRouteGeneration = null
                    routeHandler.removeCallbacks(audioRouteTimeout)
                    pending.success(snapshot())
                }
            },
            AUDIO_ROUTE_SETTLE_MS,
        )
    }

    private fun waitForSelectedCommunicationDevice(
        generation: Int,
        attemptsRemaining: Int,
    ) {
        val pending = pendingAudioRouteResult ?: return
        if (
            disposed ||
            pendingAudioRouteGeneration != generation ||
            audioRouteRequestGeneration != generation
        ) {
            return
        }
        val activeDevice = confirmedSelectedCommunicationDevice()
        val readiness = routeReadiness ?: return
        when (readiness.poll(SystemClock.elapsedRealtime(), activeDevice != null)) {
        HfpRouteReadiness.Result.READY -> {
            routeActive = true
            phase = "recording"
            statusMessage = "Đang dùng mic và loa H20 trên đường HFP/SCO hai chiều."
            Log.i(
                TAG,
                "H20 HFP/SCO route confirmed: id=${activeDevice?.id}, " +
                    "name=${activeDevice?.productName}, generation=$generation",
            )
            val status = snapshot()
            emitStatus(status)
            pendingAudioRouteResult = null
            pendingAudioRouteGeneration = null
            routeReadiness = null
            pending.success(status)
            return
        }
        HfpRouteReadiness.Result.TIMED_OUT -> {
            failPendingAudioRoute(
                generation = generation,
                code = "HFP_ROUTE_TIMEOUT",
                message =
                    "Android chưa xác nhận được cả mic và loa H20 trên đường HFP/SCO.",
            )
            return
        }
        HfpRouteReadiness.Result.WAITING -> Unit
        }
        routeHandler.postDelayed(
            {
                waitForSelectedCommunicationDevice(
                    generation = generation,
                    attemptsRemaining = attemptsRemaining - 1,
                )
            },
            AUDIO_ROUTE_CONFIRM_INTERVAL_MS,
        )
    }

    private fun failPendingAudioRoute(
        generation: Int,
        code: String,
        message: String,
    ) {
        val pending = pendingAudioRouteResult ?: return
        if (
            pendingAudioRouteGeneration != generation ||
            audioRouteRequestGeneration != generation
        ) {
            return
        }
        pendingAudioRouteResult = null
        pendingAudioRouteGeneration = null
        audioRouteRequestGeneration += 1
        pending.error(code, message, null)
        stopAudioRouteInternal(invalidateRequest = false)
        phase = "error"
        statusMessage = message
        emitStatus()
    }

    private fun stopAudioRouteInternal(invalidateRequest: Boolean = true) {
        AudioDiagnostics.event("hfp.stop.begin", mapOf("generation" to audioRouteRequestGeneration))
        Log.i(TAG, "Stopping HFP route generation=$audioRouteRequestGeneration pending=${pendingAudioRouteResult != null}")
        routeReadiness = null
        clearActiveRouteRecovery()
        routeActive = false
        if (invalidateRequest) {
            audioRouteRequestGeneration += 1
        }
        pendingAudioRouteResult?.let { pending ->
            pendingAudioRouteResult = null
            pendingAudioRouteGeneration = null
            routeHandler.removeCallbacks(audioRouteTimeout)
            pending.error(
                "HFP_ROUTE_CANCELLED",
                "Đã dừng trước khi đường mic HFP/SCO sẵn sàng.",
                null,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            run { audioManager.isBluetoothScoOn = false }
        }
        if (audioModeOwned) {
            AudioDiagnostics.event("hfp.stop.restore_mode.begin")
            audioManager.mode = previousAudioMode
            audioModeOwned = false
            AudioDiagnostics.event("hfp.stop.restore_mode.end")
        }
        routeActive = false
        if (selectedDevice != null && isHeadsetConnected(selectedDevice!!)) {
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
        } else {
            phase = "idle"
            statusMessage = null
        }
        emitStatus()
        AudioDiagnostics.event("hfp.stop.completed", mapOf("generation" to audioRouteRequestGeneration))
    }

    private fun refreshSelectedDeviceStatus() {
        if (pendingAudioRouteResult != null) {
            phase = "connecting"
            statusMessage = "Đang xác nhận mic và loa H20 trên đường HFP/SCO…"
            emitStatus()
            return
        }
        val selected = selectedDevice
        if (
            routeActive &&
            selected != null &&
            isHeadsetConnected(selected) &&
            isSelectedCommunicationRouteConfirmed()
        ) {
            phase = "recording"
            statusMessage = "Đang dùng mic và loa H20 trên đường HFP/SCO hai chiều."
        } else if (selected != null && isHeadsetConnected(selected)) {
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
        } else {
            phase = "idle"
            if (selected != null) {
                statusMessage = "Thiết bị HFP chưa kết nối trong hệ thống."
            } else if (statusMessage?.startsWith("Đang tìm") == true) {
                statusMessage = null
            }
        }
        emitStatus()
    }

    private fun connectedHeadsets(): List<BluetoothDevice> =
        try {
            headset?.connectedDevices.orEmpty()
        } catch (_: SecurityException) {
            emptyList()
        }

    private fun isHeadsetConnected(device: BluetoothDevice): Boolean {
        if (!hasConnectPermission()) return false
        return try {
            val address = device.address
            val profileConnected = connectedHeadsets().any { it.address == address }
            if (profileConnected) return true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
            audioManager.availableCommunicationDevices.any {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                    addressesMatch(it.address, address)
            }
        } catch (_: SecurityException) {
            false
        }
    }

    private fun isLikelyHfp(
        device: BluetoothDevice,
        connectedAddresses: Set<String>,
    ): Boolean {
        if (!hasConnectPermission()) return false
        return try {
            if (connectedAddresses.contains(device.address)) return true
            val hasHfpUuid = device.uuids?.any { HFP_UUIDS.contains(it.uuid) } == true
            hasHfpUuid ||
                device.bluetoothClass?.majorDeviceClass ==
                android.bluetooth.BluetoothClass.Device.Major.AUDIO_VIDEO
        } catch (_: SecurityException) {
            // BLUETOOTH_CONNECT can be revoked while a scan result is being
            // evaluated. Treat the device as unavailable instead of crashing.
            false
        }
    }

    private fun safeName(device: BluetoothDevice): String =
        try {
            device.name?.trim().takeUnless { it.isNullOrEmpty() }
                ?: safeAddress(device)
                ?: "Thiết bị HFP"
        } catch (_: SecurityException) {
            "Thiết bị HFP"
        }

    private fun safeAddress(device: BluetoothDevice): String? =
        if (!hasConnectPermission()) {
            null
        } else {
            try {
                device.address
            } catch (_: SecurityException) {
                null
            }
        }

    private fun addressesMatch(
        first: String?,
        second: String?,
    ): Boolean =
        !first.isNullOrBlank() &&
            !second.isNullOrBlank() &&
            first.equals(second, ignoreCase = true)

    private fun isSelectedDeviceEvent(intent: Intent): Boolean {
        val selected = selectedDevice ?: return false
        val eventDevice = bluetoothDeviceExtra(intent)
        if (eventDevice != null) {
            val selectedAddress = safeAddress(selected)
            val eventAddress = safeAddress(eventDevice)
            if (addressesMatch(selectedAddress, eventAddress)) return true
            return normalizedDeviceName(safeName(selected)) ==
                normalizedDeviceName(safeName(eventDevice))
        }
        val connected = connectedHeadsets()
        return connected.size == 1 &&
            addressesMatch(safeAddress(connected.single()), safeAddress(selected))
    }

    private fun bluetoothDeviceExtra(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    private fun normalizedDeviceName(value: String?): String =
        value
            ?.lowercase()
            ?.replace(Regex("[^\\p{L}\\p{N}]+"), "")
            .orEmpty()

    private fun selectedCommunicationDevice(
        selected: BluetoothDevice,
    ): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val scoDevices = audioManager.availableCommunicationDevices.filter {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        val selectedAddress = safeAddress(selected)
        scoDevices.firstOrNull {
            addressesMatch(it.address, selectedAddress)
        }?.let { return it }

        val selectedName = normalizedDeviceName(safeName(selected))
        val nameMatches = scoDevices.filter {
            selectedName.isNotEmpty() &&
                normalizedDeviceName(it.productName?.toString()) == selectedName
        }
        if (nameMatches.size == 1) return nameMatches.single()

        // Some OEMs redact AudioDeviceInfo.address. A single SCO endpoint is
        // still deterministic only when the selected H20 is also the sole
        // connected HEADSET profile device.
        val connected = connectedHeadsets()
        if (
            scoDevices.size == 1 &&
            connected.size == 1 &&
            addressesMatch(safeAddress(connected.single()), selectedAddress)
        ) {
            return scoDevices.single()
        }
        return null
    }

    private fun confirmedSelectedCommunicationDevice(): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val selected = selectedDevice ?: return null
        // An OEM can retain the selected port while SCO is already closing.
        // Do not authorize playback until the headset reports a live audio link.
        if (!isSelectedHeadsetAudioConnected()) return null
        val expected = selectedCommunicationDevice(selected) ?: return null
        val active = audioManager.communicationDevice ?: return null
        return active.takeIf {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO && it.id == expected.id
        }
    }

    private fun isSelectedCommunicationRouteConfirmed(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            confirmedSelectedCommunicationDevice() != null
        } else {
            routeActive
        }

    private fun hasBluetoothFeature(): Boolean =
        appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            appContext.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun isAdapterEnabled(): Boolean =
        try {
            adapter?.isEnabled == true
        } catch (_: SecurityException) {
            false
        }

    private fun ensureBluetoothReady(result: MethodChannel.Result): Boolean {
        if (!hasBluetoothFeature() || adapter == null) {
            fail(result, "HFP_UNSUPPORTED", "Điện thoại không hỗ trợ Bluetooth HFP.")
            return false
        }
        if (!hasConnectPermission()) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
            return false
        }
        if (!isAdapterEnabled()) {
            fail(result, "BLUETOOTH_DISABLED", "Hãy bật Bluetooth trên điện thoại.")
            return false
        }
        return true
    }

    private fun fail(
        result: MethodChannel.Result,
        code: String,
        message: String,
    ) {
        phase = "error"
        statusMessage = message
        emitStatus()
        result.error(code, message, null)
    }

    private fun snapshot(): Map<String, Any?> {
        // Confirm once per snapshot, not once for status and twice again for
        // each endpoint name. This is a live query, never a cached route bypass.
        val communicationDevice = if (routeActive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            confirmedSelectedCommunicationDevice()
        } else null
        val confirmedRoute = routeActive &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || communicationDevice != null)
        return mapOf(
            "type" to "status",
            "phase" to phase,
            "deviceId" to selectedDevice?.let(::safeAddress),
            "deviceName" to selectedDevice?.let(::safeName),
            "message" to statusMessage,
            "sampleRate" to 16000,
            "routeActive" to confirmedRoute,
            "inputDeviceName" to if (confirmedRoute) {
                activeScoDeviceName(AudioManager.GET_DEVICES_INPUTS, communicationDevice)
            } else null,
            "outputDeviceName" to if (confirmedRoute) {
                activeScoDeviceName(AudioManager.GET_DEVICES_OUTPUTS, communicationDevice)
            } else null,
            "audioRoute" to if (confirmedRoute) "HFP/SCO two-way" else "system/default",
        )
    }

    private fun activeScoDeviceName(direction: Int, communicationDevice: AudioDeviceInfo?): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return communicationDevice?.productName?.toString()
                ?.trim()
                ?.takeUnless { it.isEmpty() }
                ?: selectedDevice?.let(::safeName)
        }
        val selected = selectedDevice ?: return null
        val selectedAddress = safeAddress(selected)
        val selectedName = normalizedDeviceName(safeName(selected))
        val scoDevices = audioManager.getDevices(direction).filter {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        val matching = scoDevices.firstOrNull {
            addressesMatch(it.address, selectedAddress)
        } ?: scoDevices.singleOrNull {
            selectedName.isNotEmpty() &&
                normalizedDeviceName(it.productName?.toString()) == selectedName
        } ?: scoDevices.singleOrNull()
        return matching
            ?.productName
            ?.toString()
            ?.trim()
            ?.takeUnless { it.isEmpty() }
            ?: safeName(selected)
    }

    private fun emitStatus(confirmedStatus: Map<String, Any?>? = null) {
        if (!disposed) {
            val sink = eventSink ?: return
            routeDispatch.publish({ confirmedStatus ?: snapshot() }) { status ->
                if (!disposed && eventSink === sink) sink.success(status)
            }
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
        runOnRoute {
            if (disposed) return@runOnRoute
            routeDispatch.publish(::snapshot) { status ->
                if (!disposed && eventSink === events) events?.success(status)
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun onBackgroundSessionStopped() {
        runOnRoute { if (!disposed) stopAudioRouteInternal() }
    }

    fun dispose() {
        if (disposed || disposalRequested) return
        disposalRequested = true
        // Channel registration belongs to Flutter's platform thread. Route
        // teardown stays on the serial worker, including blocking binder calls.
        host.runOnMain {
            methodChannel.setMethodCallHandler(null)
            eventChannel.setStreamHandler(null)
        }
        runOnRoute { disposeRoute() }
    }

    private fun runOnRoute(block: () -> Unit) {
        routeDispatch.run(block)
    }

    private fun disposeRoute() {
        if (disposed) return
        runCatching { stopAudioRouteInternal() }.onFailure { error ->
            Log.w(TAG, "Unable to finish HFP route teardown", error)
        }
        disposed = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            communicationDeviceListener?.let { listener ->
                runCatching { audioManager.removeOnCommunicationDeviceChangedListener(listener) }
            }
            communicationDeviceListener = null
        }
        pendingPermissionResult?.error(
            "HFP_DISPOSED",
            "Ứng dụng đã dừng trước khi nhận quyền Bluetooth.",
            null,
        )
        pendingPermissionResult = null
        routeHandler.removeCallbacks(audioRouteTimeout)
        runCatching { appContext.unregisterReceiver(bluetoothReceiver) }
        headset?.let { proxy ->
            runCatching { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, proxy) }
        }
        headset = null
        eventSink = null
        // Drain already queued channel calls so they receive HFP_DISPOSED;
        // quitSafely drops future timers without silently losing method replies.
        routeThread.quitSafely()
    }
}
