package com.gatisaarth.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.GnssMeasurementsEvent
import android.location.GnssStatus
import android.location.LocationManager
import java.io.File
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.gatisaarth.app/device_sensors"
    private val MAP_PACKS_CHANNEL = "com.gatisaarth.app/map_packs"
    private val GNSS_CONTROL_CHANNEL = "com.gatisaarth.app/gnss_control"
    private val GNSS_TELEMETRY_CHANNEL = "com.gatisaarth.app/gnss_telemetry"
    private var gnssEventSink: EventChannel.EventSink? = null
    private var gnssStatus: GnssStatus? = null
    private var gnssStatusRegistered = false
    private var rawMeasurementsRegistered = false
    private var rawMeasurementsObserved = false

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
            if (!rawMeasurementsObserved) {
                rawMeasurementsObserved = true
                emitGnssSnapshot(gnssStatus)
            }
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
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasFineLocationPermission(): Boolean =
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

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
                "satellites" to satellites
            )
        )
    }

    override fun onDestroy() {
        stopGnssTelemetry()
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

    private fun getBatteryTemperature(): Double {
        return try {
            val intent = applicationContext.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
            if (tempTenths > 0) {
                tempTenths / 10.0
            } else {
                35.0 // Fallback nominal operating temperature
            }
        } catch (e: Exception) {
            35.0
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

