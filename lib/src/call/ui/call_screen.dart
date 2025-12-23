import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../call_service.dart';
import '../model/call_state.dart';
import 'widgets/call_controls.dart';
import 'widgets/call_avatar.dart';
import 'widgets/call_timer.dart';
import 'widgets/incoming_call_controls.dart';
import 'widgets/pip_video.dart';

/// Main call screen that adapts to all call states
class CallScreen extends ConsumerStatefulWidget {
  final String? callId;
  final String? callerName;
  final String? callerAvatar;
  final CallType? initialCallType;
  final bool isIncoming;

  const CallScreen({
    super.key,
    this.callId,
    this.callerName,
    this.callerAvatar,
    this.initialCallType,
    this.isIncoming = false,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  static const _pipChannel = MethodChannel('com.anonymous.talka/pip');
  
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  bool _showControls = true;
  Timer? _hideControlsTimer;
  StreamSubscription? _localStreamSub;
  StreamSubscription? _remoteStreamSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initRenderers();
    _setupPipListener();
    
    // Auto-hide controls after 5 seconds
    _startHideControlsTimer();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    final controller = ref.read(callServiceProvider);
    
    // Set initial streams if available
    if (controller.currentLocalStream != null) {
      _localRenderer.srcObject = controller.currentLocalStream;
    }
    if (controller.currentRemoteStream != null) {
      _remoteRenderer.srcObject = controller.currentRemoteStream;
    }
    
    // Listen for stream updates
    _localStreamSub = controller.localStream.listen((stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    });
    
    _remoteStreamSub = controller.remoteStream.listen((stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    });
  }

  void _setupPipListener() {
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        // Handle PiP mode change - could update UI if needed
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && ref.read(callServiceProvider).status == CallStatus.connected) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  Future<void> _enterPip() async {
    try {
      final controller = ref.read(callServiceProvider);
      final isVideo = controller.callType == CallType.video;
      
      await _pipChannel.invokeMethod('enterPip', {
        'width': isVideo ? 9 : 1,
        'height': isVideo ? 16 : 1,
      });
    } catch (e) {
      debugPrint('CallScreen: Error entering PiP: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(callServiceProvider);
    
    if (state == AppLifecycleState.paused && controller.status.isActive) {
      // Try to enter PiP when app goes to background
      _enterPip();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(callServiceProvider);
    
    // Use ListenableBuilder to react to ChangeNotifier updates
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final status = controller.status;
        final call = controller.currentCall;
        final currentUserId = controller.currentUserId;
        
        // Get remote user info - only lookup if we have both call and userId
        final remoteName = (call != null && currentUserId != null)
            ? (call.remoteUserName(currentUserId) ?? widget.callerName ?? 'Unknown')
            : (widget.callerName ?? 'Unknown');
        final remoteAvatar = (call != null && currentUserId != null)
            ? (call.remoteUserAvatar(currentUserId) ?? widget.callerAvatar)
            : widget.callerAvatar;
        
        final isVideo = controller.callType == CallType.video;
        final isConnected = status == CallStatus.connected;

        // Handle call ended
        if (status == CallStatus.idle && Navigator.canPop(context)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          });
        }

        return PopScope(
      canPop: !status.isActive && !status.isRinging,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && status.isActive) {
          _enterPip();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: GestureDetector(
          onTap: isConnected ? _toggleControls : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background - Video or Gradient
              if (isVideo && isConnected)
                _buildVideoBackground()
              else
                _buildGradientBackground(),

              // Main content
              SafeArea(
                child: Column(
                  children: [
                    // Top bar
                    _buildTopBar(context, status, remoteName),
                    
                    const Spacer(),
                    
                    // Center content
                    if (!isVideo || !isConnected)
                      _buildCenterContent(
                        remoteName,
                        remoteAvatar,
                        status,
                        controller,
                      ),
                    
                    const Spacer(),
                    
                    // Controls
                    if (_showControls || !isConnected)
                      _buildControls(context, controller, status),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),

              // Local video (PiP style)
              if (isVideo && isConnected && controller.isVideoEnabled)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 80,
                  right: 16,
                  child: PipVideo(
                    renderer: _localRenderer,
                    mirror: controller.isFrontCamera,
                    onTap: () async {
                      await controller.switchCamera();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
        );
      },
    );
  }

  Widget _buildVideoBackground() {
    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      mirror: false,
    );
  }

  Widget _buildGradientBackground() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [
                  Color(0xFF1A2E1A),
                  Color(0xFF162116),
                  Color(0xFF0F1A0F),
                ]
              : const [
                  Color(0xFF2D4A2D),
                  Color(0xFF1E3A1E),
                  Color(0xFF153015),
                ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, CallStatus status, String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back/Minimize button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () {
              if (status.isActive) {
                _enterPip();
              } else if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
          ),
          
          const Spacer(),
          
          // Call quality indicator
          if (status == CallStatus.connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.signal_cellular_alt, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'HD',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            ),
          
          const Spacer(),
          
          // More options
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // TODO: Show more options
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCenterContent(
    String name,
    String? avatar,
    CallStatus status,
    CallController controller,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar
        CallAvatar(
          name: name,
          avatarUrl: avatar,
          size: 120,
          isRinging: status.isRinging,
        ),
        
        const SizedBox(height: 24),
        
        // Name
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w600,
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Status or Timer
        if (status == CallStatus.connected)
          CallTimer(seconds: controller.callDurationSeconds)
        else
          Text(
            status.displayName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
        
        // Call type indicator
        if (status.isRinging)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller.callType == CallType.video
                      ? Icons.videocam
                      : Icons.call,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${controller.callType.displayName} Call',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    CallController controller,
    CallStatus status,
  ) {
    // Incoming call - show accept/decline
    if (status == CallStatus.ringing && widget.isIncoming) {
      return IncomingCallControls(
        onAccept: () => controller.acceptCall(),
        onDecline: () => controller.declineCall(),
        callType: controller.callType,
      );
    }
    
    // Outgoing call - show cancel
    if (status == CallStatus.calling) {
      return _buildCancelButton(controller);
    }
    
    // Active call - show full controls
    if (status.isActive) {
      return CallControls(
        isMuted: controller.isMuted,
        isVideoEnabled: controller.isVideoEnabled,
        isSpeakerOn: controller.isSpeakerOn,
        callType: controller.callType,
        onMuteToggle: () => controller.toggleMute(),
        onVideoToggle: () => controller.toggleVideo(),
        onSpeakerToggle: () => controller.toggleSpeaker(),
        onCameraSwitch: () => controller.switchCamera(),
        onEndCall: () => controller.endCall(),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildCancelButton(CallController controller) {
    return Center(
      child: GestureDetector(
        onTap: () => controller.endCall(),
        child: Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.call_end,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}
