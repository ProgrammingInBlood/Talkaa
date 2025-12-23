import 'package:flutter/material.dart';
import '../../model/call_state.dart';

const _themeGreen = Color(0xFF659254);

/// Control buttons for an active call
class CallControls extends StatelessWidget {
  final bool isMuted;
  final bool isVideoEnabled;
  final bool isSpeakerOn;
  final CallType callType;
  final VoidCallback onMuteToggle;
  final VoidCallback onVideoToggle;
  final VoidCallback onSpeakerToggle;
  final VoidCallback onCameraSwitch;
  final VoidCallback onEndCall;

  const CallControls({
    super.key,
    required this.isMuted,
    required this.isVideoEnabled,
    required this.isSpeakerOn,
    required this.callType,
    required this.onMuteToggle,
    required this.onVideoToggle,
    required this.onSpeakerToggle,
    required this.onCameraSwitch,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute button
          _ControlButton(
            icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            label: isMuted ? 'Unmute' : 'Mute',
            isActive: isMuted,
            activeColor: Colors.red.shade400,
            onTap: onMuteToggle,
          ),
          
          // Video button (for video calls)
          if (callType == CallType.video)
            _ControlButton(
              icon: isVideoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: isVideoEnabled ? 'Video' : 'Video',
              isActive: !isVideoEnabled,
              activeColor: Colors.red.shade400,
              onTap: onVideoToggle,
            ),
          
          // Speaker button
          _ControlButton(
            icon: isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
            label: isSpeakerOn ? 'Speaker' : 'Earpiece',
            isActive: isSpeakerOn,
            activeColor: _themeGreen,
            onTap: onSpeakerToggle,
          ),
          
          // Camera switch button (for video calls)
          if (callType == CallType.video && isVideoEnabled)
            _ControlButton(
              icon: Icons.cameraswitch_rounded,
              label: 'Flip',
              isActive: false,
              onTap: onCameraSwitch,
            ),
          
          // End call button
          _EndCallButton(onTap: onEndCall),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isActive
        ? (activeColor ?? Colors.white)
        : Colors.white.withValues(alpha: 0.12);
    final iconColor = isActive
        ? Colors.white
        : Colors.white.withValues(alpha: 0.9);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: (activeColor ?? Colors.white).withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.call_end,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'End',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
