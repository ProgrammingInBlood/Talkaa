import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../watch_party/watch_party_service.dart';
import '../providers.dart';
import 'watch_party_room_screen.dart';
import 'watch_party_host_flow.dart';
import 'instagram_reels_room.dart';

enum StreamingService {
  youtube('YouTube', 'https://m.youtube.com', Color(0xFFFF0000), Icons.play_circle_filled),
  instagram('Instagram Reels', 'https://www.instagram.com/reels/', Color(0xFFE4405F), Icons.video_collection_rounded);

  final String name;
  final String url;
  final Color color;
  final IconData icon;
  
  const StreamingService(this.name, this.url, this.color, this.icon);
}

class WatchPartyPage extends ConsumerStatefulWidget {
  const WatchPartyPage({super.key});

  @override
  ConsumerState<WatchPartyPage> createState() => _WatchPartyPageState();
}

class _WatchPartyPageState extends ConsumerState<WatchPartyPage> {
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Use Supabase Realtime stream for auto-updating room list
    final roomsAsync = ref.watch(publicRoomsStreamProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Party'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Invalidate stream to force refresh
          ref.invalidate(publicRoomsStreamProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Host Room Button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildHostButton(context, cs),
              ),
            ),
            
            // Public Rooms Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.public_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Public Rooms',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            
            // Rooms List
            roomsAsync.when(
              data: (rooms) {
                if (rooms.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _buildEmptyState(cs),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildRoomCard(context, cs, rooms[index]),
                      childCount: rooms.length,
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Error loading rooms: $e'),
                )),
              ),
            ),
            
            // Beta Badge
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_rounded, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Beta Feature',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHostButton(BuildContext context, ColorScheme cs) {
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _startHostFlow,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Host a Room',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start watching with friends',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: cs.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.live_tv_rounded,
            size: 64,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No active rooms',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to host a watch party!',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRoomCard(BuildContext context, ColorScheme cs, WatchPartyRoom room) {
    final serviceColor = _getServiceColor(room.service);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _joinRoom(room),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                // Service icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getServiceIcon(room.service), color: serviceColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.videoTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (room.hostAvatarUrl != null && room.hostAvatarUrl!.isNotEmpty)
                            CircleAvatar(
                              radius: 10,
                              backgroundImage: NetworkImage(room.hostAvatarUrl!),
                            )
                          else
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.person, size: 12, color: cs.primary),
                            ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Hosted by ${room.hostName ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Join',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Color _getServiceColor(String service) {
    switch (service.toLowerCase()) {
      case 'youtube':
        return const Color(0xFFFF0000);
      case 'instagram':
        return const Color(0xFFE4405F);
      case 'netflix':
        return const Color(0xFFE50914);
      case 'prime':
        return const Color(0xFF00A8E1);
      default:
        return const Color(0xFFFF0000);
    }
  }
  
  IconData _getServiceIcon(String service) {
    switch (service.toLowerCase()) {
      case 'youtube':
        return Icons.play_circle_filled;
      case 'instagram':
        return Icons.video_collection_rounded;
      case 'netflix':
        return Icons.movie_rounded;
      case 'prime':
        return Icons.video_library_rounded;
      default:
        return Icons.play_circle_filled;
    }
  }
  
  void _startHostFlow() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WatchPartyHostFlow()),
    );
  }
  
  void _joinRoom(WatchPartyRoom room) {
    final client = ref.read(supabaseProvider);
    final currentUserId = client.auth.currentUser?.id;
    final isHost = currentUserId == room.hostId;
    
    // Route to appropriate room based on service
    if (room.service.toLowerCase() == 'instagram') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InstagramReelsRoom(room: room, isHost: isHost),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WatchPartyRoomScreen(room: room)),
      );
    }
  }
}
