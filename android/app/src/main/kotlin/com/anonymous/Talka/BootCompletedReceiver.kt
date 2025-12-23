package com.anonymous.Talka

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            try {
                Log.i("BootCompletedReceiver", "Device boot completed; initializing lightweight app components")
                // Optionally, preload minimal resources or log for analytics.
                // Avoid starting long-running services here to respect user/device state.
            } catch (e: Exception) {
                Log.e("BootCompletedReceiver", "Error on boot: ${e.message}", e)
            }
        }
    }
}