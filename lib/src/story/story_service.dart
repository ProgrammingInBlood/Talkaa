import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import '../storage/signed_url_helper.dart';

class StoryService {
  final SupabaseClient client;
  StoryService(this.client);

  static final storyServiceProvider = Provider<StoryService>((ref) {
    final client = ref.read(supabaseProvider);
    return StoryService(client);
  });

  Future<void> createStory(WidgetRef ref, {required String mediaUrl, String mediaType = 'image'}) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    await client.from('stories').insert({
      'user_id': uid,
      'media_url': mediaUrl,
      'media_type': mediaType,
      // Use UTC time to match database timezone
      'created_at': DateTime.now().toUtc().toIso8601String(),
      // expires_at default is set in DB (now + 24h)
    });
  }

  Future<List<Map<String, dynamic>>> fetchActiveStories() async {
    // RLS restricts results to: self and conversation starters, and only not expired
    final rows = await client
        .from('stories')
        .select('id, user_id, media_url, media_type, created_at, expires_at, user:profiles(full_name, username, avatar_url)')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    
    // Refresh signed URLs for each story (handles old public URLs and expired signed URLs)
    final stories = List<Map<String, dynamic>>.from(rows as List);
    for (int i = 0; i < stories.length; i++) {
      final story = Map<String, dynamic>.from(stories[i]);
      final mediaUrl = story['media_url'] as String?;
      if (mediaUrl != null) {
        story['media_url'] = await _getSignedUrl(mediaUrl);
      }
      // Also sign the user's avatar_url
      final user = story['user'] as Map<String, dynamic>?;
      if (user != null) {
        final userCopy = Map<String, dynamic>.from(user);
        final avatarPath = userCopy['avatar_url'] as String?;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          userCopy['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
        }
        story['user'] = userCopy;
      }
      stories[i] = story;
    }
    return stories;
  }

  /// Generate fresh signed URL for story media
  Future<String> _getSignedUrl(String pathOrUrl) async {
    // Import the helper inline to avoid circular dependencies
    try {
      String path = pathOrUrl;
      // Extract path from full URL if needed
      if (pathOrUrl.contains('supabase.co/storage')) {
        final cleanUrl = pathOrUrl.split('?').first;
        final bucketPattern = '/stories/';
        final bucketIndex = cleanUrl.indexOf(bucketPattern);
        if (bucketIndex != -1) {
          path = cleanUrl.substring(bucketIndex + bucketPattern.length);
        }
      }
      // Generate fresh signed URL valid for 1 hour
      return await client.storage.from('stories').createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('Error generating signed URL: $e');
      return pathOrUrl;
    }
  }

  Future<bool> hasActiveStoryForSelf() async {
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) return false;
      final res = await client
          .from('stories')
          .select('id')
          .eq('user_id', uid)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .limit(1);
      final list = (res as List);
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> markViewed({required String storyId}) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await client.from('story_views').insert({
        'story_id': storyId,
        'viewer_id': uid,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      // ignore duplicate view errors or RLS rejections
      debugPrint('story view insert: $e');
    }
  }

  Future<Set<String>> fetchViewedIdsFor(List<String> storyIds) async {
    try {
      if (storyIds.isEmpty) return <String>{};
      final uid = client.auth.currentUser?.id;
      if (uid == null) return <String>{};

      final response = await client
          .from('story_views')
          .select('story_id')
          .eq('viewer_id', uid);

      final ids = <String>{};
      for (final row in (response as List)) {
        final sid = row['story_id']?.toString();
        if (sid != null && storyIds.contains(sid)) ids.add(sid);
      }
      return ids;
    } catch (_) {
      return <String>{};
    }
  }

  Future<bool> deleteStory(String storyId) async {
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) return false;
      // Delete the story row owned by the current user
      final res = await client
          .from('stories')
          .delete()
          .eq('id', storyId)
          .eq('user_id', uid);
      // Supabase Dart returns deleted rows array; treat non-empty as success
      return res is List ? res.isNotEmpty : true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchStoryViewers(String storyId) async {
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) return [];

      // Only story owner should see viewers
      final story = await client
          .from('stories')
          .select('user_id')
          .eq('id', storyId)
          .maybeSingle();
      
      if (story == null || story['user_id'] != uid) {
        return [];
      }

      final response = await client
          .from('story_views')
          .select('viewer_id, viewed_at, viewer:profiles(full_name, username, avatar_url)')
          .eq('story_id', storyId)
          .order('viewed_at', ascending: false);

      // Sign avatar URLs for viewers
      final viewers = List<Map<String, dynamic>>.from(response as List);
      for (int i = 0; i < viewers.length; i++) {
        final viewer = Map<String, dynamic>.from(viewers[i]);
        final viewerProfile = viewer['viewer'] as Map<String, dynamic>?;
        if (viewerProfile != null) {
          final profileCopy = Map<String, dynamic>.from(viewerProfile);
          final avatarPath = profileCopy['avatar_url'] as String?;
          if (avatarPath != null && avatarPath.isNotEmpty) {
            profileCopy['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
          }
          viewer['viewer'] = profileCopy;
        }
        viewers[i] = viewer;
      }
      return viewers;
    } catch (e) {
      debugPrint('Error fetching story viewers: $e');
      return [];
    }
  }

  Future<int> getStoryViewCount(String storyId) async {
    try {
      final response = await client
          .from('story_views')
          .select('id')
          .eq('story_id', storyId);
      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }
}