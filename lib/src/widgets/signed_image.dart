import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../storage/signed_url_helper.dart';

enum SignedImageBucket { avatar, stories, chatFiles }

class SignedImage extends StatefulWidget {
  final String? imagePath;
  final SupabaseClient client;
  final SignedImageBucket bucket;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const SignedImage({
    super.key,
    required this.imagePath,
    required this.client,
    required this.bucket,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  String? _signedUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
  }

  @override
  void didUpdateWidget(SignedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadSignedUrl();
    }
  }

  Future<void> _loadSignedUrl() async {
    if (widget.imagePath == null || widget.imagePath!.isEmpty) {
      setState(() {
        _signedUrl = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      String url;
      switch (widget.bucket) {
        case SignedImageBucket.avatar:
          url = await SignedUrlHelper.getAvatarUrl(widget.client, widget.imagePath!);
          break;
        case SignedImageBucket.stories:
          url = await SignedUrlHelper.getStoryUrl(widget.client, widget.imagePath!);
          break;
        case SignedImageBucket.chatFiles:
          url = await SignedUrlHelper.getChatFileUrl(widget.client, widget.imagePath!);
          break;
      }
      if (mounted) {
        setState(() {
          _signedUrl = url;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signedUrl = null;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPlaceholder = Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );

    final defaultError = Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Icon(
        Icons.broken_image,
        color: Theme.of(context).colorScheme.onErrorContainer,
      ),
    );

    if (_isLoading) {
      return widget.placeholder ?? defaultPlaceholder;
    }

    if (_signedUrl == null || _signedUrl!.isEmpty) {
      return widget.errorWidget ?? defaultError;
    }

    return CachedNetworkImage(
      imageUrl: _signedUrl!,
      fit: widget.fit ?? BoxFit.cover,
      width: widget.width,
      height: widget.height,
      placeholder: (context, url) => widget.placeholder ?? defaultPlaceholder,
      errorWidget: (context, url, error) => widget.errorWidget ?? defaultError,
    );
  }
}
