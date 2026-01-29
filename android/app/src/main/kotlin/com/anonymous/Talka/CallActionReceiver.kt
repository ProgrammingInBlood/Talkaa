package com.anonymous.Talka

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.app.NotificationManager
import android.os.Build

class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val action = intent.action
        val callId = intent.getStringExtra(CallForegroundService.EXTRA_CALL_ID)
        if (callId == null) {
            Log.e("CallActionReceiver", "Missing callId in intent for action=$action")
            return
        }

        when (action) {
            CallForegroundService.ACTION_DECLINE -> {
                // Try to forward to Dart - if Flutter is detached, action is stored
                val sent = CallFlutterBridge.sendActionToDart("decline", callId)
                
                // Cancel notification and stop service regardless
                try {
                    val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(callId.hashCode())
                } catch (_: Exception) {}
                try {
                    ctx.stopService(Intent(ctx, CallForegroundService::class.java))
                } catch (_: Exception) {}
                
                // If Flutter was detached, launch app to process the decline
                if (!sent) {
                    launchAppWithAction(ctx, CallForegroundService.ACTION_DECLINE, callId)
                }
            }
            CallForegroundService.ACTION_ANSWER -> {
                // Try to forward to Flutter - if detached, action is stored
                CallFlutterBridge.sendActionToDart("answer", callId)
                
                // ALWAYS launch the app for answer action (to show call screen)
                launchAppWithAction(ctx, CallForegroundService.ACTION_ANSWER, callId)
            }
            CallForegroundService.ACTION_HANGUP -> {
                // Try to forward to Dart - if Flutter is detached, action is stored
                val sent = CallFlutterBridge.sendActionToDart("hangup", callId)
                
                // Cancel notification and stop service regardless
                try {
                    val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(callId.hashCode())
                } catch (_: Exception) {}
                try {
                    ctx.stopService(Intent(ctx, CallForegroundService::class.java))
                } catch (_: Exception) {}
                
                // If Flutter was detached, launch app to process the hangup
                if (!sent) {
                    launchAppWithAction(ctx, CallForegroundService.ACTION_HANGUP, callId)
                }
            }
            else -> {
                Log.w("CallActionReceiver", "Unhandled action=$action for callId=$callId")
            }
        }
    }
    
    private fun launchAppWithAction(ctx: Context, action: String, callId: String) {
        try {
            val launchIntent = Intent(ctx, CallActivity::class.java).apply {
                this.action = action
                putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            ctx.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e("CallActionReceiver", "Failed to launch app: ${e.message}")
        }
    }
}