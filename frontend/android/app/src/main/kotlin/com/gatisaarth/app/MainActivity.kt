package com.gatisaarth.app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import java.io.File
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.gatisaarth.app/device_sensors"
    private val MAP_PACKS_CHANNEL = "com.gatisaarth.app/map_packs"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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

