import 'package:flutter/material.dart';
import '../../model/call_state.dart';

const _themeGreen = Color(0xFF659254);

/// Controls for incoming call - Accept/Decline buttons with swipe gestures
class IncomingCallControls extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final CallType callType;

  const IncomingCallControls({
    super.key,
    required this.onAccept,
    required this.onDecline,
    required this.callType,
  });

  @override
  State<IncomingCallControls> createState() => _IncomingCallControlsState();
}

class _IncomingCallControlsState extends State<IncomingCallControls>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _ringController;
  late Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ringController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _ringAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Decline button
          _ActionButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            color: Colors.red.shade500,
            onTap: widget.onDecline,
          ),
          
          // Accept button with pulse and ring animation
          SizedBox(
            width: 120, // Fixed size to contain the animation
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Ripple rings - contained within the SizedBox
                AnimatedBuilder(
                  animation: _ringAnimation,
                  builder: (context, child) {
                    final size = 72 + (_ringAnimation.value * 40);
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _themeGreen.withValues(alpha: 0.6 * (1 - _ringAnimation.value)),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),
                // Button with pulse
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: _ActionButton(
                    icon: widget.callType == CallType.video
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    label: 'Accept',
                    color: _themeGreen,
                    onTap: widget.onAccept,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
