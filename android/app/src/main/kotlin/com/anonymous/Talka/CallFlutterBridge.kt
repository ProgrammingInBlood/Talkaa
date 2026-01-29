package com.anonymous.Talka

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object CallFlutterBridge {
    private const val CHANNEL = "app.call"
    private const val PREFS_NAME = "call_pending_action"
    private const val KEY_ACTION = "pending_action"
    private const val KEY_CALL_ID = "pending_call_id"
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var isFlutterAttached = false

    fun init(engine: FlutterEngine, context: Context) {
        appContext = context.applicationContext
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler(::onMethodCall)
        isFlutterAttached = true
    }
    
    fun setFlutterDetached() {
        isFlutterAttached = false
        channel = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext ?: run {
            result.error("no_ctx", "No application context", null)
            return
        }
        when (call.method) {
            "call.startService" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val style = (args["style"] as? String ?: "incoming").lowercase()
                val callId = args["callId"] as? String ?: System.currentTimeMillis().toString()
                val name = args["name"] as? String ?: "Incoming call"
                val avatar = args["avatar"] as? String
                val timeoutMs = (args["timeoutMs"] as? Number)?.toLong()
                val intent = Intent(ctx, CallForegroundService::class.java).apply {
                    putExtra(CallForegroundService.EXTRA_STYLE, style)
                    putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                    putExtra(CallForegroundService.EXTRA_CALLER_NAME, name)
                    if (avatar != null) putExtra(CallForegroundService.EXTRA_AVATAR_URL, avatar)
                    if (timeoutMs != null) putExtra("timeoutMs", timeoutMs)
                }
                try { ctx.startService(intent) } catch (_: Exception) {}
                result.success(null)
            }
            "call.updateStyle" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val style = (args["style"] as? String ?: "ongoing").lowercase()
                val callId = args["callId"] as? String ?: return result.error("missing_callId", "callId required", null)
                val name = args["name"] as? String ?: "On call"
                val intent = Intent(ctx, CallForegroundService::class.java).apply {
                    putExtra(CallForegroundService.EXTRA_STYLE, style)
                    putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                    putExtra(CallForegroundService.EXTRA_CALLER_NAME, name)
                }
                try { ctx.startService(intent) } catch (_: Exception) {}
                result.success(null)
            }
            "call.endService" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val callId = args["callId"] as? String ?: return result.error("missing_callId", "callId required", null)
                try { ctx.stopService(Intent(ctx, CallForegroundService::class.java)) } catch (_: Exception) {}
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.cancel(callId.hashCode())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun sendActionToDart(action: String, callId: String): Boolean {
        android.util.Log.d("CallFlutterBridge", "sendActionToDart: action=$action, callId=$callId, isFlutterAttached=$isFlutterAttached, channel=${channel != null}")
        val args = mapOf("action" to action, "callId" to callId)
        
        // Try to send via existing channel first
        if (isFlutterAttached && channel != null) {
            try {
                android.util.Log.d("CallFlutterBridge", "Sending via existing channel")
                channel?.invokeMethod("call.onAction", args)
                android.util.Log.d("CallFlutterBridge", "Sent via existing channel successfully")
                return true
            } catch (e: Exception) {
                android.util.Log.e("CallFlutterBridge", "Failed to send via existing channel", e)
            }
        }
        
        // Try cached engine
        try {
            val engine = FlutterEngineCache.getInstance().get("app_call_engine")
            android.util.Log.d("CallFlutterBridge", "Trying cached engine: ${engine != null}")
            if (engine != null) {
                val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                android.util.Log.d("CallFlutterBridge", "Sending via cached engine channel")
                ch.invokeMethod("call.onAction", args)
                android.util.Log.d("CallFlutterBridge", "Sent via cached engine successfully")
                return true
            }
        } catch (e: Exception) {
            android.util.Log.e("CallFlutterBridge", "Failed to send via cached engine", e)
        }
        
        // Flutter not available - store pending action for when app starts
        android.util.Log.d("CallFlutterBridge", "Storing pending action for later")
        storePendingAction(action, callId)
        return false
    }

    fun notifyTimeout(callId: String) {
        val args = mapOf("callId" to callId)
        
        if (isFlutterAttached && channel != null) {
            try {
                channel?.invokeMethod("call.onTimeout", args)
                return
            } catch (_: Exception) {}
        }
        
        try {
            val engine = FlutterEngineCache.getInstance().get("app_call_engine")
            if (engine != null) {
                val ch = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                ch.invokeMethod("call.onTimeout", args)
            }
        } catch (_: Exception) {}
    }
    
    private fun storePendingAction(action: String, callId: String) {
        val ctx = appContext ?: return
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(KEY_ACTION, action)
            .putString(KEY_CALL_ID, callId)
            .apply()
    }
    
    fun getPendingAction(context: Context): Pair<String, String>? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val action = prefs.getString(KEY_ACTION, null)
        val callId = prefs.getString(KEY_CALL_ID, null)
        if (action != null && callId != null) {
            return Pair(action, callId)
        }
        return null
    }
    
    fun clearPendingAction(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
    }
}