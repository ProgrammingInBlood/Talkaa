import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);


// Heartbeat: upsert last_seen every minute while app active
final heartbeatProvider = Provider.autoDispose<void>((ref) {
  final client = ref.read(supabaseProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return;

  Future<void> beat() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      debugPrint('DEBUG HEARTBEAT: Updating profiles for $uid at $now');
      await client.from('profiles').update({
        'last_seen': now,
      }).eq('id', uid);
      debugPrint('DEBUG HEARTBEAT: Successfully updated profiles for $uid');
    } catch (e) {
      debugPrint('DEBUG HEARTBEAT: Error updating profiles for $uid: $e');
    }
  }

  // Immediate beat on start
  debugPrint('DEBUG HEARTBEAT: Starting heartbeat for user $uid');
  beat();
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    debugPrint('DEBUG HEARTBEAT: Timer triggered for user $uid');
    beat();
  });

  ref.onDispose(() {
    timer.cancel();
  });
});

// Stream the last_seen of a specific user via Realtime Postgres Changes
final lastSeenProvider = StreamProvider.autoDispose.family<DateTime?, String>((ref, userId) {
  final client = ref.read(supabaseProvider);
  if (userId.isEmpty) return Stream.value(null);

  final controller = StreamController<DateTime?>();
  late final RealtimeChannel channel;


  debugPrint('DEBUG LAST_SEEN: Subscribing to last_seen changes for user $userId');

  Future<void> loadInitial() async {
    try {
      final row = await client
          .from('profiles')
          .select('last_seen')
          .eq('id', userId)
          .limit(1)
          .maybeSingle();
      final ts = row?['last_seen']?.toString();
      controller.add(ts != null ? DateTime.tryParse(ts) : null);
    } catch (_) {
      controller.add(null);
    }
  }

  channel = client
      .channel('public:profiles')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'profiles',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (payload) {
          final ts = payload.newRecord['last_seen']?.toString();
          controller.add(ts != null ? DateTime.tryParse(ts) : null);
        },
      )
      .subscribe((status, _) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await loadInitial();
        }
      });

  ref.onDispose(() async {
    try {
      await channel.unsubscribe();
    } catch (_) {}
    await controller.close();
  });

  return controller.stream;
});