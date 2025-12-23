import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ImageViewerPage extends StatelessWidget {
  final String url;
  final String? heroTag;

  const ImageViewerPage({super.key, required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: SizedBox.expand(
          child: ClipRect(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: heroTag != null
                        ? Hero(
                            tag: heroTag!,
                            child: CachedNetworkImage(
                              imageUrl: url,
                              placeholder: (context, _) => const CircularProgressIndicator(color: Colors.white70),
                              errorWidget: (context, _, __) => const Icon(Icons.broken_image, color: Colors.white70, size: 64),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: url,
                            placeholder: (context, _) => const CircularProgressIndicator(color: Colors.white70),
                            errorWidget: (context, _, __) => const Icon(Icons.broken_image, color: Colors.white70, size: 64),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}