import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../storage/signed_url_helper.dart';

class SignedAvatar extends StatefulWidget {
  final String? avatarPath;
  final double radius;
  final SupabaseClient client;
  final Color? backgroundColor;
  final Widget? placeholder;

  const SignedAvatar({
    super.key,
    required this.avatarPath,
    required this.radius,
    required this.client,
    this.backgroundColor,
    this.placeholder,
  });

  @override
  State<SignedAvatar> createState() => _SignedAvatarState();
}

class _SignedAvatarState extends State<SignedAvatar> {
  String? _signedUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
  }

  @override
  void didUpdateWidget(SignedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) {
      _loadSignedUrl();
    }
  }

  Future<void> _loadSignedUrl() async {
    if (widget.avatarPath == null || widget.avatarPath!.isEmpty) {
      setState(() {
        _signedUrl = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = await SignedUrlHelper.getAvatarUrl(
        widget.client,
        widget.avatarPath!,
      );
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
    final cs = Theme.of(context).colorScheme;
    final defaultPlaceholder = CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor ?? cs.primaryContainer,
      child: Icon(
        Icons.person,
        size: widget.radius,
        color: cs.onPrimaryContainer,
      ),
    );

    if (_isLoading) {
      return widget.placeholder ?? defaultPlaceholder;
    }

    if (_signedUrl == null || _signedUrl!.isEmpty) {
      return widget.placeholder ?? defaultPlaceholder;
    }

    return CachedNetworkImage(
      imageUrl: _signedUrl!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: widget.radius,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => widget.placeholder ?? defaultPlaceholder,
      errorWidget: (context, url, error) => widget.placeholder ?? defaultPlaceholder,
    );
  }
}
