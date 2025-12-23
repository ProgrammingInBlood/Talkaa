import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ui/navigation.dart';
import '../notify/call_notifications.dart';
import 'call_service.dart';
import 'model/call_state.dart';
import 'ui/call_screen.dart';

/// Manages call navigation and overlay display.
/// Should be initialized at app startup to listen for incoming calls.
class CallManager {
  static CallManager? _instance;
  static CallManager get instance => _instance ??= CallManager._();
  
  CallManager._();
  
  StreamSubscription? _statusSubscription;
  StreamSubscription? _notificationActionSubscription;
  bool _isCallScreenShowing = false;
  
  /// Initialize the call manager with a WidgetRef
  void initialize(WidgetRef ref) {
    _statusSubscription?.cancel();
    _notificationActionSubscription?.cancel();
    
    // Listen to call status changes
    _statusSubscription = null; // We'll use listenManual instead
    ref.listenManual<CallController>(callServiceProvider, (previous, next) {
      _handleCallStatusChange(previous?.status, next.status, next, ref);
    });

    // Listen to notification actions to show call screen
    _notificationActionSubscription = CallNotifications.actions.listen((action) {
      _handleNotificationAction(action, ref);
    });
  }

  void _handleNotificationAction(CallAction action, WidgetRef ref) {
    debugPrint('CallManager: Notification action: ${action.action}');
    
    switch (action.action.toLowerCase()) {
      case 'incoming_call':
      case 'open':
        // Show call screen if not already showing and we have a call
        if (!_isCallScreenShowing) {
          // Wait a bit for call state to be set up
          Future.delayed(const Duration(milliseconds: 300), () {
            final ctrl = ref.read(callServiceProvider);
            // Show for any active call state (ringing, calling, connecting, connected)
            if ((ctrl.status.isRinging || ctrl.status.isActive) && !_isCallScreenShowing) {
              final isIncoming = ctrl.status == CallStatus.ringing;
              final userId = ctrl.currentUserId;
              _showCallScreen(
                controller: ctrl,
                calleeName: userId != null ? ctrl.currentCall?.remoteUserName(userId) : null,
                calleeAvatar: userId != null ? ctrl.currentCall?.remoteUserAvatar(userId) : null,
                callType: ctrl.callType,
                isIncoming: isIncoming,
              );
            }
          });
        }
        break;
      case 'answer':
        // Show call screen for answered call
        if (!_isCallScreenShowing) {
          Future.delayed(const Duration(milliseconds: 300), () {
            final ctrl = ref.read(callServiceProvider);
            if ((ctrl.status.isRinging || ctrl.status.isActive) && !_isCallScreenShowing) {
              final userId = ctrl.currentUserId;
              _showCallScreen(
                controller: ctrl,
                calleeName: userId != null ? ctrl.currentCall?.remoteUserName(userId) : null,
                calleeAvatar: userId != null ? ctrl.currentCall?.remoteUserAvatar(userId) : null,
                callType: ctrl.callType,
                isIncoming: true,
              );
            }
          });
        }
        break;
    }
  }
  
  void _handleCallStatusChange(
    CallStatus? oldStatus,
    CallStatus newStatus,
    CallController controller,
    WidgetRef ref,
  ) {
    // Show call screen for incoming calls
    if (newStatus == CallStatus.ringing && 
        oldStatus != CallStatus.ringing && 
        !_isCallScreenShowing) {
      _showCallScreen(
        controller: controller,
        isIncoming: true,
      );
    }
    
    // Close call screen when call ends
    if (newStatus == CallStatus.idle && _isCallScreenShowing) {
      _closeCallScreen();
    }
  }
  
  /// Show the call screen for an outgoing call
  Future<void> showOutgoingCallScreen({
    required String calleeId,
    required CallType callType,
    String? chatId,
    String? calleeName,
    String? calleeAvatar,
    required CallController controller,
  }) async {
    debugPrint('CallManager.showOutgoingCallScreen: calleeId=$calleeId, type=$callType, name=$calleeName');
    
    if (_isCallScreenShowing) {
      debugPrint('CallManager.showOutgoingCallScreen: Already showing call screen, returning');
      return;
    }
    
    // Show call screen FIRST (immediately) for responsive UX
    _showCallScreen(
      controller: controller,
      calleeName: calleeName,
      calleeAvatar: calleeAvatar,
      callType: callType,
      isIncoming: false,
    );
    
    // Then start the call in background
    await controller.startCall(
      calleeId: calleeId,
      type: callType,
      chatId: chatId,
      calleeName: calleeName,
      calleeAvatar: calleeAvatar,
    );
  }
  
  void _showCallScreen({
    required CallController controller,
    String? calleeName,
    String? calleeAvatar,
    CallType? callType,
    bool isIncoming = false,
  }) {
    debugPrint('CallManager._showCallScreen: isIncoming=$isIncoming, name=$calleeName, isShowing=$_isCallScreenShowing');
    
    final context = appNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('CallManager._showCallScreen: ERROR - appNavigatorKey.currentContext is NULL');
      return;
    }
    
    debugPrint('CallManager._showCallScreen: Navigating to CallScreen');
    
    _isCallScreenShowing = true;
    
    final userId = controller.currentUserId;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return CallScreen(
            callId: controller.currentCall?.id,
            callerName: calleeName ?? 
                (userId != null ? controller.currentCall?.remoteUserName(userId) : null),
            callerAvatar: calleeAvatar ?? 
                (userId != null ? controller.currentCall?.remoteUserAvatar(userId) : null),
            initialCallType: callType ?? controller.callType,
            isIncoming: isIncoming,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    ).then((_) {
      _isCallScreenShowing = false;
    });
  }
  
  void _closeCallScreen() {
    final context = appNavigatorKey.currentContext;
    if (context == null || !_isCallScreenShowing) return;
    
    Navigator.of(context).popUntil((route) {
      return route.settings.name != null || route.isFirst;
    });
    _isCallScreenShowing = false;
  }
  
  /// Handle an incoming call from push notification
  Future<void> handleIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    CallType? callType,
    required CallController controller,
  }) async {
    await controller.handleIncomingCall(
      callId: callId,
      callerName: callerName,
      callerAvatar: callerAvatar,
      callType: callType,
    );
    
    if (!_isCallScreenShowing) {
      _showCallScreen(
        controller: controller,
        calleeName: callerName,
        calleeAvatar: callerAvatar,
        callType: callType,
        isIncoming: true,
      );
    }
  }
  
  void dispose() {
    _statusSubscription?.cancel();
    _notificationActionSubscription?.cancel();
    _statusSubscription = null;
    _notificationActionSubscription = null;
  }
}
