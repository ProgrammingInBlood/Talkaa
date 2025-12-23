import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../model/call_state.dart';

/// Service for managing Picture-in-Picture mode on Android
class PipService {
  static const MethodChannel _channel = MethodChannel('com.anonymous.talka/pip');
  
  static final _pipModeController = StreamController<bool>.broadcast();
  static bool _isInitialized = false;
  static bool _isPipMode = false;

  /// Stream of PiP mode changes
  static Stream<bool> get pipModeStream => _pipModeController.stream;

  /// Current PiP mode state
  static bool get isInPipMode => _isPipMode;

  /// Initialize PiP service
  static void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        final active = call.arguments['active'] as bool;
        _isPipMode = active;
        _pipModeController.add(active);
        debugPrint('PipService: PiP mode changed to $active');
      }
    });
  }

  /// Request to enter PiP mode
  static Future<bool> enterPip({
    CallType callType = CallType.video,
    int? width,
    int? height,
  }) async {
    try {
      // Default aspect ratio based on call type
      final w = width ?? (callType == CallType.video ? 9 : 1);
      final h = height ?? (callType == CallType.video ? 16 : 1);

      final result = await _channel.invokeMethod<bool>('enterPip', {
        'width': w,
        'height': h,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('PipService: Error entering PiP: $e');
      return false;
    }
  }

  /// Set PiP eligibility (auto-enter PiP when leaving app)
  static Future<void> setPipEligible({
    required bool enabled,
    CallType callType = CallType.video,
    int? width,
    int? height,
  }) async {
    try {
      final w = width ?? (callType == CallType.video ? 9 : 1);
      final h = height ?? (callType == CallType.video ? 16 : 1);

      await _channel.invokeMethod('setPipEligible', {
        'enabled': enabled,
        'width': w,
        'height': h,
      });
      debugPrint('PipService: PiP eligibility set to $enabled');
    } catch (e) {
      debugPrint('PipService: Error setting PiP eligibility: $e');
    }
  }

  /// Check if currently in PiP mode
  static Future<bool> checkPipMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInPip');
      _isPipMode = result ?? false;
      return _isPipMode;
    } catch (e) {
      debugPrint('PipService: Error checking PiP mode: $e');
      return false;
    }
  }

  /// Dispose resources
  static void dispose() {
    _pipModeController.close();
    _isInitialized = false;
  }
}
