import 'dart:ui';
import 'package:flutter/material.dart';

// Bubble grouping position within a sequence
enum BubblePosition { single, first, middle, last }

class ChatBubble extends StatelessWidget {
  final Widget child;
  final bool isMine;
  final BubblePosition position;
  
  const ChatBubble({
    super.key,
    required this.child,
    required this.isMine,
    this.position = BubblePosition.single,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = _bubbleRadius(isMine, position);
    final margin = switch (position) {
      BubblePosition.single => const EdgeInsets.symmetric(vertical: 6),
      BubblePosition.first => const EdgeInsets.only(top: 6, bottom: 2),
      BubblePosition.middle => const EdgeInsets.symmetric(vertical: 2),
      BubblePosition.last => const EdgeInsets.only(top: 2, bottom: 6),
    };
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: isMine
            ? cs.primary
            : (Theme.of(context).brightness == Brightness.dark
                ? cs.surfaceContainerHighest
                : Colors.white),
        borderRadius: radius,
        border: Border.all(
            color: isMine
                ? cs.primary
                : (Theme.of(context).brightness == Brightness.dark
                    ? cs.onSurface.withValues(alpha: 0.10)
                    : Colors.black12),
            width: 1),
        boxShadow: isMine
            ? [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.20)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: child,
    );
  }

  BorderRadius _bubbleRadius(bool mine, BubblePosition pos) {
    const base = 18.0;
    const tight = 6.0; // inside corners when grouped
    if (mine) {
      switch (pos) {
        case BubblePosition.single:
          return BorderRadius.circular(base);
        case BubblePosition.first:
          return const BorderRadius.only(
            topLeft: Radius.circular(base),
            bottomLeft: Radius.circular(base),
            topRight: Radius.circular(base),
            bottomRight: Radius.circular(tight),
          );
        case BubblePosition.middle:
          return const BorderRadius.only(
            topLeft: Radius.circular(base),
            bottomLeft: Radius.circular(base),
            topRight: Radius.circular(tight),
            bottomRight: Radius.circular(tight),
          );
        case BubblePosition.last:
          return const BorderRadius.only(
            topLeft: Radius.circular(base),
            bottomLeft: Radius.circular(base),
            topRight: Radius.circular(tight),
            bottomRight: Radius.circular(base),
          );
      }
    } else {
      switch (pos) {
        case BubblePosition.single:
          return BorderRadius.circular(base);
        case BubblePosition.first:
          return const BorderRadius.only(
            topRight: Radius.circular(base),
            bottomRight: Radius.circular(base),
            topLeft: Radius.circular(base),
            bottomLeft: Radius.circular(tight),
          );
        case BubblePosition.middle:
          return const BorderRadius.only(
            topRight: Radius.circular(base),
            bottomRight: Radius.circular(base),
            topLeft: Radius.circular(tight),
            bottomLeft: Radius.circular(tight),
          );
        case BubblePosition.last:
          return const BorderRadius.only(
            topRight: Radius.circular(base),
            bottomRight: Radius.circular(base),
            topLeft: Radius.circular(tight),
            bottomLeft: Radius.circular(base),
          );
      }
    }
  }
}

class GlassBubble extends StatelessWidget {
  final Widget child;
  final bool isMine;
  
  const GlassBubble({
    super.key,
    required this.child,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // Frosted glass blur of the gradient background
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(),
            ),
            // Semi-transparent layer with subtle border and shadow
            Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: (isMine ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.12)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}