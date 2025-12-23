import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallNotifications {
  static const MethodChannel _channel = MethodChannel('com.anonymous.talka/call_notify');
  // Bridge channel used by native headless engine to forward actions
  static const MethodChannel _bridgeChannel = MethodChannel('app.call');
  static final StreamController<CallAction> _actions = StreamController<CallAction>.broadcast();

  static Stream<CallAction> get actions => _actions.stream;

  // Allow programmatic emission of call actions (fallback notifications)
  static void emitAction(CallAction action) {
    _actions.add(action);
  }

  // Start native foreground service for call-style notifications (Android)
  static Future<void> startForegroundService({
    required String callerName,
    required String callId,
    String? avatarUrl,
    int timeoutMs = 30000,
    String style = 'incoming', // incoming | outgoing | ongoing
  }) async {
    try {
      debugPrint('CallNotifications.startForegroundService style=$style callId=$callId name=$callerName');
      await _channel.invokeMethod('startCallForegroundService', {
        'callerName': callerName,
        'callId': callId,
        'avatarUrl': avatarUrl,
        'timeoutMs': timeoutMs,
        'style': style,
      });
      debugPrint('CallNotifications.startForegroundService invoked for callId=$callId');
    } catch (_) {}
  }

  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopCallForegroundService');
    } catch (_) {}
  }

  static void init() {
    // Listen for native actions from notification (answer/decline/open/hangup)
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'callAction') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final String action = args['action']?.toString() ?? '';
        final String? callId = args['callId']?.toString();
        _actions.add(CallAction(action: action, callId: callId));
      }
    });

    // Also listen to headless-native bridge actions
    _bridgeChannel.setMethodCallHandler((MethodCall call) async {
      try {
        if (call.method == 'call.onAction') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final String action = (args['action']?.toString() ?? '').toLowerCase();
          final String? callId = args['callId']?.toString();
          if (action.isNotEmpty) {
            _actions.add(CallAction(action: action, callId: callId));
          }
        } else if (call.method == 'call.onTimeout') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final String? callId = args['callId']?.toString();
          // Propagate timeout as an action for higher-level handling
          _actions.add(CallAction(action: 'timeout', callId: callId));
        }
      } catch (_) {}
    });
    // Fetch any pending startup action (cold start from notification tap)
    // is now handled explicitly by CallService after it binds listeners via
    // getPendingStartupAction(), to avoid dropping actions before subscribe.
  }

  static Future<CallAction?> getPendingStartupAction() async {
    try {
      final Map<dynamic, dynamic>? pending =
          await _channel.invokeMethod('getPendingCallAction');
      if (pending == null) return null;
      final args = Map<String, dynamic>.from(pending);
      final String action = (args['action']?.toString() ?? '').toLowerCase();
      final String? callId = args['callId']?.toString();
      if (action.isEmpty || callId == null || callId.isEmpty) return null;
      return CallAction(action: action, callId: callId);
    } catch (_) {
      return null;
    }
  }

  static Future<void> endCallNotification(String callId) async {
    try {
      await _channel.invokeMethod('endCallNotification', {
        'callId': callId,
      });
    } catch (e) {
      debugPrint('endCallNotification invoke failed: $e');
    }
  }
}

class CallAction {
  final String action;
  final String? callId;
  CallAction({required this.action, this.callId});
}