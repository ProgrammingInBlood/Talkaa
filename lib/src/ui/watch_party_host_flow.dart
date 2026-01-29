import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../watch_party/watch_party_service.dart';
import 'watch_party_page.dart';
import 'watch_party_room_screen.dart';
import 'youtube_browser_page.dart';
import 'youtube_player_page.dart';
import 'watch_party_webview_page.dart';
import 'instagram_reels_room.dart';

class WatchPartyHostFlow extends ConsumerStatefulWidget {
  final WatchPartyRoom? existingRoom;
  
  const WatchPartyHostFlow({super.key, this.existingRoom});

  @override
  ConsumerState<WatchPartyHostFlow> createState() => _WatchPartyHostFlowState();
}

class _WatchPartyHostFlowState extends ConsumerState<WatchPartyHostFlow> {
  bool _isCreatingRoom = false;
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isChangingVideo = widget.existingRoom != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isChangingVideo ? 'Change Video' : 'Choose Service'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary.withValues(alpha: 0.2),
                          cs.tertiary.withValues(alpha: 0.2),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isChangingVideo ? Icons.swap_horiz_rounded : Icons.live_tv_rounded,
                      size: 40,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isChangingVideo ? 'Select New Video' : 'Select a Service',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isChangingVideo 
                        ? 'Choose a new video to watch'
                        : 'Pick where you want to watch from',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Service cards
            ...StreamingService.values.map((service) => 
              _buildServiceCard(context, cs, service),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildServiceCard(BuildContext context, ColorScheme cs, StreamingService service) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _selectService(context, service),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: service.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(service.icon, color: service.color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getServiceDescription(service),
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _getServiceDescription(StreamingService service) {
    switch (service) {
      case StreamingService.youtube:
        return 'Browse or paste a YouTube link';
      case StreamingService.instagram:
        return 'Watch Instagram Reels together';
    }
  }
  
  void _selectService(BuildContext context, StreamingService service) {
    if (service == StreamingService.youtube) {
      _showYouTubeOptions(context);
    } else if (service == StreamingService.instagram) {
      _createInstagramReelsRoom(context);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WatchPartyWebViewPage(
            service: service,
            onVideoSelected: (url, title) => _onVideoSelected(url, title, service.name.toLowerCase()),
          ),
        ),
      );
    }
  }
  
  Future<void> _createInstagramReelsRoom(BuildContext context) async {
    if (_isCreatingRoom) return;
    setState(() => _isCreatingRoom = true);
    
    final watchPartyService = ref.read(watchPartyServiceProvider);
    
    try {
      // Auto-create room with Instagram Reels
      final room = await watchPartyService.createRoom(
        videoUrl: 'https://www.instagram.com/reels/',
        videoTitle: 'Instagram Reels',
        service: 'instagram',
      );
      
      if (room != null && mounted) {
        // Navigate directly to the Instagram Reels room
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InstagramReelsRoom(
              room: room,
              isHost: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating Instagram Reels room: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create room: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingRoom = false);
    }
  }
  
  void _showYouTubeOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'YouTube',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to find a video',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              
              _buildOptionTile(
                context: ctx,
                cs: cs,
                icon: Icons.explore_rounded,
                title: 'Browse YouTube',
                subtitle: 'Explore and select a video',
                color: const Color(0xFFFF0000),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => YouTubeBrowserPage(
                        onVideoSelected: (url, title) => _onVideoSelected(url, title, 'youtube'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              
              _buildOptionTile(
                context: ctx,
                cs: cs,
                icon: Icons.link_rounded,
                title: 'Enter YouTube URL',
                subtitle: 'Paste a video link directly',
                color: cs.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => YouTubePlayerPage(
                        onVideoSelected: (url, title) => _onVideoSelected(url, title, 'youtube'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildOptionTile({
    required BuildContext context,
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _onVideoSelected(String videoUrl, String videoTitle, String service) async {
    // Prevent duplicate room creation
    if (_isCreatingRoom) return;
    setState(() => _isCreatingRoom = true);
    
    final watchPartyService = ref.read(watchPartyServiceProvider);
    
    try {
      if (widget.existingRoom != null) {
        // Update existing room
        final updatedRoom = await watchPartyService.updateRoom(
          roomId: widget.existingRoom!.id,
          videoUrl: videoUrl,
          videoTitle: videoTitle,
          service: service,
        );
        
        if (updatedRoom != null && mounted) {
          // Pop back to room screen - the room subscription will update it
          Navigator.of(context).pop();
        }
      } else {
        // Create new room
        final room = await watchPartyService.createRoom(
          videoUrl: videoUrl,
          videoTitle: videoTitle,
          service: service,
        );
        
        if (room != null && mounted) {
          // Navigate to room screen, clearing all watch party flow screens
          // This handles the case where YouTubeBrowserPage is still in the stack
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => WatchPartyRoomScreen(room: room, isHost: true),
            ),
            (route) => route.isFirst, // Keep only the first route (main app)
          );
          
          // Refresh rooms list
          ref.invalidate(publicRoomsProvider);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create room')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isCreatingRoom = false);
    }
  }
}
