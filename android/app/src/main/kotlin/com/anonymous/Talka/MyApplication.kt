package com.anonymous.Talka

import android.app.Application
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

class MyApplication : Application() {
    lateinit var flutterEngine: FlutterEngine

    override fun onCreate() {
        super.onCreate()
        // Create and cache a FlutterEngine so method channels are available headlessly
        flutterEngine = FlutterEngine(this)
        try {
            GeneratedPluginRegistrant.registerWith(flutterEngine)
        } catch (_: Throwable) {
            // Safe-guard in case plugin registrant is not found; engine still runs
        }
        
        // Use callMain entrypoint for call-only Flutter engine
        val flutterLoader = FlutterInjector.instance().flutterLoader()
        flutterLoader.startInitialization(this)
        flutterLoader.ensureInitializationComplete(this, null)
        
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                flutterLoader.findAppBundlePath(),
                "callMain"
            )
        )
        FlutterEngineCache.getInstance().put("app_call_engine", flutterEngine)
        CallFlutterBridge.init(flutterEngine, applicationContext)
    }
}