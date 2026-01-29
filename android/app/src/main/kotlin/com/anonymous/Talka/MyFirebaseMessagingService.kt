package com.anonymous.Talka

import android.content.Intent
import android.util.Log
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {
    
    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val ACTIVE_CHAT_KEY = "flutter.active_chat_id"
        private const val ACTIVE_CHAT_TIME_KEY = "flutter.active_chat_id_time"
    }
    
    private fun isActiveChatId(chatId: String): Boolean {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val storedChatId = prefs.getString(ACTIVE_CHAT_KEY, null)
            val storedTime = prefs.getLong(ACTIVE_CHAT_TIME_KEY, 0L)
            
            if (storedChatId == chatId && storedTime > 0) {
                // Check if stored value is recent (within 5 minutes)
                val age = System.currentTimeMillis() - storedTime
                if (age < 5 * 60 * 1000) {
                    Log.d("MyFcmService", "Chat $chatId is active (age=${age/1000}s)")
                    return true
                }
            }
        } catch (e: Exception) {
            Log.e("MyFcmService", "Error checking active chat: ${e.message}")
        }
        return false
    }
    
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        try {
            val data = remoteMessage.data
            if (data.isNullOrEmpty()) return
            val typeRaw = (data["type"] ?: data["message_type"] ?: data["notification_type"] ?: "").toString().lowercase()

            if (typeRaw == "call_invite") {
                val callerName = (data["callerName"] ?: data["caller_name"] ?: "Incoming call").toString()
                val callId = (data["callId"] ?: data["session_id"] ?: data["call_id"] ?: System.currentTimeMillis().toString()).toString()
                val avatarUrl = (data["avatarUrl"] ?: data["avatar_url"])?.toString()
                val timeoutMs: Long = try {
                    val raw = data["timeoutMs"]
                    when (raw) {
                        is String -> raw.toLongOrNull() ?: 30000L
                        is Number -> raw.toLong()
                        else -> 30000L
                    }
                } catch (_: Exception) {
                    30000L
                }

                val ctx: android.content.Context = this
                val intent = Intent(ctx, CallForegroundService::class.java)
                intent.putExtra(CallForegroundService.EXTRA_CALLER_NAME, callerName)
                intent.putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                intent.putExtra(CallForegroundService.EXTRA_AVATAR_URL, avatarUrl)
                intent.putExtra("timeoutMs", timeoutMs)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
                return
            }

            if (typeRaw == "call_accept") {
                try {
                    val ctx: Context = this
                    val callId = (data["session_id"] ?: data["callId"] ?: data["call_id"] ?: System.currentTimeMillis().toString()).toString()
                    val senderName = (data["sender_name"] ?: data["callerName"] ?: data["caller_name"] ?: "On call").toString()
                    val avatarUrl = (data["avatar_url"] ?: data["avatarUrl"])?.toString()
                    val intent = Intent(ctx, CallForegroundService::class.java).apply {
                        putExtra(CallForegroundService.EXTRA_CALLER_NAME, senderName)
                        putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                        putExtra(CallForegroundService.EXTRA_AVATAR_URL, avatarUrl)
                        putExtra(CallForegroundService.EXTRA_STYLE, "ongoing")
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                        ctx.startForegroundService(intent)
                    } else {
                        ctx.startService(intent)
                    }
                    // Update in place; no cancel needed
                } catch (_: Exception) {}
                return
            }

            if (typeRaw == "call_cancel" || typeRaw == "call_reject" || typeRaw == "call_decline" || typeRaw == "call_end") {
                try {
                    val ctx: Context = this
                    val callId = (data["session_id"] ?: data["callId"] ?: data["call_id"] ?: System.currentTimeMillis().toString()).toString()
                    
                    // Cancel notification
                    val mgr = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    mgr.cancel(callId.hashCode())
                    mgr.cancel(CallForegroundService.NOTIFICATION_ID)
                    
                    // Stop foreground service with ACTION_STOP
                    val intent = Intent(ctx, CallForegroundService::class.java).apply {
                        action = CallForegroundService.ACTION_STOP
                    }
                    ctx.stopService(intent)
                    
                    // Also notify Flutter via CallFlutterBridge
                    CallFlutterBridge.sendActionToDart("remote_end", callId)
                } catch (_: Exception) {}
                return
            }
            
            // Check for chat messages and suppress if user is in that conversation
            val chatId = (data["chat_id"] ?: "").toString()
            if (chatId.isNotEmpty() && typeRaw.isEmpty()) {
                // This is a chat message - check if user is viewing this conversation
                if (isActiveChatId(chatId)) {
                    Log.d("MyFcmService", "Suppressing notification for active chat: $chatId")
                    return
                }
                // Let Flutter handle showing the notification
            }
        } catch (e: Exception) {
            Log.e("MyFcmService", "onMessageReceived error: ${e.message}", e)
        }
    }
}