package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.util.Locale

@SuppressLint("MissingPermission")
class Aiv0BleControlBridge(
    private val host: HomiAndroidHost,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_aiv0_ble_control"
        private const val EVENT_CHANNEL = "ailingo_aiv0_ble_control/events"
        private const val PERMISSION_REQUEST_CODE = 7395
        private const val ENABLE_BLUETOOTH_REQUEST_CODE = 7396
        private const val MAX_RECONNECT_ATTEMPTS = 5
        private const val GATT_CONNECTION_TIMEOUT = 8
        private const val ADAPTER_ON_RECONNECT_DELAY_MS = 1_000L
        private const val DUPLICATE_WINDOW_MS = 750L
        private const val TAG = "Aiv0BleControl"
        private const val RUNTIME_PREFERENCES = "homi_android_runtime"
        private const val LAST_DEVICE_ID = "h20_ble_device_id"
        private const val LAST_DEVICE_NAME = "h20_ble_device_name"
        private const val MANUAL_DISCONNECT = "h20_ble_manual_disconnect"
        private const val MAX_BUFFERED_BUTTON_EVENTS = 32
    }

    private val methodChannel = MethodChannel(messenger, CONTROL_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val appContext = host.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter
    private val scanDevices = linkedMapOf<String, ScannedDevice>()
    private val classicDiscovery = HomiClassicDiscovery(appContext)
    private val runtimePreferences =
        appContext.getSharedPreferences(RUNTIME_PREFERENCES, Context.MODE_PRIVATE)
    private val bufferedButtonEvents = ArrayDeque<Map<String, Any?>>()
    private val mediaKeyObserver = H20MediaKeyObserver(appContext, ::emitButtonEvent)

    private var eventSink: EventChannel.EventSink? = null
    private var enableBluetoothResult: MethodChannel.Result? = null
    private var phase = "idle"
    private var message: String? = null
    private var deviceId: String? = null
    private var deviceName: String? = null
    private var writeMode: String? = null
    private var batteryPercent: Int? = null
    private var firmwareRevision: String? = null
    private var lastRawHex: String? = null
    private var packetCount = 0L
    private var invalidPacketCount = 0L
    private var duplicatePacketCount = 0L
    private var reconnectCount = 0L
    private var lastPacketAt = 0L

    private var permissionResult: MethodChannel.Result? = null
    private var scanResult: MethodChannel.Result? = null
    private var connectResult: MethodChannel.Result? = null
    private var bondResult: MethodChannel.Result? = null
    private var bondPoll: Runnable? = null
    private var pendingWriteResult: MethodChannel.Result? = null
    private var scanCallback: ScanCallback? = null
    private var scanTimeout: Runnable? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var buttonCharacteristic: BluetoothGattCharacteristic? = null
    private var stateCharacteristic: BluetoothGattCharacteristic? = null
    private var batteryCharacteristic: BluetoothGattCharacteristic? = null
    private var firmwareCharacteristic: BluetoothGattCharacteristic? = null
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private var reconnectRunnable: Runnable? = null
    private var lastDisconnectCode: String? = null
    private var lastDisconnectEpochMs: Long? = null
    private var disposed = false
    private val connectionTimeout = Runnable {
        if (phase == "connecting" || phase == "reconnecting") {
            failOrRetry(
                "Kết nối/đọc GATT của HM-D001 quá thời gian 15 giây.",
                GATT_CONNECTION_TIMEOUT,
            )
        }
    }
    private val adapterStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF ->
                    handleAdapterOff()
                BluetoothAdapter.STATE_TURNING_ON -> if (!disposed) emitStatus()
                BluetoothAdapter.STATE_ON -> handleAdapterOn()
            }
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Protected system broadcast sent by the Bluetooth process; see
            // the matching note in HfpAudioBridge.
            appContext.registerReceiver(adapterStateReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(adapterStateReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bleDiagnostic" -> {
                BleDiagnostics.event(appContext, "selection", call.arguments as? Map<String, Any?> ?: emptyMap())
                result.success(null)
            }
            "initialize" -> initialize(result)
            "hasPermissions" -> result.success(hasPermissions())
            "requestPermissions" -> requestPermissions(result)
            "bluetoothAdapterState" -> result.success(bluetoothAdapterState())
            "bluetoothPermissionRequiresSettings" -> result.success(permissionRequiresSettings())
            "requestEnableBluetooth" -> requestEnableBluetooth(result)
            "openBluetoothSettings" -> openBluetoothSettings(result)
            "openPermissionSettings" -> openPermissionSettings(result)
            "scan" -> scan(call, result)
            "scanClassic" -> {
                if (ensureBluetoothReady(result)) {
                    classicDiscovery.start(result, call.argument<Number>("timeoutMs")?.toLong() ?: 15_000L)
                }
            }
            "connect" -> connect(call, result)
            "requestDualModeBond" -> requestDualModeBond(call, result)
            "disconnect" -> disconnect(result)
            "cancelConnectionAttempt" -> {
                cancelConnectionAttempt(preserveConnected = true)
                result.success(snapshot())
            }
            "refreshBattery" -> refreshBattery(result)
            "sendAppState" -> sendAppState(call, result)
            "status" -> result.success(snapshot())
            "setControlContext" -> {
                mediaKeyObserver.setControlContext(
                    learningActive = call.argument<Boolean>("learningActive") == true,
                    diagnosticsActive = call.argument<Boolean>("diagnosticsActive") == true,
                )
                result.success(snapshot())
                emitStatus()
            }
            "dispose" -> {
                // The native bridge belongs to the process-scoped HOMI runtime,
                // not to an individual Dart controller. A screen/controller may
                // be disposed while the foreground service must keep H20 alive.
                // EventChannel.onCancel detaches the old Dart listener; a later
                // controller can subscribe again and receive the current state.
                eventSink = null
                mediaKeyObserver.setControlContext(false, false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(snapshot())
        while (events != null && bufferedButtonEvents.isNotEmpty()) {
            events.success(bufferedButtonEvents.removeFirst())
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        mediaKeyObserver.setControlContext(false, false)
    }

    fun observeMediaKey(key: KeyEvent) {
        // Activity remains non-consuming: phone volume/power behavior is untouched.
        mediaKeyObserver.observe(key, "activity")
    }

    fun setControlForeground(foreground: Boolean) {
        mediaKeyObserver.setForeground(foreground)
        emitStatus()
    }

    private fun initialize(result: MethodChannel.Result) {
        val adapterState = bluetoothAdapterState()
        phase = when {
            !appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) ->
                "disabled"
            adapter == null -> "disabled"
            else -> if (phase == "disabled") "idle" else phase
        }
        message = when {
            phase == "disabled" -> "Điện thoại không hỗ trợ Bluetooth Low Energy."
            adapterState == "unauthorized" -> "Cần cấp quyền Bluetooth trước."
            adapterState == "poweredOff" -> "Bluetooth đang tắt."
            else -> message
        }
        result.success(snapshot())
        emitStatus()
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions(): Boolean = requiredPermissions().all {
        appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun permissionRequiresSettings(): Boolean {
        if (hasPermissions()) return false
        val activity = host.currentActivity ?: return false
        return runtimePreferences.getBoolean("ble_permission_prompt_blocked", false) &&
            requiredPermissions().any {
                appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED &&
                    !activity.shouldShowRequestPermissionRationale(it)
            }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("PERMISSION_IN_PROGRESS", "Đang chờ cấp quyền Bluetooth.", null)
            return
        }
        permissionResult = result
        Log.i(TAG, "Requesting Bluetooth permission; activity=${host.currentActivity != null}")
        message = "Cần quyền Thiết bị ở gần/Bluetooth để tìm HM-D001."
        emitStatus()
        if (!host.requestPermissions(requiredPermissions(), PERMISSION_REQUEST_CODE)) {
            permissionResult = null
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để cấp quyền Bluetooth trước khi tiếp tục.",
                null,
            )
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        // An empty result may be an interrupted/concurrent request, not a
        // permanent denial. Only classify a completed system response.
        if (grantResults.isNotEmpty()) {
            val activity = host.currentActivity
            val blocked = !granted && activity != null && requiredPermissions().any {
                appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED &&
                    !activity.shouldShowRequestPermissionRationale(it)
            }
            runtimePreferences.edit().putBoolean("ble_permission_prompt_blocked", blocked).apply()
        }
        Log.i(TAG, "Bluetooth permission result: granted=$granted settingsRequired=${permissionRequiresSettings()}")
        permissionResult?.success(granted)
        permissionResult = null
        phase = if (granted) "idle" else "error"
        message = if (granted) null else "Quyền Bluetooth đã bị từ chối."
        emitStatus()
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != ENABLE_BLUETOOTH_REQUEST_CODE) return false
        // A late Activity result must not reset a newer GATT connection, or
        // revive a bridge that has already completed/disposed this request.
        val pending = enableBluetoothResult ?: return true
        enableBluetoothResult = null
        val adapterState = bluetoothAdapterState()
        val enabled = resultCode == Activity.RESULT_OK && adapterState == "poweredOn"
        if (phase == "idle" || phase == "error" || phase == "disabled") {
            phase = if (enabled) "idle" else "error"
            message = when {
                enabled -> null
                adapterState == "unauthorized" -> "Cần cấp quyền Bluetooth trước."
                adapterState == "unsupported" -> "Điện thoại không hỗ trợ BLE."
                else -> "Bluetooth vẫn đang tắt."
            }
        }
        emitStatus()
        pending.success(enabled)
        return true
    }

    private fun bluetoothAdapterState(): String {
        val bluetoothAdapter = adapter
        if (bluetoothAdapter == null ||
            !appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        ) return "unsupported"
        if (!hasPermissions()) return "unauthorized"
        return try {
            when (bluetoothAdapter.state) {
                BluetoothAdapter.STATE_ON -> "poweredOn"
                BluetoothAdapter.STATE_OFF -> "poweredOff"
                BluetoothAdapter.STATE_TURNING_ON, BluetoothAdapter.STATE_TURNING_OFF -> "resetting"
                else -> "unknown"
            }
        } catch (_: SecurityException) {
            // Permissions can be revoked between the check and binder call.
            "unauthorized"
        }
    }

    private fun requestEnableBluetooth(result: MethodChannel.Result) {
        val adapterState = bluetoothAdapterState()
        Log.i(TAG, "Request enable Bluetooth: state=$adapterState activity=${host.currentActivity != null}")
        if (adapterState == "unsupported") {
            result.error("BLE_UNSUPPORTED", "Điện thoại không hỗ trợ BLE.", null)
            return
        }
        if (adapterState == "unauthorized") {
            result.error("PERMISSION_REQUIRED", "Cần cấp quyền Bluetooth trước.", null)
            return
        }
        if (adapterState == "poweredOn") {
            result.success(true)
            return
        }
        if (enableBluetoothResult != null) {
            result.error(
                "ENABLE_BLUETOOTH_IN_PROGRESS",
                "Đang chờ phụ huynh bật Bluetooth.",
                null,
            )
            return
        }
        val activity = host.currentActivity
        if (activity == null) {
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để bật Bluetooth trước khi tiếp tục.",
                null,
            )
            return
        }
        enableBluetoothResult = result
        try {
            activity.startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                ENABLE_BLUETOOTH_REQUEST_CODE,
            )
        } catch (_: ActivityNotFoundException) {
            enableBluetoothResult = null
            result.error(
                "ENABLE_BLUETOOTH_UNAVAILABLE",
                "Máy không thể mở yêu cầu bật Bluetooth.",
                null,
            )
        } catch (error: SecurityException) {
            enableBluetoothResult = null
            Log.w(TAG, "System Bluetooth enable dialog rejected", error)
            result.error("PERMISSION_REQUIRED", "Cần cấp quyền Bluetooth trước.", null)
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        val opened = host.startVisibleActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
        if (opened) {
            result.success(true)
        } else {
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để đi tới Cài đặt Bluetooth.",
                null,
            )
        }
    }

    private fun openPermissionSettings(result: MethodChannel.Result) {
        // This destination repairs an app permission that Android can no
        // longer prompt for. Radio power uses ACTION_REQUEST_ENABLE instead.
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", appContext.packageName, null),
        )
        val opened = try {
            host.startVisibleActivity(intent)
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
        result.success(opened)
    }

    private fun ensureBluetoothReady(result: MethodChannel.Result): Boolean {
        if (adapter == null || !appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.error("BLE_UNSUPPORTED", "Điện thoại không hỗ trợ BLE.", null)
            return false
        }
        if (!hasPermissions()) {
            result.error("PERMISSION_REQUIRED", "Cần cấp quyền Bluetooth trước.", null)
            return false
        }
        if (bluetoothAdapterState() != "poweredOn") {
            result.error("BLUETOOTH_DISABLED", "Bluetooth đang tắt.", null)
            return false
        }
        return true
    }

    private fun scan(call: MethodCall, result: MethodChannel.Result) {
        BleDiagnostics.event(appContext, "scan.request", mapOf("timeoutMs" to call.argument<Number>("timeoutMs"), "foreground" to (call.argument<Boolean>("foreground") == true), "permissions" to hasPermissions(), "adapter" to bluetoothAdapterState()))
        if (!ensureBluetoothReady(result)) return
        if (scanResult != null) {
            result.error("SCAN_IN_PROGRESS", "Đang quét thiết bị Bluetooth.", null)
            return
        }
        stopScan(complete = true)
        scanDevices.clear()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                if (scanCallback !== this) return
                addScanResult(scanResult)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                if (scanCallback !== this) return
                results.forEach(::addScanResult)
            }

            override fun onScanFailed(errorCode: Int) {
                if (scanCallback !== this) return
                scanTimeout?.let(mainHandler::removeCallbacks)
                scanTimeout = null
                BleDiagnostics.event(appContext, "scan.failed", mapOf("code" to errorCode))
                val pending = this@Aiv0BleControlBridge.scanResult
                this@Aiv0BleControlBridge.scanResult = null
                scanCallback = null
                phase = "error"
                message = "Không quét được Bluetooth (mã $errorCode)."
                emitStatus()
                pending?.error("BLE_SCAN_FAILED", message, errorCode)
            }
        }
        scanCallback = callback
        scanResult = result
        phase = "scanning"
        message = null
        emitStatus()
        try {
            if (call.argument<Boolean>("foreground") == true) {
                val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .setReportDelay(0L)
                    .build()
                adapter!!.bluetoothLeScanner.startScan(null, settings, callback)
            } else {
                adapter!!.bluetoothLeScanner.startScan(callback)
            }
        } catch (error: Throwable) {
            scanResult = null
            scanCallback = null
            phase = "error"
            message = "Không thể bắt đầu quét: ${error.message}"
            emitStatus()
            result.error("BLE_SCAN_FAILED", message, null)
            return
        }
        val timeout = (call.argument<Number>("timeoutMs")?.toLong() ?: 8_000L)
            .coerceIn(2_000L, 15_000L)
        val timeoutTask = Runnable {
            if (scanCallback === callback) stopScan(complete = true)
        }
        scanTimeout = timeoutTask
        mainHandler.postDelayed(timeoutTask, timeout)
    }

    private fun addScanResult(result: ScanResult) {
        val device = result.device ?: return
        val id = device.address ?: return
        val advertisedName = result.scanRecord?.deviceName?.trim()?.takeIf { it.isNotEmpty() }
        val name = advertisedName ?: runCatching { device.name }.getOrNull().orEmpty().trim()
        val advertisesControlService = result.scanRecord?.serviceUuids?.any {
            it.uuid == Aiv0BleProtocol.controlServiceUuid
        } == true
        val normalizedName = name.lowercase(Locale.ROOT)
        val likely = advertisesControlService ||
            normalizedName.contains("h20") ||
            normalizedName.contains("aiv0") ||
            normalizedName.contains("innotrik") ||
            normalizedName == "hm-d001"
        val previous = scanDevices[id]
        if (previous == null || (name.isNotEmpty() && previous.name != name) ||
            (advertisesControlService && !previous.advertisesControlService)) {
            BleDiagnostics.event(appContext, "scan.device", mapOf("id" to id, "name" to name, "advertisedName" to advertisedName, "rssi" to result.rssi, "uuids" to result.scanRecord?.serviceUuids?.map { it.toString() }, "connectable" to if (Build.VERSION.SDK_INT >= 26) result.isConnectable else null, "likely" to likely, "controlService" to advertisesControlService))
        }
        // Name/service can arrive in a weaker scan-response packet. Retain
        // identity metadata across packets independently of the best RSSI.
        scanDevices[id] = ScannedDevice(
            id = id,
            name = name.takeIf { it.isNotEmpty() } ?: previous?.name.orEmpty(),
            rssi = maxOf(result.rssi, previous?.rssi ?: Int.MIN_VALUE),
            likely = likely || previous?.likely == true,
            advertisesControlService = advertisesControlService || previous?.advertisesControlService == true,
        )
    }

    private fun stopScan(complete: Boolean) {
        scanTimeout?.let(mainHandler::removeCallbacks)
        scanTimeout = null
        scanCallback?.let { callback ->
            runCatching { adapter?.bluetoothLeScanner?.stopScan(callback) }
        }
        scanCallback = null
        val pending = scanResult
        scanResult = null
        if (complete && pending != null) {
            BleDiagnostics.event(appContext, "scan.complete", mapOf("count" to scanDevices.size, "devices" to scanDevices.values.map { it.toMap() }))
            val devices = scanDevices.values.sortedWith(
                compareByDescending<ScannedDevice> { it.likely }
                    .thenByDescending { it.rssi },
            )
            phase = if (stateCharacteristic != null) "connected" else "idle"
            message = if (devices.isEmpty()) "Không tìm thấy HM-D001/AIV0." else null
            emitStatus()
            pending.success(devices.map { it.toMap() })
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        val requestedId = call.argument<String>("deviceId")?.trim().orEmpty()
        if (requestedId.isEmpty()) {
            result.error("DEVICE_REQUIRED", "Thiếu địa chỉ thiết bị BLE.", null)
            return
        }
        if (connectResult != null) {
            result.error("CONNECT_IN_PROGRESS", "Đang kết nối BLE.", null)
            return
        }
        stopScan(complete = true)
        shouldReconnect = false
        cancelPendingReconnect()
        closeGatt()
        val device = runCatching { adapter!!.getRemoteDevice(requestedId) }.getOrNull()
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Không tìm thấy thiết bị $requestedId.", null)
            return
        }
        deviceId = requestedId
        runtimePreferences.edit().putBoolean(MANUAL_DISCONNECT, false).apply()
        deviceName = runCatching { device.name }.getOrNull()?.trim()?.takeIf { it.isNotEmpty() }
            ?: scanDevices[requestedId]?.name
            ?: ""
        shouldReconnect = true
        reconnectAttempts = 0
        connectResult = result
        phase = "connecting"
        message = "Đang xác nhận BLE Control 9E3B0001…"
        emitStatus()
        openGatt(device)
    }

    private fun requestDualModeBond(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        // Discovery must have stopped before bonding/connecting the radio.
        runCatching { adapter?.cancelDiscovery() }
        if (bondResult != null) {
            result.error("BOND_IN_PROGRESS", "Đang chờ ghép đôi H20.", null)
            return
        }
        val id = call.argument<String>("deviceId")?.trim().orEmpty()
        val device = runCatching { adapter?.getRemoteDevice(id) }.getOrNull()
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Không tìm thấy thiết bị H20 để ghép đôi.", null)
            return
        }
        val initialState = runCatching { device.bondState }.getOrNull()
        BleDiagnostics.event(appContext, "bond.request", mapOf("id" to id, "type" to device.type, "state" to initialState))
        if (initialState == BluetoothDevice.BOND_BONDED) {
            BleDiagnostics.event(appContext, "bond.complete", mapOf("id" to id, "bonded" to true, "alreadyPaired" to true))
            result.success(true)
            return
        }
        val started = initialState == BluetoothDevice.BOND_BONDING ||
            runCatching { device.createBond() }.getOrDefault(false)
        BleDiagnostics.event(appContext, "bond.started", mapOf("id" to id, "started" to started))
        if (!started) {
            result.success(false)
            return
        }

        bondResult = result
        val deadline = SystemClock.elapsedRealtime() + 25_000L
        var sawBonding = initialState == BluetoothDevice.BOND_BONDING
        val poll = object : Runnable {
            override fun run() {
                if (bondResult !== result) return
                val state = runCatching { device.bondState }.getOrNull()
                when {
                    state == BluetoothDevice.BOND_BONDED -> finishBond(true)
                    sawBonding && state == BluetoothDevice.BOND_NONE -> finishBond(false)
                    SystemClock.elapsedRealtime() >= deadline -> finishBond(false)
                    else -> {
                        if (state == BluetoothDevice.BOND_BONDING) sawBonding = true
                        mainHandler.postDelayed(this, 250L)
                    }
                }
            }
        }
        bondPoll = poll
        mainHandler.postDelayed(poll, 250L)
    }

    private fun finishBond(bonded: Boolean) {
        bondPoll?.let(mainHandler::removeCallbacks)
        bondPoll = null
        val pending = bondResult
        bondResult = null
        if (pending != null) BleDiagnostics.event(appContext, "bond.complete", mapOf("bonded" to bonded))
        pending?.success(bonded)
    }

    private fun openGatt(device: BluetoothDevice) {
        BleDiagnostics.event(appContext, "gatt.open", mapOf("id" to device.address, "name" to device.name))
        cancelPendingReconnect()
        mainHandler.removeCallbacks(connectionTimeout)
        val opened = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(appContext, false, gattCallback)
            }
        }.getOrElse { error ->
            failConnection("Không thể mở GATT HM-D001: ${error.message}")
            return
        }
        bluetoothGatt = opened
        mainHandler.postDelayed(connectionTimeout, 15_000L)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            BleDiagnostics.event(appContext, "gatt.state", mapOf("id" to gatt.device.address, "status" to status, "state" to newState))
            mainHandler.post {
                if (gatt !== bluetoothGatt) {
                    // A cancelled session can deliver its disconnect after a new
                    // GATT is opened. It must not replace or close the new link.
                    runCatching { gatt.close() }
                    return@post
                }
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        // Do not publish a stale value from the previous GATT
                        // session before this peripheral has been read.
                        batteryPercent = null
                        // An automatic recovery stays "reconnecting" so a
                        // stalled discovery takes the next backoff step.
                        if (phase != "reconnecting") phase = "connecting"
                        message = "Đang đọc dịch vụ BLE Control…"
                        emitStatus()
                        if (!gatt.discoverServices()) {
                            failOrRetry(
                                "Không thể bắt đầu đọc GATT services.",
                                BluetoothGatt.GATT_FAILURE,
                            )
                        }
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> handleDisconnected(gatt, status)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            BleDiagnostics.event(appContext, "gatt.services", mapOf("status" to status, "services" to gatt.services.map { service -> mapOf("uuid" to service.uuid.toString(), "characteristics" to service.characteristics.map { mapOf("uuid" to it.uuid.toString(), "properties" to it.properties) }) }))
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failOrRetry("Không đọc được GATT services (mã $status).", status)
                    return@post
                }
                val service = gatt.getService(Aiv0BleProtocol.controlServiceUuid)
                val button = service?.getCharacteristic(Aiv0BleProtocol.buttonEventUuid)
                val state = service?.getCharacteristic(Aiv0BleProtocol.appStateUuid)
                if (service == null || button == null || state == null) {
                    failConnection(
                        "Thiết bị không có đủ 9E3B0001/0002/0003. V1 không dùng FF12/FF13/FF14.",
                    )
                    return@post
                }
                val supportsIndicate =
                    button.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
                if (!supportsIndicate) {
                    failConnection("9E3B0002 chưa hỗ trợ Indicate.")
                    return@post
                }
                val supportsWrite =
                    state.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
                val supportsWriteWithoutResponse =
                    state.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
                if (!supportsWrite && !supportsWriteWithoutResponse) {
                    failConnection("9E3B0003 không có thuộc tính ghi.")
                    return@post
                }
                writeMode = if (supportsWrite) "withResponse" else "withoutResponse"
                Log.i(
                    TAG,
                    "GATT verified: service=9E3B0001 button=indicate state=$writeMode",
                )
                buttonCharacteristic = button
                stateCharacteristic = state
                batteryCharacteristic = gatt
                    .getService(Aiv0BleProtocol.batteryServiceUuid)
                    ?.getCharacteristic(Aiv0BleProtocol.batteryLevelUuid)
                firmwareCharacteristic = gatt
                    .getService(Aiv0BleProtocol.deviceInformationServiceUuid)
                    ?.getCharacteristic(Aiv0BleProtocol.firmwareRevisionUuid)

                if (!gatt.setCharacteristicNotification(button, true)) {
                    failConnection("Không thể đăng ký Indicate 9E3B0002.")
                    return@post
                }
                val descriptor = button.getDescriptor(Aiv0BleProtocol.clientCharacteristicConfigUuid)
                if (descriptor == null) {
                    failConnection("9E3B0002 thiếu CCCD 2902.")
                    return@post
                }
                val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_INDICATION_VALUE,
                    ) == android.bluetooth.BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
                if (!started) failConnection("Không thể bật Indicate 9E3B0002.")
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                if (descriptor.uuid != Aiv0BleProtocol.clientCharacteristicConfigUuid) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failOrRetry("Không bật được Indicate 9E3B0002 (mã $status).", status)
                    return@post
                }
                phase = "connected"
                reconnectAttempts = 0
                mainHandler.removeCallbacks(connectionTimeout)
                runtimePreferences.edit()
                    .putString(LAST_DEVICE_ID, deviceId)
                    .putString(LAST_DEVICE_NAME, deviceName)
                    .apply()
                message = if (writeMode == "withoutResponse") {
                    "Đã kết nối. ODM cần bổ sung Write with response cho 9E3B0003."
                } else {
                    "Đã kết nối BLE Control AIV0."
                }
                connectResult?.success(snapshot())
                connectResult = null
                emitStatus()
                readOptionalCharacteristics(gatt)
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            handleCharacteristicChanged(gatt, characteristic.uuid, characteristic.value ?: byteArrayOf())
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handleCharacteristicChanged(gatt, characteristic.uuid, value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            @Suppress("DEPRECATION")
            handleCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            handleCharacteristicRead(gatt, characteristic, value, status)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid != Aiv0BleProtocol.appStateUuid) return
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                val pending = pendingWriteResult
                pendingWriteResult = null
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    pending?.success(null)
                } else {
                    pending?.error("BLE_WRITE_FAILED", "Ghi APP State thất bại (mã $status).", null)
                }
            }
        }
    }

    private fun handleCharacteristicChanged(gatt: BluetoothGatt, uuid: java.util.UUID, value: ByteArray) {
        if (uuid == Aiv0BleProtocol.batteryLevelUuid) {
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                batteryPercent = value.firstOrNull()?.toInt()?.and(0xFF)?.coerceIn(0, 100)
                emitStatus()
            }
            return
        }
        if (uuid != Aiv0BleProtocol.buttonEventUuid) return
        mainHandler.post {
            if (gatt !== bluetoothGatt) return@post
            packetCount += 1
            val hex = value.toHex()
            val now = android.os.SystemClock.elapsedRealtime()
            val receivedAtEpochMs = System.currentTimeMillis()
            val duplicate = hex == lastRawHex && now - lastPacketAt <= DUPLICATE_WINDOW_MS
            if (duplicate) duplicatePacketCount += 1
            if (value.size != 12) invalidPacketCount += 1
            lastRawHex = hex
            lastPacketAt = now
            H20ControlObservation.batteryPercent(value)?.let { batteryPercent = it }
            Log.i(
                TAG,
                "Button Event device=$deviceId len=${value.size} duplicate=$duplicate raw=$hex",
            )
            if (!duplicate && isObservedH20MainPacket(value)) {
                BackgroundLearningService.notePhysicalMain()
            }
            emitStatus()
            emitButtonEvent(
                H20ControlObservation.bleMetadata(value) + mapOf(
                    "type" to "button",
                    "deviceId" to deviceId,
                    "bytes" to value.map { it.toInt() and 0xFF },
                    "duplicate" to duplicate,
                    "receivedAtEpochMs" to receivedAtEpochMs,
                ),
            )
        }
    }

    private fun readOptionalCharacteristics(gatt: BluetoothGatt) {
        val battery = batteryCharacteristic
        if (battery != null && gatt.readCharacteristic(battery)) return
        val firmware = firmwareCharacteristic
        if (firmware != null) gatt.readCharacteristic(firmware)
    }

    private fun refreshBattery(result: MethodChannel.Result) {
        val gatt = bluetoothGatt
        val battery = batteryCharacteristic
        // APP State drives MAIN feedback and always wins over telemetry. If a
        // write is active, skip this minute's optional read and try next time.
        if (phase != "connected" || gatt == null || battery == null || pendingWriteResult != null) {
            result.success(false)
            return
        }
        result.success(runCatching { gatt.readCharacteristic(battery) }.getOrDefault(false))
    }

    private fun handleCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        mainHandler.post {
            if (gatt !== bluetoothGatt) return@post
            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (characteristic.uuid) {
                    Aiv0BleProtocol.batteryLevelUuid -> {
                        batteryPercent = value.firstOrNull()?.toInt()?.and(0xFF)?.coerceIn(0, 100)
                    }
                    Aiv0BleProtocol.firmwareRevisionUuid -> {
                        firmwareRevision = String(value, StandardCharsets.UTF_8).trim().ifBlank { null }
                    }
                }
                emitStatus()
            }
            if (characteristic.uuid == Aiv0BleProtocol.batteryLevelUuid) {
                firmwareCharacteristic?.let { gatt.readCharacteristic(it) }
            }
        }
    }

    private fun sendAppState(call: MethodCall, result: MethodChannel.Result) {
        val gatt = bluetoothGatt
        val characteristic = stateCharacteristic
        if (phase != "connected" || gatt == null || characteristic == null) {
            result.error("NOT_CONNECTED", "BLE Control AIV0 chưa kết nối.", null)
            return
        }
        val values = call.argument<List<Number>>("bytes")
        val bytes = values?.map { (it.toInt() and 0xFF).toByte() }?.toByteArray()
        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_PACKET", "APP State rỗng.", null)
            return
        }
        val withResponse =
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        characteristic.writeType = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, bytes, characteristic.writeType) ==
                android.bluetooth.BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = bytes
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (!started) {
            result.error("BLE_WRITE_FAILED", "Không thể bắt đầu ghi APP State.", null)
            return
        }
        Log.i(TAG, "APP State write mode=$writeMode raw=${bytes.toHex()}")
        if (withResponse) {
            pendingWriteResult?.error("BLE_WRITE_REPLACED", "APP State mới đã thay thế gói cũ.", null)
            pendingWriteResult = result
        } else {
            result.success(null)
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        runtimePreferences.edit().putBoolean(MANUAL_DISCONNECT, true).apply()
        cancelConnectionAttempt(preserveConnected = false)
        result.success(null)
    }

    private fun cancelConnectionAttempt(preserveConnected: Boolean) {
        val keepLink = preserveConnected && bluetoothGatt != null &&
            buttonCharacteristic != null && stateCharacteristic != null && connectResult == null
        stopScan(complete = true)
        classicDiscovery.cancel()
        finishBond(false)
        if (keepLink) {
            phase = "connected"
            message = null
            emitStatus()
            return
        }
        shouldReconnect = false
        reconnectAttempts = 0
        cancelPendingReconnect()
        mainHandler.removeCallbacks(connectionTimeout)
        connectResult?.error("CONNECT_CANCELLED", "Đã hủy kết nối.", null)
        connectResult = null
        pendingWriteResult?.error("CONNECT_CANCELLED", "Đã hủy kết nối.", null)
        pendingWriteResult = null
        closeGatt()
        phase = "idle"
        message = "Đã ngắt BLE Control AIV0."
        emitStatus()
    }

    private fun handleDisconnected(gatt: BluetoothGatt, status: Int) {
        if (gatt !== bluetoothGatt) return
        mainHandler.removeCallbacks(connectionTimeout)
        bluetoothGatt = null
        runCatching { gatt.close() }
        clearCharacteristics()
        continueAfterLinkLoss(status)
    }

    private fun continueAfterLinkLoss(status: Int) {
        lastDisconnectCode = status.toString()
        lastDisconnectEpochMs = System.currentTimeMillis()
        if (!shouldReconnect || disposed) {
            phase = "idle"
            message = "BLE Control đã ngắt kết nối."
            emitStatus()
            return
        }
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            phase = "error"
            message = "Không thể tự kết nối lại HM-D001 sau $MAX_RECONNECT_ATTEMPTS lần."
            connectResult?.error("RECONNECT_FAILED", message, status)
            connectResult = null
            emitStatus()
            return
        }
        reconnectAttempts += 1
        reconnectCount += 1
        phase = "reconnecting"
        message = "Đang kết nối lại HM-D001 ($reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)…"
        Log.w(TAG, "Reconnect $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS status=$status")
        emitStatus()
        scheduleReconnect((1_000L shl (reconnectAttempts - 1)).coerceAtMost(8_000L))
    }

    private fun scheduleReconnect(delay: Long) {
        val expectedId = deviceId
        val retry = Runnable {
            reconnectRunnable = null
            if (!shouldReconnect || disposed || phase != "reconnecting" ||
                deviceId != expectedId || bluetoothGatt != null
            ) return@Runnable
            val id = expectedId ?: return@Runnable
            val device = runCatching { adapter?.getRemoteDevice(id) }.getOrNull()
            if (device == null) {
                phase = "error"
                message = "Không còn tìm thấy HM-D001 đã ghép nối."
                emitStatus()
            } else {
                openGatt(device)
            }
        }
        reconnectRunnable = retry
        mainHandler.postDelayed(retry, delay)
    }

    /**
     * Bluetooth switched off: a GATT opened now can only time out, and some
     * stacks never report the disconnect of the live link. Drop everything
     * but the intent to reconnect, which [handleAdapterOn] resumes.
     */
    private fun handleAdapterOff() {
        if (disposed || phase == "disabled") return
        mainHandler.removeCallbacks(connectionTimeout)
        cancelPendingReconnect()
        stopScan(complete = true)
        classicDiscovery.cancel()
        connectResult?.error("BLUETOOTH_DISABLED", "Bluetooth đang tắt.", null)
        connectResult = null
        pendingWriteResult?.error("BLUETOOTH_DISABLED", "Bluetooth đang tắt.", null)
        pendingWriteResult = null
        finishBond(false)
        closeGatt()
        reconnectAttempts = 0
        phase = "idle"
        message = "Bluetooth đang tắt."
        emitStatus()
    }

    private fun handleAdapterOn() {
        if (disposed) return
        // First setup has no saved control device/reconnect intent yet. Still
        // notify Flutter so the power UI reads the now-ready radio state.
        if (!shouldReconnect || bluetoothGatt != null ||
            phase == "connecting" || phase == "reconnecting" ||
            !hasPermissions() || deviceId == null
        ) {
            if (phase == "idle") message = null
            emitStatus()
            return
        }
        Log.i(TAG, "Bluetooth is back on; reopening $deviceName")
        reconnectAttempts = 0
        phase = "reconnecting"
        message = "Đang khôi phục kết nối HM-D001…"
        emitStatus()
        scheduleReconnect(ADAPTER_ON_RECONNECT_DELAY_MS)
    }

    private fun cancelPendingReconnect() {
        reconnectRunnable?.let(mainHandler::removeCallbacks)
        reconnectRunnable = null
    }

    /**
     * A GATT step that failed while recovering automatically (link loss,
     * Bluetooth switched back on, background session) takes the next backoff
     * step: right after an adapter toggle the link can come up while service
     * discovery never answers. A connect requested by Dart reports the failure.
     */
    private fun failOrRetry(reason: String, status: Int) {
        if (phase == "reconnecting" && shouldReconnect) {
            closeGatt()
            continueAfterLinkLoss(status)
        } else {
            failConnection(reason, if (status == GATT_CONNECTION_TIMEOUT) "BLE_CONNECTION_TIMEOUT" else "AIV0_PROTOCOL_MISMATCH")
        }
    }

    private fun failConnection(reason: String, code: String = "AIV0_PROTOCOL_MISMATCH") {
        BleDiagnostics.event(appContext, "gatt.failure", mapOf("reason" to reason, "code" to code, "id" to deviceId))
        mainHandler.removeCallbacks(connectionTimeout)
        shouldReconnect = false
        cancelPendingReconnect()
        phase = "error"
        message = reason
        connectResult?.error(code, reason, snapshot())
        connectResult = null
        emitStatus()
        closeGatt()
    }

    private fun clearCharacteristics() {
        buttonCharacteristic = null
        stateCharacteristic = null
        batteryCharacteristic = null
        firmwareCharacteristic = null
        writeMode = null
    }

    private fun closeGatt() {
        val gatt = bluetoothGatt
        bluetoothGatt = null
        clearCharacteristics()
        if (gatt != null) {
            runCatching { gatt.disconnect() }
            runCatching { gatt.close() }
        }
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "type" to "status",
        "phase" to phase,
        "message" to message,
        "deviceId" to deviceId,
        "deviceName" to deviceName,
        "writeMode" to writeMode,
        "batteryPercent" to batteryPercent,
        "firmwareRevision" to firmwareRevision,
        "lastRawHex" to lastRawHex,
        "packetCount" to packetCount,
        "invalidPacketCount" to invalidPacketCount,
        "duplicatePacketCount" to duplicatePacketCount,
        "reconnectCount" to reconnectCount,
        "peripheralState" to if (phase == "connected") "connected" else "disconnected",
        "mainNotificationState" to if (phase == "connected") "enabled" else "unavailable",
        "lastDisconnectCode" to lastDisconnectCode,
        "lastDisconnectEpochMs" to lastDisconnectEpochMs,
        "mediaKeyObservationActive" to mediaKeyObserver.active,
    )

    private fun emitStatus() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post(::emitStatus)
            return
        }
        eventSink?.success(snapshot())
    }

    private fun emitButtonEvent(event: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) {
            sink.success(event)
            return
        }
        while (bufferedButtonEvents.size >= MAX_BUFFERED_BUTTON_EVENTS) {
            bufferedButtonEvents.removeFirst()
        }
        bufferedButtonEvents.addLast(event)
    }

    /** Reopens the last verified H20 GATT link after service/process recovery. */
    fun onBackgroundSessionStarted() {
        mainHandler.post {
            if (disposed || bluetoothGatt != null ||
                runtimePreferences.getBoolean(MANUAL_DISCONNECT, false) ||
                phase == "connecting" || phase == "reconnecting" ||
                !hasPermissions() || adapter?.isEnabled != true
            ) {
                return@post
            }
            val savedId = runtimePreferences.getString(LAST_DEVICE_ID, null)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: return@post
            val device = runCatching { adapter?.getRemoteDevice(savedId) }.getOrNull()
                ?: return@post
            deviceId = savedId
            deviceName = runtimePreferences.getString(LAST_DEVICE_NAME, null)
                ?: runCatching { device.name }.getOrNull()
                ?: ""
            shouldReconnect = true
            reconnectAttempts = 0
            cancelPendingReconnect()
            phase = "reconnecting"
            message = "Đang khôi phục kết nối HM-D001…"
            emitStatus()
            openGatt(device)
        }
    }

    /** Stops service-owned BLE without forgetting the parent's verified H20. */
    fun onBackgroundSessionStopped() {
        mainHandler.post {
            if (disposed) return@post
            cancelConnectionAttempt(preserveConnected = false)
            message = "Phiên HOMI nền đã dừng."
            emitStatus()
        }
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        classicDiscovery.cancel()
        finishBond(false)
        runCatching { appContext.unregisterReceiver(adapterStateReceiver) }
        mediaKeyObserver.dispose()
        shouldReconnect = false
        mainHandler.removeCallbacksAndMessages(null)
        reconnectRunnable = null
        stopScan(complete = false)
        connectResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        connectResult = null
        pendingWriteResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        pendingWriteResult = null
        permissionResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        permissionResult = null
        enableBluetoothResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        enableBluetoothResult = null
        closeGatt()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    private data class ScannedDevice(
        val id: String,
        val name: String,
        val rssi: Int,
        val likely: Boolean,
        val advertisesControlService: Boolean,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "id" to id,
            "name" to name,
            "rssi" to rssi,
            "isLikelyAiv0" to likely,
            "advertisesControlService" to advertisesControlService,
        )
    }

    private fun isObservedH20MainPacket(value: ByteArray): Boolean =
        H20ControlObservation.isObservedMainPacket(value)

    private fun ByteArray.toHex(): String = joinToString(" ") {
        (it.toInt() and 0xFF).toString(16).padStart(2, '0').uppercase(Locale.ROOT)
    }
}
