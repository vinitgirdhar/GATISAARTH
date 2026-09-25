package com.gatisaarth.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.location.GnssMeasurementsEvent
import android.location.GnssMeasurement
import android.location.GnssStatus
import android.location.LocationManager
import java.io.File
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.net.wifi.WifiManager
import android.net.wifi.rtt.RangingRequest
import android.net.wifi.rtt.RangingResult
import android.net.wifi.rtt.RangingResultCallback
import android.net.wifi.rtt.WifiRttManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity

class MainActivity: FlutterActivity() {
    companion object {
        private var activityEventSink: EventChannel.EventSink? = null

        fun emitActivity(mode: String) {
            Handler(Looper.getMainLooper()).post { activityEventSink?.success(mode) }
        }
    }

    private val CHANNEL = "com.gatisaarth.app/device_sensors"
    private val MAP_PACKS_CHANNEL = "com.gatisaarth.app/map_packs"
    private val GNSS_CONTROL_CHANNEL = "com.gatisaarth.app/gnss_control"
    private val GNSS_TELEMETRY_CHANNEL = "com.gatisaarth.app/gnss_telemetry"
    private val ACTIVITY_CONTROL_CHANNEL = "com.gatisaarth.app/activity_control"
    private val ACTIVITY_UPDATES_CHANNEL = "com.gatisaarth.app/activity_updates"
    private val WIFI_RTT_CHANNEL = "com.gatisaarth.app/wifi_rtt"
    private val ACTIVITY_PERMISSION_REQUEST = 7412
    private val WIFI_RTT_PERMISSION_REQUEST = 7413
    private var pendingActivityResult: MethodChannel.Result? = null
    private var activityRequested = false
    private var pendingRttResult: MethodChannel.Result? = null
    private var pendingRttBssid: String? = null
    private var gnssEventSink: EventChannel.EventSink? = null
    private var gnssStatus: GnssStatus? = null
    private var gnssStatusRegistered = false
    private var rawMeasurementsRegistered = false
    private var rawMeasurementsObserved = false
    private var rawMeasurementCount = 0
    private var adrMeasurementCount = 0
    private var textToSpeech: TextToSpeech? = null
    private var pendingGuidance: String? = null

    private val gnssStatusCallback = object : GnssStatus.Callback() {
        override fun onSatelliteStatusChanged(status: GnssStatus) {
            gnssStatus = status
            emitGnssSnapshot(status)
        }

        override fun onStopped() {
            gnssStatus = null
            emitGnssSnapshot(null)
        }
    }

    private val rawMeasurementsCallback = object : GnssMeasurementsEvent.Callback() {
        override fun onGnssMeasurementsReceived(eventArgs: GnssMeasurementsEvent) {
            rawMeasurementsObserved = true
            rawMeasurementCount = eventArgs.measurements.size
            adrMeasurementCount = eventArgs.measurements.count { measurement ->
                measurement.accumulatedDeltaRangeState and
                    GnssMeasurement.ADR_STATE_VALID != 0
            }
            emitGnssSnapshot(gnssStatus)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GNSS_TELEMETRY_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                gnssEventSink = events
                emitGnssSnapshot(gnssStatus)
            }

            override fun onCancel(arguments: Any?) {
                gnssEventSink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIVITY_UPDATES_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                activityEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                activityEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIVITY_CONTROL_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startActivityTransitions(result)
                "stop" -> {
                    activityRequested = false
                    stopActivityTransitions()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIFI_RTT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "range" -> rangeWifiRtt(call.argument<String>("radioId"), result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GNSS_CONTROL_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startGnssTelemetry()
                    result.success(null)
                }
                "stop" -> {
                    stopGnssTelemetry()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAP_PACKS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "locate" -> result.success(locateMapPack(call.argument<String>("name")))
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceTemperature" -> {
                    val temp = getBatteryTemperature()
                    result.success(temp)
                }
                "vibrateDevice" -> {
                    val durationMs = (call.argument<Int>("durationMs") ?: 200).toLong().coerceIn(1L, 2000L)
                    val amplitude = call.argument<Int>("amplitude") ?: VibrationEffect.DEFAULT_AMPLITUDE
                    vibratePhone(durationMs, amplitude)
                    result.success(true)
                }
                "getDeviceInfo" -> {
                    result.success(
                        mapOf(
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
                        )
                    )
                }
                "setKeepScreenOn" -> {
                    // A recorded drive dies at screen timeout: Flutter reports
                    // AppLifecycleState.paused and the session stops sensors and
                    // GPS by design. Holding the window flag is the least
                    // invasive fix -- no wake lock permission, no foreground
                    // service, and it is released the moment recording stops.
                    val on = call.argument<Boolean>("on") ?: false
                    runOnUiThread {
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                "speakGuidance" -> {
                    speakGuidance(call.argument<String>("message") ?: "")
                    result.success(true)
                }
                "stopGuidance" -> {
                    textToSpeech?.stop()
                    pendingGuidance = null
                    result.success(true)
                }
                "signEvidence" -> {
                    try {
                        val payload = call.argument<String>("payload") ?: ""
                        result.success(signEvidence(payload))
                    } catch (error: Exception) {
                        result.error("EVIDENCE_SIGNING_FAILED", error.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasFineLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasActivityPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    private fun activityPendingIntent(): PendingIntent = PendingIntent.getBroadcast(
        this,
        0,
        Intent(this, ActivityTransitionReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
    )

    private fun startActivityTransitions(result: MethodChannel.Result) {
        activityRequested = true
        if (!hasActivityPermission()) {
            pendingActivityResult = result
            requestPermissions(
                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                ACTIVITY_PERMISSION_REQUEST
            )
            return
        }
        registerActivityTransitions(result)
    }

    private fun registerActivityTransitions(result: MethodChannel.Result?) {
        val activities = listOf(
            DetectedActivity.IN_VEHICLE,
            DetectedActivity.ON_BICYCLE,
            DetectedActivity.WALKING,
            DetectedActivity.RUNNING,
            DetectedActivity.STILL
        )
        val transitions = activities.map { activity ->
            ActivityTransition.Builder()
                .setActivityType(activity)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build()
        }
        try {
            ActivityRecognition.getClient(this)
                .requestActivityTransitionUpdates(
                    ActivityTransitionRequest(transitions),
                    activityPendingIntent()
                )
                .addOnSuccessListener { result?.success(null) }
                .addOnFailureListener { error ->
                    result?.error("ACTIVITY_TRANSITIONS_FAILED", error.message, null)
                }
        } catch (error: SecurityException) {
            result?.error("ACTIVITY_PERMISSION_DENIED", error.message, null)
        }
    }

    private fun stopActivityTransitions() {
        try {
            ActivityRecognition.getClient(this)
                .removeActivityTransitionUpdates(activityPendingIntent())
        } catch (_: SecurityException) {
        }
    }

    private fun rangeWifiRtt(bssid: String?, result: MethodChannel.Result) {
        if (bssid == null || !Regex("^[0-9a-f]{2}(:[0-9a-f]{2}){5}$").matches(bssid)) {
            result.error("RTT_INVALID_ID", "Invalid registered BSSID", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_RTT)) {
            result.error("RTT_UNSUPPORTED", "Phone does not support Wi-Fi RTT", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) !=
                PackageManager.PERMISSION_GRANTED) {
            if (pendingRttResult != null) {
                result.error("RTT_BUSY", "Another range request is in progress", null)
                return
            }
            pendingRttResult = result
            pendingRttBssid = bssid
            requestPermissions(
                arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
                WIFI_RTT_PERMISSION_REQUEST
            )
            return
        }
        performWifiRtt(bssid, result)
    }

    private fun performWifiRtt(bssid: String, result: MethodChannel.Result) {
        if (!hasFineLocationPermission()) {
            result.error("RTT_LOCATION_PERMISSION", "Precise location permission required", null)
            return
        }
        try {
            val rtt = getSystemService(Context.WIFI_RTT_RANGING_SERVICE) as? WifiRttManager
            if (rtt == null || !rtt.isAvailable) {
                result.error("RTT_UNAVAILABLE", "Wi-Fi RTT currently unavailable", null)
                return
            }
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val accessPoint = wifi.scanResults.firstOrNull {
                it.BSSID.equals(bssid, ignoreCase = true) && it.is80211mcResponder
            }
            if (accessPoint == null) {
                result.error("RTT_AP_NOT_FOUND", "Registered RTT access point not visible", null)
                return
            }
            val request = RangingRequest.Builder().addAccessPoint(accessPoint).build()
            rtt.startRanging(request, { task -> runOnUiThread(task) },
                object : RangingResultCallback() {
                    override fun onRangingFailure(code: Int) {
                        result.error("RTT_RANGE_FAILED", "Ranging failed: $code", null)
                    }

                    override fun onRangingResults(results: List<RangingResult>) {
                        val measured = results.firstOrNull {
                            it.macAddress?.toString()?.equals(bssid, ignoreCase = true) == true &&
                                it.status == RangingResult.STATUS_SUCCESS
                        }
                        if (measured == null || measured.numSuccessfulMeasurements < 2) {
                            result.error("RTT_NO_VALID_RANGE", "No reliable RTT measurement", null)
                            return
                        }
                        val ageMs = (SystemClock.elapsedRealtime() -
                            measured.rangingTimestampMillis).coerceAtLeast(0L)
                        result.success(mapOf(
                            "radioId" to bssid,
                            "rangeM" to measured.distanceMm / 1000.0,
                            "rangeSigmaM" to measured.distanceStdDevMm / 1000.0,
                            "ageMs" to ageMs
                        ))
                    }
                })
        } catch (error: SecurityException) {
            result.error("RTT_PERMISSION_DENIED", error.message, null)
        } catch (error: Exception) {
            result.error("RTT_UNAVAILABLE", error.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == WIFI_RTT_PERMISSION_REQUEST) {
            val result = pendingRttResult
            val bssid = pendingRttBssid
            pendingRttResult = null
            pendingRttBssid = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED &&
                result != null && bssid != null) {
                performWifiRtt(bssid, result)
            } else {
                result?.error("RTT_PERMISSION_DENIED", "Nearby Wi-Fi permission denied", null)
            }
            return
        }
        if (requestCode != ACTIVITY_PERMISSION_REQUEST) return
        val result = pendingActivityResult
        pendingActivityResult = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            if (activityRequested) registerActivityTransitions(result)
            else result?.success(null)
        } else {
            result?.error("ACTIVITY_PERMISSION_DENIED", "Activity recognition denied", null)
        }
    }

    private fun speakGuidance(message: String) {
        if (message.isBlank()) return
        val engine = textToSpeech
        if (engine != null) {
            engine.speak(message, TextToSpeech.QUEUE_FLUSH, null, "mission-guidance")
            return
        }
        pendingGuidance = message
        textToSpeech = TextToSpeech(applicationContext) { status ->
            val ready = textToSpeech
            if (status == TextToSpeech.SUCCESS && ready != null) {
                ready.language = Locale.forLanguageTag("en-IN")
                pendingGuidance?.let {
                    ready.speak(it, TextToSpeech.QUEUE_FLUSH, null, "mission-guidance")
                }
            }
            pendingGuidance = null
        }
    }

    private fun signEvidence(payload: String): Map<String, String> {
        require(payload.isNotEmpty()) { "Evidence payload must not be empty" }
        val alias = "gatisaarth-field-evidence-v1"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!keyStore.containsAlias(alias)) {
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                "AndroidKeyStore"
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setUserAuthenticationRequired(false)
                    .build()
            )
            generator.generateKeyPair()
        }
        val entry = keyStore.getEntry(alias, null) as KeyStore.PrivateKeyEntry
        val bytes = payload.toByteArray(Charsets.UTF_8)
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(entry.privateKey)
        signer.update(bytes)
        val signature = signer.sign()
        val publicKey = entry.certificate.publicKey.encoded
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        val keyId = MessageDigest.getInstance("SHA-256")
            .digest(publicKey)
            .take(12)
            .joinToString("") { "%02x".format(it) }
        return mapOf(
            "algorithm" to "SHA256withECDSA",
            "keyId" to keyId,
            "payloadSha256" to digest.joinToString("") { "%02x".format(it) },
            "publicKeyBase64" to Base64.encodeToString(publicKey, Base64.NO_WRAP),
            "signatureBase64" to Base64.encodeToString(signature, Base64.NO_WRAP)
        )
    }

    private fun startGnssTelemetry() {
        if (!hasFineLocationPermission()) {
            emitGnssSnapshot(null)
            return
        }
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val handler = Handler(Looper.getMainLooper())
        if (!gnssStatusRegistered) {
            gnssStatusRegistered = try {
                @Suppress("DEPRECATION")
                manager.registerGnssStatusCallback(gnssStatusCallback, handler)
            } catch (_: SecurityException) {
                false
            }
        }
        if (!rawMeasurementsRegistered) {
            rawMeasurementsRegistered = try {
                @Suppress("DEPRECATION")
                manager.registerGnssMeasurementsCallback(rawMeasurementsCallback, handler)
            } catch (_: SecurityException) {
                false
            }
        }
        emitGnssSnapshot(gnssStatus)
    }

    private fun stopGnssTelemetry() {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (gnssStatusRegistered) manager.unregisterGnssStatusCallback(gnssStatusCallback)
        if (rawMeasurementsRegistered) {
            manager.unregisterGnssMeasurementsCallback(rawMeasurementsCallback)
        }
        gnssStatusRegistered = false
        rawMeasurementsRegistered = false
        gnssStatus = null
    }

    private fun emitGnssSnapshot(status: GnssStatus?) {
        val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val rawMeasurementsSupported =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.gnssCapabilities.hasMeasurements()
            } else {
                // Before API 31, callback registration always returns true.
                // Only claim support after the receiver delivers measurements.
                rawMeasurementsObserved
            }
        val satellites = mutableListOf<Map<String, Any>>()
        if (status != null) {
            for (index in 0 until status.satelliteCount) {
                val item = mutableMapOf<String, Any>(
                    "svid" to status.getSvid(index),
                    "constellation" to status.getConstellationType(index),
                    "cn0DbHz" to status.getCn0DbHz(index).toDouble(),
                    "usedInFix" to status.usedInFix(index),
                    "elevationDegrees" to status.getElevationDegrees(index).toDouble(),
                    "azimuthDegrees" to status.getAzimuthDegrees(index).toDouble()
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    status.hasCarrierFrequencyHz(index)) {
                    item["carrierFrequencyHz"] =
                        status.getCarrierFrequencyHz(index).toDouble()
                }
                satellites.add(item)
            }
        }
        gnssEventSink?.success(
            mapOf(
                "timestampMs" to System.currentTimeMillis(),
                "permissionGranted" to hasFineLocationPermission(),
                "statusSupported" to
                    packageManager.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS),
                "rawMeasurementsSupported" to rawMeasurementsSupported,
                "rawMeasurementCount" to rawMeasurementCount,
                "adrMeasurementCount" to adrMeasurementCount,
                "satellites" to satellites
            )
        )
    }

    override fun onDestroy() {
        stopActivityTransitions()
        activityEventSink = null
        stopGnssTelemetry()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    /**
     * Where an offline map archive (PMTiles) can be read from, or null.
     *
     * 1. A copy pushed onto the phone (`adb push x.pmtiles
     *    /sdcard/Android/data/<package>/files/offline_maps/`) wins, so maps can
     *    be updated for testing without a new build.
     * 2. Then a copy the app downloaded into its own storage.
     * 3. Otherwise the copy bundled in the APK. It is stored uncompressed
     *    (see `noCompress` in build.gradle), so it is read in place: the APK
     *    path plus the asset's offset. No second copy is made on the phone.
     */
    private fun locateMapPack(name: String?): Map<String, Any>? {
        if (name.isNullOrEmpty() || name.contains('/') || name.contains('\\') || name.contains("..")) {
            return null
        }
        // The app's own storage holds what it downloaded; the external app folder
        // holds what was pushed by hand (adb). A pushed copy wins, so it can be
        // used to try a newer map.
        val folders = listOfNotNull(
            getExternalFilesDir(null)?.let { it to "sideloaded" },
            filesDir to "downloaded"
        )
        for ((folder, origin) in folders) {
            val file = File(File(folder, "offline_maps"), name)
            if (file.isFile && file.length() > 0) {
                return mapOf(
                    "path" to file.absolutePath,
                    "offset" to 0L,
                    "length" to file.length(),
                    "origin" to origin
                )
            }
        }
        return try {
            assets.openFd("flutter_assets/assets/maps/packs/$name").use { fd ->
                mapOf(
                    "path" to applicationInfo.sourceDir,
                    "offset" to fd.startOffset,
                    "length" to fd.declaredLength,
                    "origin" to "bundled"
                )
            }
        } catch (e: Exception) {
            // Not bundled (a build made without the archives), or stored
            // compressed: the map falls back to online/cached tiles.
            null
        }
    }

    /** Battery temperature in degC, or null when the phone does not report it. */
    private fun getBatteryTemperature(): Double? {
        return try {
            val intent = applicationContext.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?: Int.MIN_VALUE
            if (tempTenths == Int.MIN_VALUE) null else tempTenths / 10.0
        } catch (e: Exception) {
            null
        }
    }

    private fun vibratePhone(durationMs: Long, amplitude: Int) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                val vibrator = vibratorManager?.defaultVibrator
                if (vibrator != null && vibrator.hasVibrator()) {
                    val effect = VibrationEffect.createOneShot(
                        durationMs,
                        if (amplitude in 1..255) amplitude else VibrationEffect.DEFAULT_AMPLITUDE
                    )
                    vibrator.vibrate(effect)
                }
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (vibrator != null && vibrator.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val effect = VibrationEffect.createOneShot(
                            durationMs,
                            if (amplitude in 1..255) amplitude else VibrationEffect.DEFAULT_AMPLITUDE
                        )
                        vibrator.vibrate(effect)
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(durationMs)
                    }
                }
            }
        } catch (e: Exception) {
            // Graceful fallback if vibration is not allowed or unavailable
        }
    }
}

