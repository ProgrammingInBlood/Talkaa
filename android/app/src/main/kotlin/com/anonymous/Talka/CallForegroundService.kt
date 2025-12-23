package com.anonymous.Talka

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.graphics.BitmapFactory
import java.net.HttpURLConnection
import java.net.URL
import android.os.PowerManager
import android.app.KeyguardManager
import android.view.WindowManager

class CallForegroundService : Service() {
    companion object {
        const val EXTRA_CALLER_NAME = "extra_caller_name"
        const val EXTRA_CALL_ID = "extra_call_id"
        const val EXTRA_AVATAR_URL = "extra_avatar_url"
        const val EXTRA_STYLE = "style" // incoming | outgoing | ongoing
        const val CALL_NOTIF_CHANNEL_ID = "call_notifications" // incoming
        const val CALL_STATUS_CHANNEL_ID = "call_status" // outgoing/ongoing (no heads-up, no sound)
        const val ACTION_ANSWER = "com.anonymous.talka.ACTION_ANSWER"
        const val ACTION_DECLINE = "com.anonymous.talka.ACTION_DECLINE"
        const val ACTION_OPEN = "com.anonymous.talka.ACTION_OPEN_CALL"
        const val ACTION_HANGUP = "com.anonymous.talka.ACTION_HANGUP"
    }

    // Added state to manage notification updates and timeout
    private var currentCallId: String? = null
    private var startedForeground = false
    private var lastNotificationId: Int = 0
    private var timeoutHandler: Handler? = null
    private var timeoutRunnable: Runnable? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callerName = intent?.getStringExtra(EXTRA_CALLER_NAME) ?: "Incoming call"
        val callId = intent?.getStringExtra(EXTRA_CALL_ID) ?: System.currentTimeMillis().toString()
        val avatarUrl = intent?.getStringExtra(EXTRA_AVATAR_URL)
        val styleParam = (intent?.getStringExtra(EXTRA_STYLE) ?: "incoming").lowercase()
        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

        // Choose appropriate channel by style
        if (styleParam == "incoming") {
            ensureCallNotificationChannel(this)
        } else {
            ensureCallStatusChannel(this)
        }
        // Acquire appropriate wake lock based on call state
        if (styleParam == "incoming") {
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                // Use FULL_WAKE_LOCK to turn on screen for incoming calls
                @Suppress("DEPRECATION")
                wakeLock = pm.newWakeLock(
                    PowerManager.FULL_WAKE_LOCK or 
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or 
                    PowerManager.ON_AFTER_RELEASE,
                    "Talka:IncomingCall"
                )
                wakeLock?.acquire((intent?.getLongExtra("timeoutMs", 30000L) ?: 30000L) + 5000L)
                
                // Also turn screen on via KeyguardManager for newer Android versions
                turnScreenOn()
            } catch (_: Exception) {}
        } else if (styleParam == "ongoing") {
            // For ongoing calls, use a lighter wake lock to prevent deep sleep during call
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Talka:OngoingCall")
                wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes, will be renewed as needed
            } catch (_: Exception) {}
        } else {
            try { wakeLock?.release() } catch (_: Exception) {}
            wakeLock = null
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            1000 + callId.hashCode(),
            Intent(this, MainActivity::class.java).apply {
                action = ACTION_OPEN
                putExtra(EXTRA_CALL_ID, callId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            pendingIntentFlags()
        )
        // Replaced actions to use broadcasts to work in background
        val answerPI = PendingIntent.getBroadcast(
            this,
            2000 + callId.hashCode(),
            Intent(this, CallActionReceiver::class.java).apply {
                action = ACTION_ANSWER
                putExtra(EXTRA_CALL_ID, callId)
                putExtra("name", callerName)
            },
            pendingIntentFlags()
        )
        val declinePI = PendingIntent.getBroadcast(
            this,
            3000 + callId.hashCode(),
            Intent(this, CallActionReceiver::class.java).apply {
                action = ACTION_DECLINE
                putExtra(EXTRA_CALL_ID, callId)
            },
            pendingIntentFlags()
        )
        val hangupPI = PendingIntent.getBroadcast(
            this,
            4000 + callId.hashCode(),
            Intent(this, CallActionReceiver::class.java).apply {
                action = ACTION_HANGUP
                putExtra(EXTRA_CALL_ID, callId)
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
            val channelId = if (styleParam == "incoming") CALL_NOTIF_CHANNEL_ID else CALL_STATUS_CHANNEL_ID
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }
            .setSmallIcon(getAppSmallIcon())
            .setCategory(Notification.CATEGORY_CALL)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        // Add content text to differentiate call states
        when (styleParam) {
            "incoming" -> builder.setContentText("Incoming call")
            "outgoing" -> builder.setContentText("Calling...")
            "ongoing" -> {
                // Use chronometer for ongoing calls to show duration
                builder.setUsesChronometer(true)
                builder.setWhen(System.currentTimeMillis())
                builder.setContentText("Ongoing call")
            }
        }

        // Sound/vibrate for incoming only on pre-O
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O && styleParam == "incoming") {
            builder.setSound(ringtoneUri)
            builder.setPriority(Notification.PRIORITY_MAX)
            builder.setDefaults(Notification.DEFAULT_ALL)
        }

        if (Build.VERSION.SDK_INT >= 31) {
            when (styleParam) {
                "incoming" -> {
                    val style = Notification.CallStyle.forIncomingCall(caller, declinePI, answerPI)
                    builder.setStyle(style).addPerson(caller)
                }
                "outgoing" -> {
                    // Use forOngoingCall for outgoing (no forOutgoingCall in Android API)
                    // but with "Calling..." content text set above
                    val style = Notification.CallStyle.forOngoingCall(caller, hangupPI)
                    builder.setStyle(style).addPerson(caller)
                }
                "ongoing" -> {
                    val style = Notification.CallStyle.forOngoingCall(caller, hangupPI)
                    builder.setStyle(style).addPerson(caller)
                }
                else -> {
                    val hangupAction = Notification.Action.Builder(
                        getAppSmallIcon(),
                        "Hang up",
                        hangupPI
                    ).build()
                    builder.addAction(hangupAction)
                }
            }
        } else {
            // Fallback actions for older devices
            when (styleParam) {
                "incoming" -> {
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
                else -> { // outgoing/ongoing
                    val hangupAction = Notification.Action.Builder(
                        getAppSmallIcon(),
                        "Hang up",
                        hangupPI
                    ).build()
                    builder.addAction(hangupAction)
                }
            }
        }

        // Full-screen incoming only
        if (Build.VERSION.SDK_INT >= 29 && styleParam == "incoming") {
            builder.setFullScreenIntent(contentIntent, true)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder.build()

        // Update ongoing via NotificationManager to keep same ID; start foreground only for initial
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        lastNotificationId = callId.hashCode()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val isIncoming = (styleParam == "incoming")
                var types = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                if (!isIncoming) {
                    // On connected/dialing, include audio and camera usage. Avoid mediaProjection.
                    types = types or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    types = types or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                }
                if (styleParam == "ongoing" && startedForeground && currentCallId == callId) {
                    nm.notify(lastNotificationId, notification)
                } else {
                    startForeground(lastNotificationId, notification, types)
                    startedForeground = true
                    currentCallId = callId
                    // For incoming calls, proactively bring up the UI for better responsiveness
                    if (styleParam == "incoming") {
                        try {
                            // Handle locked screen scenarios
                            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                            val open = Intent(this, MainActivity::class.java).apply {
                                action = ACTION_OPEN
                                putExtra(EXTRA_CALL_ID, callId)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                
                                // Critical flags for locked screen
                                if (keyguardManager.isKeyguardLocked) {
                                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                                    addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                                    addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                                }
                            }
                            startActivity(open)
                        } catch (_: Exception) {}
                    }
                }
            } else {
                if (styleParam == "ongoing" && startedForeground && currentCallId == callId) {
                    nm.notify(lastNotificationId, notification)
                } else {
                    startForeground(lastNotificationId, notification)
                    startedForeground = true
                    currentCallId = callId
                    if (styleParam == "incoming") {
                        try {
                            // Handle locked screen scenarios
                            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                            val open = Intent(this, MainActivity::class.java).apply {
                                action = ACTION_OPEN
                                putExtra(EXTRA_CALL_ID, callId)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                
                                // Critical flags for locked screen
                                if (keyguardManager.isKeyguardLocked) {
                                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                                    addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                                    addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                                }
                            }
                            startActivity(open)
                        } catch (_: Exception) {}
                    }
                }
            }
        } catch (_: Exception) {
            if (styleParam == "ongoing" && startedForeground && currentCallId == callId) {
                nm.notify(lastNotificationId, notification)
            } else {
                startForeground(lastNotificationId, notification)
                startedForeground = true
                currentCallId = callId
            }
        }

        // Attempt to update avatar icon from HTTP URL asynchronously
        avatarUrl?.let { url ->
            try {
                val uri = Uri.parse(url)
                val scheme = uri.scheme?.lowercase()
                if (scheme == "http" || scheme == "https") {
                    Thread {
                        val bmp = loadBitmapFromUrl(url)
                        if (bmp != null) {
                            try {
                                val personWithIcon = Person.Builder().setName(callerName).setIcon(Icon.createWithBitmap(bmp)).build()
                                val b2 = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    val channelId = if (styleParam == "incoming") CALL_NOTIF_CHANNEL_ID else CALL_STATUS_CHANNEL_ID
                                    Notification.Builder(this, channelId)
                                } else {
                                    Notification.Builder(this)
                                }
                                    .setSmallIcon(getAppSmallIcon())
                                    .setCategory(Notification.CATEGORY_CALL)
                                    .setAutoCancel(false)
                                    .setOngoing(true)
                                    .setContentIntent(contentIntent)
                                    .setVisibility(Notification.VISIBILITY_PUBLIC)
                                // Add content text differentiation
                                when (styleParam) {
                                    "incoming" -> b2.setContentText("Incoming call")
                                    "outgoing" -> b2.setContentText("Calling...")
                                    "ongoing" -> {
                                        b2.setUsesChronometer(true)
                                        b2.setContentText("Ongoing call")
                                    }
                                }
                                if (Build.VERSION.SDK_INT >= 31) {
                                    when (styleParam) {
                                        "incoming" -> {
                                            val style = Notification.CallStyle.forIncomingCall(personWithIcon, declinePI, answerPI)
                                            b2.setStyle(style).addPerson(personWithIcon)
                                        }
                                        "outgoing" -> {
                                            val style = Notification.CallStyle.forOngoingCall(personWithIcon, hangupPI)
                                            b2.setStyle(style).addPerson(personWithIcon)
                                        }
                                        "ongoing" -> {
                                            val style = Notification.CallStyle.forOngoingCall(personWithIcon, hangupPI)
                                            b2.setStyle(style).addPerson(personWithIcon)
                                        }
                                        else -> {
                                            val hangupAction = Notification.Action.Builder(
                                                getAppSmallIcon(),
                                                "Hang up",
                                                hangupPI
                                            ).build()
                                            b2.addAction(hangupAction)
                                        }
                                    }
                                } else {
                                    // Fallback actions for older devices
                                    when (styleParam) {
                                        "incoming" -> {
                                            val answerAction = Notification.Action.Builder(getAppSmallIcon(), "Answer", answerPI).build()
                                            val declineAction = Notification.Action.Builder(getAppSmallIcon(), "Decline", declinePI).build()
                                            b2.addAction(answerAction).addAction(declineAction)
                                        }
                                        else -> {
                                            val hangupAction = Notification.Action.Builder(getAppSmallIcon(), "Hang up", hangupPI).build()
                                            b2.addAction(hangupAction)
                                        }
                                    }
                                }
                                val notif2 = b2.build()
                                nm.notify(lastNotificationId, notif2)
                            } catch (_: Exception) {}
                        }
                    }.start()
                }
            } catch (_: Exception) {}
        }

        // Manage ringing timeout: schedule for incoming, cancel when transitioning
        if (styleParam == "incoming") {
            val timeoutMs = intent?.getLongExtra("timeoutMs", 30000L) ?: 30000L
            timeoutHandler = Handler(Looper.getMainLooper())
            timeoutRunnable = Runnable {
                try {
                    CallFlutterBridge.notifyTimeout(callId)
                } catch (_: Exception) {}
                try {
                    stopForeground(true)
                } catch (_: Exception) {}
                stopSelf()
            }
            timeoutHandler?.postDelayed(timeoutRunnable!!, timeoutMs)
        } else {
            timeoutRunnable?.let { timeoutHandler?.removeCallbacks(it) }
            timeoutRunnable = null
            timeoutHandler = null
        }

        return START_STICKY
    }

    override fun onDestroy() {
        // Clean up all resources
        try {
            timeoutRunnable?.let { timeoutHandler?.removeCallbacks(it) }
            timeoutRunnable = null
            timeoutHandler = null
        } catch (_: Exception) {}
        
        try {
            wakeLock?.release()
            wakeLock = null
        } catch (_: Exception) {}
        
        try {
            stopForeground(true)
        } catch (_: Exception) {}
        
        super.onDestroy()
    }

    private fun ensureCallNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(CALL_NOTIF_CHANNEL_ID, "Call notifications", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Incoming call alerts and call status"
            channel.setShowBadge(false)
            channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            // Ensure ringtone plays via channel for incoming
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            channel.setSound(ringtoneUri, attrs)
            channel.enableVibration(true)
            channel.vibrationPattern = longArrayOf(0, 300, 150, 300)
            channel.setBypassDnd(true)
            mgr.createNotificationChannel(channel)
        } catch (_: Exception) {}
    }

    private fun ensureCallStatusChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            var channel = mgr.getNotificationChannel(CALL_STATUS_CHANNEL_ID)
            if (channel == null) {
                channel = NotificationChannel(CALL_STATUS_CHANNEL_ID, "Call status", NotificationManager.IMPORTANCE_DEFAULT)
                channel.description = "Outgoing/ongoing call status"
                channel.setShowBadge(false)
                channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                // No sound or vibration for outgoing/ongoing status
                channel.setSound(null, null)
                channel.enableVibration(false)
                channel.setBypassDnd(false)
                mgr.createNotificationChannel(channel)
            }
        } catch (_: Exception) {}
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun loadBitmapFromUrl(url: String): android.graphics.Bitmap? {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.instanceFollowRedirects = true
            conn.doInput = true
            conn.connect()
            val stream = conn.inputStream
            val bmp = BitmapFactory.decodeStream(stream)
            try { stream.close() } catch (_: Exception) {}
            try { conn.disconnect() } catch (_: Exception) {}
            bmp
        } catch (_: Exception) {
            null
        }
    }

    private fun getAppSmallIcon(): Icon {
        return try {
            Icon.createWithResource(this, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            Icon.createWithResource(this, android.R.drawable.sym_call_incoming)
        }
    }
    
    private fun turnScreenOn() {
        try {
            // For Android 8.0+ use Activity flags, but for service we need PowerManager
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                @Suppress("DEPRECATION")
                val screenLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "Talka:ScreenOn"
                )
                screenLock.acquire(5000L)
                screenLock.release()
            }
        } catch (_: Exception) {}
    }
}