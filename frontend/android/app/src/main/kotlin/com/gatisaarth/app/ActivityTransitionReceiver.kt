package com.gatisaarth.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

class ActivityTransitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!ActivityTransitionResult.hasResult(intent)) return
        val event = ActivityTransitionResult.extractResult(intent)
            ?.transitionEvents
            ?.lastOrNull { it.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER }
            ?: return
        val mode = when (event.activityType) {
            DetectedActivity.IN_VEHICLE -> "inVehicle"
            DetectedActivity.ON_BICYCLE -> "bicycle"
            DetectedActivity.WALKING, DetectedActivity.ON_FOOT -> "walking"
            DetectedActivity.RUNNING -> "running"
            DetectedActivity.STILL -> "still"
            else -> "unknown"
        }
        MainActivity.emitActivity(mode)
    }
}
