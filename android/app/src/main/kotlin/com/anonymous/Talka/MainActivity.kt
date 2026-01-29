package com.anonymous.Talka

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Main Activity for the app.
 * All call-related logic is handled by CallActivity.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize the Flutter bridge for native-Flutter communication
        CallFlutterBridge.init(flutterEngine, this)
        
        // Initialize auto-start helper for OEM-specific permissions
        AutoStartHelper.init(flutterEngine, this)
    }
}
