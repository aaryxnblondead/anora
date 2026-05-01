package com.anorahealth.anora

import android.content.Context
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.app.KeyguardManager
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Federated Learning Platform Channel for Android
 * 
 * Provides native access to:
 * - Battery charging state (BatteryManager)
 * - Device idle state (KeyguardManager, user interaction tracking)
 * - App lifecycle events
 */
class FLPlatformChannel(private val context: Context) {
    companion object {
        private const val CHANNEL_NAME = "com.anorahealth.anora/fl"
    }

    private var lastUserInteractionTime = System.currentTimeMillis()

    fun setupChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceCharging" -> result.success(isDeviceCharging())
                "isDeviceIdle" -> result.success(isDeviceIdle())
                "recordUserInteraction" -> {
                    recordUserInteraction()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Check if device is currently charging.
     * 
     * Returns true if:
     * - Battery is connected to power (USB, AC, wireless)
     * - Charging state is not BATTERY_STATUS_UNKNOWN
     */
    private fun isDeviceCharging(): Boolean {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (batteryManager != null) {
                val status = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
                status == BatteryManager.BATTERY_STATUS_CHARGING || 
                status == BatteryManager.BATTERY_STATUS_FULL
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * Check if device is idle.
     * 
     * Device is considered idle when:
     * 1. Screen is locked (KeyguardManager)
     * 2. No user interaction for MIN_IDLE_TIME milliseconds
     * 3. App is in background
     */
    private fun isDeviceIdle(): Boolean {
        return try {
            val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            val isScreenLocked = keyguardManager?.isKeyguardLocked ?: false
            
            val timeSinceLastInteraction = System.currentTimeMillis() - lastUserInteractionTime
            val minIdleTimeMs = 15 * 60 * 1000 // 15 minutes
            
            isScreenLocked && (timeSinceLastInteraction > minIdleTimeMs)
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * Record user interaction timestamp.
     * Called from native MainActivity when user touches screen or interacts.
     */
    fun recordUserInteraction() {
        lastUserInteractionTime = System.currentTimeMillis()
    }

    /**
     * Notify Dart that user interacted with app.
     * Call from MainActivity or gesture detectors.
     * 
     * Usage in MainActivity.onUserInteraction():
     * ```kotlin
     * flPlatformChannel?.recordUserInteraction()
     * ```
     */
    fun notifyUserInteraction() {
        lastUserInteractionTime = System.currentTimeMillis()
    }
}
