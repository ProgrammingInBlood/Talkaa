package com.anonymous.Talka

import android.app.Application
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
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put("app_call_engine", flutterEngine)
        CallFlutterBridge.init(flutterEngine, applicationContext)
    }
}