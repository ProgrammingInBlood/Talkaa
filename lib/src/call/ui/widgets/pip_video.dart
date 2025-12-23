import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Picture-in-Picture style video view for local camera preview
class PipVideo extends StatefulWidget {
  final RTCVideoRenderer renderer;
  final bool mirror;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const PipVideo({
    super.key,
    required this.renderer,
    this.mirror = true,
    this.onTap,
    this.width = 100,
    this.height = 140,
  });

  @override
  State<PipVideo> createState() => _PipVideoState();
}

class _PipVideoState extends State<PipVideo> {
  Offset _position = Offset.zero;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanUpdate: (details) {
        setState(() {
          _position += details.delta;
        });
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      child: Transform.translate(
        offset: _position,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isDragging 
                  ? Colors.white 
                  : Colors.white.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RTCVideoView(
                  widget.renderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: widget.mirror,
                ),
                
                // Camera switch indicator
                if (widget.onTap != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.cameraswitch,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
