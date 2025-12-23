import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Animated avatar for call screens
class CallAvatar extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final double size;
  final bool isRinging;

  const CallAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 120,
    this.isRinging = false,
  });

  @override
  State<CallAvatar> createState() => _CallAvatarState();
}

class _CallAvatarState extends State<CallAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isRinging) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(CallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRinging && !oldWidget.isRinging) {
      _controller.repeat();
    } else if (!widget.isRinging && oldWidget.isRinging) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getInitials() {
    final parts = widget.name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.5,
      height: widget.size * 1.5,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple effect when ringing
          if (widget.isRinging) ...[
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: widget.size * _scaleAnimation.value,
                  height: widget.size * _scaleAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: _opacityAnimation.value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final delayed = (_controller.value + 0.3) % 1.0;
                return Container(
                  width: widget.size * (1.0 + (delayed * 0.5)),
                  height: widget.size * (1.0 + (delayed * 0.5)),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6 * (1.0 - delayed)),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          ],
          
          // Avatar
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667eea).withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.avatarUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _buildInitials(),
                      errorWidget: (context, url, error) => _buildInitials(),
                    )
                  : _buildInitials(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitials() {
    return Center(
      child: Text(
        _getInitials(),
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
