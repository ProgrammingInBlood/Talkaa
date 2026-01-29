import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import '../storage/signed_url_helper.dart';

final chatListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.read(supabaseProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];

  final raw = await client
      .from('chat_participants')
      .select('chat:chats(id, name, is_group, last_message_at, avatar_url), last_read_at, unread_count')
      .eq('user_id', userId)
      .order('last_read_at', ascending: false);

  final list = (raw as List)
      .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  // Client-side sort by chat.last_message_at desc when available
  list.sort((a, b) {
    final aChat = (a['chat'] as Map<String, dynamic>?) ?? const {};
    final bChat = (b['chat'] as Map<String, dynamic>?) ?? const {};
    final aStr = (aChat['last_message_at'] ?? '').toString();
    final bStr = (bChat['last_message_at'] ?? '').toString();
    final aDt = DateTime.tryParse(aStr);
    final bDt = DateTime.tryParse(bStr);
    if (aDt == null && bDt == null) return 0;
    if (aDt == null) return 1;
    if (bDt == null) return -1;
    return bDt.compareTo(aDt);
  });

  return list;
});

// Cached provider for DM title: other user's display name
final chatOtherUserNameProvider = FutureProvider.family<String?, String>((ref, chatId) async {
  final client = ref.read(supabaseProvider);
  final myId = client.auth.currentUser?.id;
  if (myId == null) return null;
  try {
    final rows = await client
        .from('chat_participants')
        .select('user:profiles(full_name, username)')
        .eq('chat_id', chatId)
        .neq('user_id', myId)
        .limit(1);
    final list = rows as List;
    if (list.isNotEmpty) {
      final userMap = list.first['user'] as Map<String, dynamic>?;
      final fullName = userMap?['full_name'] as String?;
      final username = userMap?['username'] as String?;
      final raw = (fullName != null && fullName.trim().isNotEmpty)
          ? fullName
          : (username ?? '');
      return raw.trim();
    }
  } catch (_) {}
  return null;
});

// Cached provider for other user's avatar url (DMs)
final chatOtherUserAvatarProvider = FutureProvider.family<String?, String>((ref, chatId) async {
  final client = ref.read(supabaseProvider);
  final myId = client.auth.currentUser?.id;
  if (myId == null) return null;
  try {
    final rows = await client
        .from('chat_participants')
        .select('user:profiles(avatar_url)')
        .eq('chat_id', chatId)
        .neq('user_id', myId)
        .limit(1);
    final list = rows as List;
    if (list.isNotEmpty) {
      final userMap = list.first['user'] as Map<String, dynamic>?;
      final avatarPath = userMap?['avatar_url'] as String?;
      if (avatarPath != null && avatarPath.trim().isNotEmpty) {
        // Generate signed URL for private avatar bucket
        return await SignedUrlHelper.getAvatarUrl(client, avatarPath.trim());
      }
    }
  } catch (_) {}
  return null;
});

// Cached provider for other user's ID (DMs)
final chatOtherUserIdProvider = FutureProvider.family<String?, String>((ref, chatId) async {
  final client = ref.read(supabaseProvider);
  final myId = client.auth.currentUser?.id;
  if (myId == null) return null;
  try {
    final rows = await client
        .from('chat_participants')
        .select('user_id')
        .eq('chat_id', chatId)
        .neq('user_id', myId)
        .limit(1);
    final list = rows as List;
    if (list.isNotEmpty) {
      return list.first['user_id'] as String?;
    }
  } catch (_) {}
  return null;
});

// Cached provider for group chat avatar url (signed)
final chatGroupAvatarProvider = FutureProvider.family<String?, String>((ref, chatId) async {
  final client = ref.read(supabaseProvider);
  try {
    final row = await client
        .from('chats')
        .select('avatar_url')
        .eq('id', chatId)
        .maybeSingle();
    final avatarPath = row?['avatar_url'] as String?;
    if (avatarPath != null && avatarPath.trim().isNotEmpty) {
      // Generate signed URL for avatar bucket
      return await SignedUrlHelper.getAvatarUrl(client, avatarPath.trim());
    }
  } catch (_) {}
  return null;
});

// Cached provider for last message preview content
final chatLastMessagePreviewProvider = FutureProvider.family<String, String>((ref, chatId) async {
  final client = ref.read(supabaseProvider);
  try {
    final rows = await client
        .from('messages')
        .select('content, created_at')
        .eq('chat_id', chatId)
        .order('created_at', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isNotEmpty) {
      final content = list.first['content'] as String?;
      return (content ?? '').trim();
    }
  } catch (_) {}
  return '';
});

/// Optimized realtime chat list provider with proper subscriptions
final realtimeChatListProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final client = ref.read(supabaseProvider);
  final userId = client.auth.currentUser?.id;
  
  final controller = StreamController<List<Map<String, dynamic>>>();
  
  Future<void> fetchAndEmit() async {
    if (userId == null) {
      controller.add([]);
      return;
    }
    
    try {
      // Use optimized database function
      final result = await client.rpc('get_user_chat_list', params: {
        'p_user_id': userId,
      });

      final list = (result as List)
          .map<Map<String, dynamic>>((row) {
            final map = Map<String, dynamic>.from(row as Map);
            // Restructure data to match existing widget expectations
            return {
              'chat': {
                'id': map['chat_id'],
                'name': map['chat_name'],
                'is_group': map['chat_is_group'],
                'last_message_at': map['chat_last_message_at'],
                'avatar_url': map['chat_avatar_url'],
              },
              'last_read_at': map['last_read_at'],
              'unread_count': map['unread_count'],
              'last_message_content': map['last_message_content'] ?? '',
              'last_message_type': map['last_message_type'],
            };
          })
          .toList();

      if (!controller.isClosed) {
        controller.add(list);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }
  
  // Initial fetch
  fetchAndEmit();
  
  // Subscribe to realtime changes with a single multiplexed channel
  final realtimeChannel = client
      .channel('user_chat_list_${userId ?? "unknown"}')
      // Listen to all message inserts (will trigger for any chat)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (_) => fetchAndEmit(),
      )
      // Listen to message updates (edits, deletes, read status)
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (_) => fetchAndEmit(),
      )
      // Listen to chat_participants updates for this user (unread count changes)
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chat_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId ?? '',
        ),
        callback: (_) => fetchAndEmit(),
      )
      // Listen to new chat participants (user added to new chat)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chat_participants',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId ?? '',
        ),
        callback: (_) => fetchAndEmit(),
      )
      // Listen to chat metadata changes (name, avatar, etc.)
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chats',
        callback: (_) => fetchAndEmit(),
      )
      .subscribe();
  
  ref.onDispose(() {
    realtimeChannel.unsubscribe();
    controller.close();
  });
  
  return controller.stream;
});

/// Mark messages as read when entering a conversation
Future<void> markMessagesAsRead(SupabaseClient client, String chatId) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) return;
  
  try {
    final now = DateTime.now().toUtc().toIso8601String();
    
    // Update messages read_at for messages not sent by current user
    await client
        .from('messages')
        .update({'read_at': now})
        .eq('chat_id', chatId)
        .neq('sender_id', userId)
        .isFilter('read_at', null);
    
    // Reset unread_count in chat_participants
    await client
        .from('chat_participants')
        .update({
          'unread_count': 0,
          'last_read_at': now,
        })
        .eq('chat_id', chatId)
        .eq('user_id', userId);
  } catch (e) {
    // Non-fatal error
  }
}