import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';

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
      'created_at': DateTime.now().toIso8601String(),
      // expires_at default is set in DB (now + 24h)
    });
  }

  Future<List<Map<String, dynamic>>> fetchActiveStories() async {
    // RLS restricts results to: self and conversation starters, and only not expired
    final rows = await client
        .from('stories')
        .select('id, user_id, media_url, media_type, created_at, expires_at, user:profiles(full_name, username, avatar_url)')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<bool> hasActiveStoryForSelf() async {
    try {
      final uid = client.auth.currentUser?.id;
      if (uid == null) return false;
      final res = await client
          .from('stories')
          .select('id')
          .eq('user_id', uid)
          .gt('expires_at', DateTime.now().toIso8601String())
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
        'viewed_at': DateTime.now().toIso8601String(),
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
}