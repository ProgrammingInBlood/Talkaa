package com.anonymous.Talka

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.app.KeyguardManager
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.anonymous.talka/pip"
    private var pipEligible: Boolean = false
    private var lastAspect: Rational = Rational(9, 16)
    // Added: hold a reference to the MethodChannel for callbacks
    private var pipChannel: MethodChannel? = null

    // Call notification channel and actions
    private val CALL_CHANNEL = "com.anonymous.talka/call_notify"
    private var callNotifyChannel: MethodChannel? = null
    private val CALL_NOTIF_CHANNEL_ID = "call_notifications"
    private val ACTION_ANSWER = "com.anonymous.talka.ACTION_ANSWER"
    private val ACTION_DECLINE = "com.anonymous.talka.ACTION_DECLINE"
    private val ACTION_OPEN = "com.anonymous.talka.ACTION_OPEN_CALL"
    private val ACTION_HANGUP = "com.anonymous.talka.ACTION_HANGUP"
    private val EXTRA_CALL_ID = "extra_call_id"
    private var pendingStartupAction: String? = null
    private var pendingStartupCallId: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            val a = intent?.action
            val c = intent?.getStringExtra(EXTRA_CALL_ID)
            if (a == ACTION_OPEN || a == ACTION_ANSWER || a == ACTION_DECLINE || a == ACTION_HANGUP) {
                // Handle locked screen scenarios for incoming calls
                try {
                    val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    if (keyguardManager.isKeyguardLocked) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            setShowWhenLocked(true)
                            setTurnScreenOn(true)
                        } else {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                            )
                        }
                    }
                } catch (_: Exception) {}

                pendingStartupAction = a
                pendingStartupCallId = c
            }
        } catch (_: Exception) {}
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize the Flutter bridge for native-Flutter communication
        CallFlutterBridge.init(flutterEngine, this)
        
        // Store PiP channel reference for later callbacks
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pipChannel = channel
        channel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val w: Int? = call.argument("width")
                        val h: Int? = call.argument("height")
                        val ratio = if (w != null && h != null && h != 0) Rational(w, h) else lastAspect
                        lastAspect = ratio
                        val params = PictureInPictureParams.Builder()
                            .setAspectRatio(ratio)
                            .build()
                        try {
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("pip_error", e.message, null)
                        }
                    } else {
                        result.error("unsupported", "Picture-in-Picture requires Android O+", null)
                    }
                }
                "setPipEligible" -> {
                    pipEligible = call.argument<Boolean>("enabled") == true
                    val w: Int? = call.argument("width")
                    val h: Int? = call.argument<Int>("height")
                    if (w != null && h != null && h != 0) {
                        lastAspect = Rational(w, h)
                    }
                    result.success(true)
                }
                "isInPip" -> {
                    result.success(isInPictureInPictureMode)
                }
                else -> result.notImplemented()
            }
        }

        // Set up call notification channel
        val callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL)
        callNotifyChannel = callChannel
        callChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "getPendingCallAction" -> {
                    // First check intent-based pending action
                    var a = pendingStartupAction
                    var c = pendingStartupCallId
                    
                    // If no intent action, check SharedPreferences for stored action
                    if (a == null) {
                        val stored = CallFlutterBridge.getPendingAction(this)
                        if (stored != null) {
                            a = when (stored.first) {
                                "answer" -> ACTION_ANSWER
                                "decline" -> ACTION_DECLINE
                                "hangup" -> ACTION_HANGUP
                                else -> stored.first
                            }
                            c = stored.second
                            CallFlutterBridge.clearPendingAction(this)
                        }
                    }
                    
                    if (a == null) {
                        result.success(null)
                    } else {
                        val actionStr = when (a) {
                            ACTION_ANSWER -> "answer"
                            ACTION_DECLINE -> "decline"
                            ACTION_OPEN -> "open"
                            ACTION_HANGUP -> "hangup"
                            else -> a // Pass through if already a string action
                        }
                        pendingStartupAction = null
                        pendingStartupCallId = null
                        result.success(mapOf("action" to actionStr, "callId" to c))
                    }
                }
                "showIncomingCall" -> {
                    val callerName: String? = call.argument("callerName")
                    val callId: String? = call.argument("callId")
                    val avatarUrl: String? = call.argument("avatarUrl")
                    val timeoutAny: Any? = call.argument<Any>("timeoutMs")
                    val timeoutMs: Long = when (timeoutAny) {
                        is Number -> timeoutAny.toLong()
                        is String -> timeoutAny.toLongOrNull() ?: 30000L
                        else -> 30000L
                    }
                    if (callerName.isNullOrEmpty() || callId.isNullOrEmpty()) {
                        result.error("bad_args", "callerName and callId are required", null)
                    } else {
                        try {
                            showIncomingCall(this, callerName, callId, avatarUrl, timeoutMs)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("notify_error", e.message, null)
                        }
                    }
                }
                "startCallForegroundService" -> {
                    val callerName: String? = call.argument("callerName")
                    val callId: String? = call.argument("callId")
                    val avatarUrl: String? = call.argument("avatarUrl")
                    val timeoutAny: Any? = call.argument<Any>("timeoutMs")
                    val timeoutMs: Long = when (timeoutAny) {
                        is Number -> timeoutAny.toLong()
                        is String -> timeoutAny.toLongOrNull() ?: 30000L
                        else -> 30000L
                    }
                    val style: String = (call.argument<String>("style") ?: "incoming").lowercase()
                    if (callerName.isNullOrEmpty() || callId.isNullOrEmpty()) {
                        result.error("bad_args", "callerName and callId are required", null)
                    } else {
                        try {
                            val intent = Intent(this, CallForegroundService::class.java).apply {
                                putExtra(CallForegroundService.EXTRA_CALLER_NAME, callerName)
                                putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
                                putExtra(CallForegroundService.EXTRA_AVATAR_URL, avatarUrl)
                                putExtra(CallForegroundService.EXTRA_STYLE, style)
                                putExtra("timeoutMs", timeoutMs)
                            }
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("service_error", e.message, null)
                        }
                    }
                }
                "stopCallForegroundService" -> {
                    try {
                        val intent = Intent(this, CallForegroundService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("service_error", e.message, null)
                    }
                }
                "endCallNotification" -> {
                    val callId: String? = call.argument("callId")
                    cancelCallNotification(callId)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEligible && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(lastAspect)
                    .build()
                enterPictureInPictureMode(params)
            } catch (_: Exception) {
                // Ignore
            }
        }
    }

    // Added: notify Flutter when PiP mode changes to allow UI optimization
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", mapOf("active" to isInPictureInPictureMode))
    }

    // Handle notification action intents and route to Flutter
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.action ?: return
        val callId = intent.getStringExtra(EXTRA_CALL_ID)
        when (action) {
            ACTION_ANSWER -> {
                callNotifyChannel?.invokeMethod("callAction", mapOf("action" to "answer", "callId" to callId))
                cancelCallNotification(callId)
            }
            ACTION_DECLINE -> {
                callNotifyChannel?.invokeMethod("callAction", mapOf("action" to "decline", "callId" to callId))
                cancelCallNotification(callId)
            }
            ACTION_OPEN -> {
                callNotifyChannel?.invokeMethod("callAction", mapOf("action" to "open", "callId" to callId))
            }
            ACTION_HANGUP -> {
                callNotifyChannel?.invokeMethod("callAction", mapOf("action" to "hangup", "callId" to callId))
                cancelCallNotification(callId)
            }
        }
    }

    private fun ensureCallNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = context.getSystemService(NotificationManager::class.java)
            var channel = mgr.getNotificationChannel(CALL_NOTIF_CHANNEL_ID)
            if (channel == null) {
                channel = NotificationChannel(
                    CALL_NOTIF_CHANNEL_ID,
                    "Incoming calls",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "High-priority notifications for incoming calls"
                    enableVibration(true)
                    setShowBadge(false)
                    setBypassDnd(true)
                }
                mgr.createNotificationChannel(channel)
            }
        }
    }

    private fun ensureFullScreenIntentAllowed(context: Context) {
        // Android 14+: Users can disable full-screen intents per app.
        // Prompt the settings page if disabled to ensure incoming call UI appears over lockscreen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                val nm = context.getSystemService(NotificationManager::class.java)
                if (!nm.canUseFullScreenIntent()) {
                    val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                        data = android.net.Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    try { context.startActivity(intent) } catch (_: Exception) {}
                }
            } catch (_: Throwable) {
                // Ignore: best-effort guidance only
            }
        }
    }

    private fun showIncomingCall(context: Context, callerName: String, callId: String, avatarUrl: String?, timeoutMs: Long) {
        // Ensure the app is allowed to use full-screen intent on Android 14+
        ensureFullScreenIntentAllowed(context)
        ensureCallNotificationChannel(context)
        val contentIntent = PendingIntent.getActivity(
            context,
            1000 + callId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = ACTION_OPEN
                putExtra(EXTRA_CALL_ID, callId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            pendingIntentFlags()
        )
        val answerPI = PendingIntent.getActivity(
            context,
            2000 + callId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = ACTION_ANSWER
                putExtra(EXTRA_CALL_ID, callId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            pendingIntentFlags()
        )
        val declinePI = PendingIntent.getActivity(
            context,
            3000 + callId.hashCode(),
            Intent(context, MainActivity::class.java).apply {
                action = ACTION_DECLINE
                putExtra(EXTRA_CALL_ID, callId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            pendingIntentFlags()
        )

        val personBuilder = Person.Builder().setName(callerName)
        val avatarIcon: Icon? = avatarUrl?.let { url ->
            try {
                val uri = Uri.parse(url)
                Icon.createWithContentUri(uri)
            } catch (_: Exception) {
                null
            }
        }
        if (avatarIcon != null) {
            personBuilder.setIcon(avatarIcon)
        }
        val caller = personBuilder.build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CALL_NOTIF_CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
            .setSmallIcon(getAppSmallIcon())
            .setCategory(Notification.CATEGORY_CALL)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(contentIntent)

        if (Build.VERSION.SDK_INT >= 31) {
            val style = Notification.CallStyle.forIncomingCall(caller, declinePI, answerPI)
            builder.setStyle(style).addPerson(caller)
        } else {
            // Fallback: Plain actions for pre-Android 12 devices
            val answerAction = Notification.Action.Builder(
                getAppSmallIcon(),
                "Answer",
                answerPI
            ).build()
            val declineAction = Notification.Action.Builder(
                getAppSmallIcon(),
                "Decline",
                declinePI
            ).build()
            builder.addAction(answerAction).addAction(declineAction)
        }

        if (Build.VERSION.SDK_INT >= 29) {
            // Full-screen intent for incoming call UI wake-up (optional)
            builder.setFullScreenIntent(contentIntent, true)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+: keep visible until user acts
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder.build()
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(callId.hashCode(), notification)

        // If avatarUrl is HTTP(S), try to fetch asynchronously and update notification
        avatarUrl?.let { url ->
            try {
                val uri = Uri.parse(url)
                val scheme = uri.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") {
                    Thread {
                        val icon = loadIconFromUrl(url)
                        if (icon != null) {
                            try {
                                val pb = Person.Builder().setName(callerName).setIcon(icon)
                                val personWithIcon = pb.build()
                                val b2 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    Notification.Builder(context, CALL_NOTIF_CHANNEL_ID)
                                } else {
                                    Notification.Builder(context)
                                }
                                    .setSmallIcon(getAppSmallIcon())
                                    .setCategory(Notification.CATEGORY_CALL)
                                    .setAutoCancel(false)
                                    .setOngoing(true)
                                    .setContentIntent(contentIntent)
                                if (Build.VERSION.SDK_INT >= 31) {
                                    val style = Notification.CallStyle.forIncomingCall(personWithIcon, declinePI, answerPI)
                                    b2.setStyle(style).addPerson(personWithIcon)
                                } else {
                                    val answerAction = Notification.Action.Builder(getAppSmallIcon(), "Answer", answerPI).build()
                                    val declineAction = Notification.Action.Builder(getAppSmallIcon(), "Decline", declinePI).build()
                                    b2.addAction(answerAction).addAction(declineAction)
                                }
                                mgr.notify(callId.hashCode(), b2.build())
                            } catch (_: Exception) {}
                        }
                    }.start()
                }
            } catch (_: Exception) {}
        }
        // Auto-cancel after timeoutMs
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                mgr.cancel(callId.hashCode())
            } catch (_: Exception) {}
        }, timeoutMs)
    }

    private fun loadIconFromUrl(url: String): Icon? {
        return try {
            val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.instanceFollowRedirects = true
            conn.doInput = true
            conn.connect()
            val stream = conn.inputStream
            val bmp = android.graphics.BitmapFactory.decodeStream(stream)
            try { stream.close() } catch (_: Exception) {}
            try { conn.disconnect() } catch (_: Exception) {}
            if (bmp != null) Icon.createWithBitmap(bmp) else null
        } catch (_: Exception) {
            null
        }
    }

    private fun cancelCallNotification(callId: String?) {
        if (callId.isNullOrEmpty()) return
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.cancel(callId.hashCode())
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun getAppSmallIcon(): Icon {
        return try {
            Icon.createWithResource(this, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            Icon.createWithResource(this, android.R.drawable.sym_call_incoming)
        }
    }
}
