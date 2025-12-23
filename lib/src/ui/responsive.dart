import 'package:flutter/widgets.dart';

class ResponsiveCenter extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const ResponsiveCenter({super.key, this.maxWidth = 720, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= maxWidth) return child;
        final horizontal = (width - maxWidth) / 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: child,
        );
      },
    );
  }
}