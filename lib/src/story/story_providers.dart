import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import 'story_service.dart';

final hasMyStoryProvider = FutureProvider<bool>((ref) async {
  final svc = ref.read(StoryService.storyServiceProvider);
  return await svc.hasActiveStoryForSelf();
});

final storiesWithViewedProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.read(StoryService.storyServiceProvider);
  final stories = await svc.fetchActiveStories();
  final ids = stories.map((e) => e['id'].toString()).toList();
  final viewedIds = await svc.fetchViewedIdsFor(ids);
  return stories.map((s) {
    final sid = s['id'].toString();
    final m = Map<String, dynamic>.from(s);
    m['hasViewed'] = viewedIds.contains(sid);
    return m;
  }).toList();
});

/// Realtime stories provider that refreshes on INSERT/DELETE events
final realtimeStoriesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final client = ref.read(supabaseProvider);
  final svc = ref.read(StoryService.storyServiceProvider);
  
  final controller = StreamController<List<Map<String, dynamic>>>();
  
  Future<void> fetchAndEmit() async {
    try {
      final stories = await svc.fetchActiveStories();
      final ids = stories.map((e) => e['id'].toString()).toList();
      final viewedIds = await svc.fetchViewedIdsFor(ids);
      final result = stories.map((s) {
        final sid = s['id'].toString();
        final m = Map<String, dynamic>.from(s);
        m['hasViewed'] = viewedIds.contains(sid);
        return m;
      }).toList();
      if (!controller.isClosed) {
        controller.add(result);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }
  
  // Initial fetch
  fetchAndEmit();
  
  // Subscribe to realtime changes on stories table
  final channel = client
      .channel('stories_realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'stories',
        callback: (_) => fetchAndEmit(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'stories',
        callback: (_) => fetchAndEmit(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'stories',
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();
  
  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });
  
  return controller.stream;
});

/// Realtime provider for checking if current user has an active story
final realtimeHasMyStoryProvider = StreamProvider<bool>((ref) {
  final client = ref.read(supabaseProvider);
  final svc = ref.read(StoryService.storyServiceProvider);
  final uid = client.auth.currentUser?.id;
  
  final controller = StreamController<bool>();
  
  Future<void> fetchAndEmit() async {
    try {
      final hasStory = await svc.hasActiveStoryForSelf();
      if (!controller.isClosed) {
        controller.add(hasStory);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.add(false);
      }
    }
  }
  
  // Initial fetch
  fetchAndEmit();
  
  if (uid != null) {
    // Subscribe to realtime changes on stories table filtered by user_id
    final channel = client
        .channel('my_stories_realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => fetchAndEmit(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'stories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => fetchAndEmit(),
        )
        .subscribe();
    
    ref.onDispose(() {
      channel.unsubscribe();
      controller.close();
    });
  } else {
    ref.onDispose(() {
      controller.close();
    });
  }
  
  return controller.stream;
});