package com.anonymous.Talka

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothHeadset
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Isolated Activity for call UI (incoming, outgoing, active calls).
 * - Uses cached "app_call_engine" Flutter engine with callMain entrypoint
 * - Supports Picture-in-Picture mode
 * - Excluded from recents, runs as separate task
 * - Shows on lockscreen
 */
class CallActivity : FlutterActivity() {

    companion object {
        // Must match CallForegroundService constants exactly
        const val EXTRA_CALL_ID = "extra_call_id"
        const val ACTION_ANSWER = "com.anonymous.talka.ACTION_ANSWER"
        const val ACTION_DECLINE = "com.anonymous.talka.ACTION_DECLINE"
        const val ACTION_OPEN = "com.anonymous.talka.ACTION_OPEN_CALL"
        const val ACTION_HANGUP = "com.anonymous.talka.ACTION_HANGUP"
    }

    private var pipChannel: MethodChannel? = null
    private var callNotifyChannel: MethodChannel? = null
    private var audioChannel: MethodChannel? = null
    private var pipEligible = false
    private var lastAspect = Rational(9, 16)
    private var pendingIntent: Intent? = null
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var bluetoothAdapter: BluetoothAdapter? = null

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        // Dump all intent extras for debugging
        android.util.Log.d("CallActivity", "=== provideFlutterEngine DEBUG ===")
        android.util.Log.d("CallActivity", "intent action: ${intent?.action}")
        android.util.Log.d("CallActivity", "ACTION_OPEN constant: $ACTION_OPEN")
        android.util.Log.d("CallActivity", "action matches: ${intent?.action == ACTION_OPEN}")
        android.util.Log.d("CallActivity", "EXTRA_CALL_ID key: $EXTRA_CALL_ID")
        intent?.extras?.let { extras ->
            android.util.Log.d("CallActivity", "All extras keys: ${extras.keySet()}")
            for (key in extras.keySet()) {
                android.util.Log.d("CallActivity", "  extra[$key] = ${extras.get(key)}")
            }
        } ?: android.util.Log.d("CallActivity", "Intent has NO extras bundle")
        
        // Store intent for later - push happens in configureFlutterEngine after channel is ready
        if (intent != null && (intent.action == ACTION_ANSWER || intent.action == ACTION_DECLINE || 
            intent.action == ACTION_OPEN || intent.action == ACTION_HANGUP)) {
            val callId = intent.getStringExtra(EXTRA_CALL_ID)
            android.util.Log.d("CallActivity", "provideFlutterEngine: storing intent action=${intent.action}, callId=$callId")
            pendingIntent = intent
        }
        
        return FlutterEngineCache.getInstance().get("app_call_engine")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        android.util.Log.d("CallActivity", "configureFlutterEngine: intent=${intent?.action}, callId=${intent?.getStringExtra(EXTRA_CALL_ID)}")

        // PiP channel
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.anonymous.talka/pip")
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val width = call.argument<Int>("width") ?: 9
                        val height = call.argument<Int>("height") ?: 16
                        lastAspect = Rational(width, height)
                        pipEligible = true
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(lastAspect)
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setPipEligible" -> {
                    pipEligible = call.argument<Boolean>("eligible") ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Call notify channel for actions
        callNotifyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.anonymous.talka/call_notify")
        callNotifyChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startCallForegroundService" -> {
                    val callerName = call.argument<String>("callerName") ?: "Call"
                    val callId = call.argument<String>("callId") ?: ""
                    val avatarUrl = call.argument<String>("avatarUrl")
                    val style = call.argument<String>("style") ?: "incoming"
                    startCallForegroundService(callerName, callId, avatarUrl, style)
                    result.success(null)
                }
                "stopCallForegroundService" -> {
                    stopCallForegroundService()
                    result.success(null)
                }
                "endCallNotification" -> {
                    val callId = call.argument<String>("callId") ?: ""
                    endCallNotification(callId)
                    result.success(null)
                }
                "closeCallActivity" -> {
                    android.util.Log.d("CallActivity", "closeCallActivity called - finishing activity")
                    result.success(null)
                    finish()
                }
                "getPendingCallAction" -> {
                    android.util.Log.d("CallActivity", "getPendingCallAction called")
                    
                    // First check if there's a stored pending intent
                    val storedIntent = pendingIntent
                    android.util.Log.d("CallActivity", "storedIntent: ${storedIntent?.action}, callId: ${storedIntent?.getStringExtra(EXTRA_CALL_ID)}")
                    
                    if (storedIntent != null) {
                        val intentAction = storedIntent.action
                        val intentCallId = storedIntent.getStringExtra(EXTRA_CALL_ID)
                        
                        if (intentAction != null && intentCallId != null) {
                            val action = when (intentAction) {
                                ACTION_ANSWER -> "answer"
                                ACTION_DECLINE -> "decline"
                                ACTION_OPEN -> "open"
                                ACTION_HANGUP -> "hangup"
                                else -> null
                            }
                            if (action != null) {
                                android.util.Log.d("CallActivity", "Returning stored intent: action=$action, callId=$intentCallId")
                                // Clear pending intent after reading
                                pendingIntent = null
                                result.success(mapOf("action" to action, "callId" to intentCallId))
                                return@setMethodCallHandler
                            }
                        }
                    }
                    
                    // Otherwise check SharedPreferences
                    val pending = CallFlutterBridge.getPendingAction(this@CallActivity)
                    android.util.Log.d("CallActivity", "SharedPreferences pending: ${pending?.first}, callId: ${pending?.second}")
                    
                    if (pending != null) {
                        CallFlutterBridge.clearPendingAction(this@CallActivity)
                        result.success(mapOf("action" to pending.first, "callId" to pending.second))
                    } else {
                        android.util.Log.d("CallActivity", "No pending action found, returning null")
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Push action to Flutter (only via call_notify channel to avoid duplicates)
        if (intent != null && (intent.action == ACTION_ANSWER || intent.action == ACTION_DECLINE || 
            intent.action == ACTION_OPEN || intent.action == ACTION_HANGUP)) {
            val callId = intent.getStringExtra(EXTRA_CALL_ID)
            android.util.Log.d("CallActivity", "configureFlutterEngine: pushing action=${intent.action}, callId=$callId")
            pendingIntent = intent
            
            if (callId != null) {
                val action = when (intent.action) {
                    ACTION_ANSWER -> "answer"
                    ACTION_DECLINE -> "decline"
                    ACTION_OPEN -> "open"
                    ACTION_HANGUP -> "hangup"
                    else -> null
                }
                if (action != null) {
                    android.util.Log.d("CallActivity", "PUSHING action to Flutter: action=$action, callId=$callId")
                    callNotifyChannel?.invokeMethod("callAction", mapOf("action" to action, "callId" to callId))
                }
            }
        }
        
        // Audio device management channel
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.anonymous.talka/audio_devices")
        setupBluetoothProfile()
        audioChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioDevices" -> {
                    result.success(getAvailableAudioDevices())
                }
                "selectAudioDevice" -> {
                    val deviceId = call.argument<String>("deviceId")
                    if (deviceId != null) {
                        selectAudioDevice(deviceId)
                        result.success(true)
                    } else {
                        result.error("bad_args", "deviceId is required", null)
                    }
                }
                "getCurrentAudioDevice" -> {
                    result.success(getCurrentAudioDevice())
                }
                "requestBluetoothPermission" -> {
                    // CallActivity cannot request permissions directly, return current state
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == 
                            PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ensure screen turns on for calls
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        
        // Store new intent for later retrieval
        if (intent.action == ACTION_ANSWER || intent.action == ACTION_DECLINE || 
            intent.action == ACTION_OPEN || intent.action == ACTION_HANGUP) {
            pendingIntent = intent
            
            // Also invoke immediately if channel is ready
            val action = intent.action
            val callId = intent.getStringExtra(EXTRA_CALL_ID)
            if (action != null && callId != null) {
                val actionStr = when (action) {
                    ACTION_ANSWER -> "answer"
                    ACTION_DECLINE -> "decline"
                    ACTION_OPEN -> "open"
                    ACTION_HANGUP -> "hangup"
                    else -> return
                }
                callNotifyChannel?.invokeMethod("callAction", mapOf("action" to actionStr, "callId" to callId))
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

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("pipModeChanged", mapOf("active" to isInPictureInPictureMode))
    }

    private fun startCallForegroundService(callerName: String, callId: String, avatarUrl: String?, style: String) {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            putExtra(CallForegroundService.EXTRA_CALLER_NAME, callerName)
            putExtra(CallForegroundService.EXTRA_CALL_ID, callId)
            putExtra(CallForegroundService.EXTRA_AVATAR_URL, avatarUrl)
            putExtra(CallForegroundService.EXTRA_STYLE, style)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopCallForegroundService() {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun endCallNotification(callId: String) {
        val mgr = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        // Cancel by call ID hash
        mgr.cancel(callId.hashCode())
        // Also cancel by fixed NOTIFICATION_ID
        mgr.cancel(CallForegroundService.NOTIFICATION_ID)
        // Stop the foreground service
        stopCallForegroundService()
    }
    
    // Audio device management
    private fun setupBluetoothProfile() {
        try {
            bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            bluetoothAdapter?.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    if (profile == BluetoothProfile.HEADSET) {
                        bluetoothHeadset = proxy as? BluetoothHeadset
                    }
                }
                override fun onServiceDisconnected(profile: Int) {
                    if (profile == BluetoothProfile.HEADSET) {
                        bluetoothHeadset = null
                    }
                }
            }, BluetoothProfile.HEADSET)
        } catch (e: Exception) {
            // Bluetooth not available or permission denied
        }
    }
    
    private fun getAvailableAudioDevices(): List<Map<String, String>> {
        val devices = mutableListOf<Map<String, String>>()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // Always add earpiece and speaker
        devices.add(mapOf("id" to "earpiece", "name" to "Phone Earpiece", "type" to "earpiece"))
        devices.add(mapOf("id" to "speaker", "name" to "Speaker", "type" to "speaker"))
        
        // Check for wired headset
        if (audioManager.isWiredHeadsetOn) {
            devices.add(mapOf("id" to "wired", "name" to "Wired Headset", "type" to "wired"))
        }
        
        // Check for Bluetooth devices
        try {
            val hasBluetoothPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == 
                    PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            
            if (hasBluetoothPermission) {
                if (audioManager.isBluetoothScoAvailableOffCall || audioManager.isBluetoothA2dpOn) {
                    val connectedDevices = bluetoothHeadset?.connectedDevices
                    if (!connectedDevices.isNullOrEmpty()) {
                        for (device in connectedDevices) {
                            val name = try { device.name ?: "Bluetooth Device" } catch (_: Exception) { "Bluetooth Device" }
                            devices.add(mapOf(
                                "id" to "bluetooth_${device.address}",
                                "name" to name,
                                "type" to "bluetooth"
                            ))
                        }
                    } else if (audioManager.isBluetoothScoOn || audioManager.isBluetoothA2dpOn) {
                        devices.add(mapOf("id" to "bluetooth", "name" to "Bluetooth", "type" to "bluetooth"))
                    }
                }
            }
        } catch (e: Exception) {
            // Bluetooth permission denied or not available
        }
        
        return devices
    }
    
    private fun selectAudioDevice(deviceId: String) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        when {
            deviceId == "speaker" -> {
                audioManager.isSpeakerphoneOn = true
                audioManager.isBluetoothScoOn = false
                try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
            }
            deviceId == "earpiece" -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.isBluetoothScoOn = false
                try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
            }
            deviceId == "wired" -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.isBluetoothScoOn = false
                try { audioManager.stopBluetoothSco() } catch (_: Exception) {}
            }
            deviceId.startsWith("bluetooth") -> {
                audioManager.isSpeakerphoneOn = false
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                try {
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                } catch (e: Exception) {
                    // Bluetooth SCO not available
                }
            }
        }
    }
    
    private fun getCurrentAudioDevice(): String {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return when {
            audioManager.isBluetoothScoOn -> "bluetooth"
            audioManager.isSpeakerphoneOn -> "speaker"
            audioManager.isWiredHeadsetOn -> "wired"
            else -> "earpiece"
        }
    }

    override fun onDestroy() {
        pipChannel?.setMethodCallHandler(null)
        callNotifyChannel?.setMethodCallHandler(null)
        audioChannel?.setMethodCallHandler(null)
        super.onDestroy()
    }
}
