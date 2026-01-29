import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignedUrlHelper {
  static final Map<String, _CachedUrl> _cache = {};
  static const int _cacheValiditySeconds = 1800; // 30 minutes
  static const int _signedUrlValiditySeconds = 3600; // 1 hour

  /// Get a signed URL for a storage path
  /// Supports avatar, stories, and chat-files buckets
  /// Returns the original URL if it's already a full URL or if signing fails
  static Future<String> getSignedUrl(
    SupabaseClient client,
    String pathOrUrl, {
    required String bucket,
  }) async {
    if (pathOrUrl.isEmpty) return pathOrUrl;

    // If it's already a signed URL or public URL, extract the path
    String path = pathOrUrl;
    if (pathOrUrl.contains('supabase.co/storage')) {
      path = _extractPath(pathOrUrl, bucket);
    }

    // Check cache first
    final cacheKey = '$bucket:$path';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.url;
    }

    try {
      final signedUrl = await client.storage
          .from(bucket)
          .createSignedUrl(path, _signedUrlValiditySeconds);

      // Cache the result
      _cache[cacheKey] = _CachedUrl(signedUrl);
      return signedUrl;
    } catch (e) {
      debugPrint('SignedUrlHelper: Error getting signed URL for $bucket/$path: $e');
      // Return empty string on error - don't return path as it's not a valid URL
      return '';
    }
  }

  /// Extract storage path from a full URL
  static String _extractPath(String url, String bucket) {
    try {
      // Remove query parameters
      final cleanUrl = url.split('?').first;
      
      // Find the bucket name in the URL and extract everything after it
      final bucketPattern = '/$bucket/';
      final bucketIndex = cleanUrl.indexOf(bucketPattern);
      if (bucketIndex != -1) {
        return cleanUrl.substring(bucketIndex + bucketPattern.length);
      }
      
      return url;
    } catch (e) {
      return url;
    }
  }

  /// Get signed URL for avatar
  static Future<String> getAvatarUrl(SupabaseClient client, String pathOrUrl) {
    return getSignedUrl(client, pathOrUrl, bucket: 'avatar');
  }

  /// Get signed URL for story media
  static Future<String> getStoryUrl(SupabaseClient client, String pathOrUrl) {
    return getSignedUrl(client, pathOrUrl, bucket: 'stories');
  }

  /// Get signed URL for chat file
  static Future<String> getChatFileUrl(SupabaseClient client, String pathOrUrl) {
    return getSignedUrl(client, pathOrUrl, bucket: 'chat-files');
  }

  /// Clear the URL cache (useful when user logs out)
  static void clearCache() {
    _cache.clear();
  }

  /// Check if a string is a valid URL for NetworkImage
  static bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('http://') || url.startsWith('https://');
  }
}

class _CachedUrl {
  final String url;
  final DateTime createdAt;

  _CachedUrl(this.url) : createdAt = DateTime.now();

  bool get isExpired {
    final age = DateTime.now().difference(createdAt).inSeconds;
    return age > SignedUrlHelper._cacheValiditySeconds;
  }
}
