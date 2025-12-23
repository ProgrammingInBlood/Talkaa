import 'package:flutter/material.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex; // 0: Dashboard, 1: Calls, 2: Settings, 3: More
  final void Function(int index)? onTabSelected;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color colorFor(int idx) => idx == currentIndex ? cs.primary : cs.onSurface;

    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(Icons.dashboard_outlined, color: colorFor(0)),
              onPressed: () => onTabSelected?.call(0),
            ),
            IconButton(
              icon: Icon(Icons.call_outlined, color: colorFor(1)),
              onPressed: () => onTabSelected?.call(1),
            ),
            IconButton(
              icon: Icon(Icons.settings_outlined, color: colorFor(2)),
              onPressed: () => onTabSelected?.call(2),
            ),
            IconButton(
              icon: Icon(Icons.more_horiz, color: colorFor(3)),
              onPressed: () => onTabSelected?.call(3),
            ),
          ],
        ),
      ),
    );
  }
}