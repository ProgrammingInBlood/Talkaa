import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omni_video_player/omni_video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../watch_party/watch_party_service.dart';
import '../providers.dart';
import 'watch_party_host_flow.dart';

class WatchPartyRoomScreen extends ConsumerStatefulWidget {
  final WatchPartyRoom room;
  final bool isHost;

  const WatchPartyRoomScreen({
    super.key,
    required this.room,
    this.isHost = false,
  });

  @override
  ConsumerState<WatchPartyRoomScreen> createState() => _WatchPartyRoomScreenState();
}

class _WatchPartyRoomScreenState extends ConsumerState<WatchPartyRoomScreen> {
  late WatchPartyRoom _room;
  
  // OmniVideoPlayer controller
  OmniPlaybackController? _playerController;
  
  StreamSubscription? _roomSubscription;
  StreamSubscription? _activitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  DateTime? _lastSeekTime;
  bool? _lastHostPlayState;
  
  // Activity tracking
  List<ParticipantActivity> _recentActivity = [];
  
  // Cache isHost to avoid recalculation during builds
  late bool _isHost;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _isHost = widget.isHost || 
        (ref.read(supabaseProvider).auth.currentUser?.id == widget.room.hostId);
    WakelockPlus.enable();
    _subscribeToRoom();
    
    // Automatically join the room
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('WatchPartyRoomScreen: Initializing room ${widget.room.id}');
      await _joinRoom();
      await _loadRecentActivity();
      _subscribeToActivity();
    });
  }
  
  void _onControllerCreated(OmniPlaybackController controller) {
    _playerController?.removeListener(_onPlayerUpdate);
    _playerController = controller..addListener(_onPlayerUpdate);
    
    if (_isHost) {
      // Start host sync to broadcast position every 1 second via Supabase
      _startHostSync();
    } else {
      // For participants, sync to host's current state immediately
      // Further syncs are handled by Supabase Realtime subscription
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _playerController != null) {
          _syncToHost(_room);
        }
      });
    }
  }
  
  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }


  @override
  void dispose() {
    WakelockPlus.disable();
    _roomSubscription?.cancel();
    _activitySubscription?.cancel();
    _syncTimer?.cancel();
    _playerController?.removeListener(_onPlayerUpdate);
    
    // Note: _leaveRoom() is called explicitly when user taps Leave button
    // Async operations won't complete during dispose
    
    super.dispose();
  }

  void _subscribeToRoom() {
    final service = ref.read(watchPartyServiceProvider);
    
    final originalHostName = widget.room.hostName;
    final originalHostAvatarUrl = widget.room.hostAvatarUrl;
    
    _roomSubscription = service.subscribeToRoom(widget.room.id).listen(
      (updatedRoom) {
        if (!mounted) return;
        
        final videoChanged = updatedRoom.videoUrl != _room.videoUrl;
        
        final roomWithHost = WatchPartyRoom(
          id: updatedRoom.id,
          hostId: updatedRoom.hostId,
          videoUrl: updatedRoom.videoUrl,
          videoTitle: updatedRoom.videoTitle,
          service: updatedRoom.service,
          isPublic: updatedRoom.isPublic,
          isActive: updatedRoom.isActive,
          createdAt: updatedRoom.createdAt,
          updatedAt: updatedRoom.updatedAt,
          hostName: updatedRoom.hostName ?? originalHostName,
          hostAvatarUrl: updatedRoom.hostAvatarUrl ?? originalHostAvatarUrl,
          currentPosition: updatedRoom.currentPosition,
          isPlaying: updatedRoom.isPlaying,
        );
        
        setState(() => _room = roomWithHost);
        
        if (videoChanged) {
          setState(() {});
        } else if (!_isHost && !_isSyncing) {
          _syncToHost(roomWithHost);
        }
        
        if (!updatedRoom.isActive && mounted && !_isHost) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Room has been closed by host')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      onError: (e) => debugPrint('Room subscription error: $e'),
    );
  }

  void _subscribeToActivity() {
    debugPrint('WatchPartyRoomScreen: Setting up activity subscription for room ${widget.room.id}');
    final service = ref.read(watchPartyServiceProvider);
    
    _activitySubscription = service.subscribeToActivity(widget.room.id).listen(
      (activities) {
        if (!mounted) return;
        debugPrint('WatchPartyRoomScreen: Received ${activities.length} activities');
        setState(() {
          _recentActivity = activities;
        });
      },
      onError: (e) => debugPrint('Activity subscription error: $e'),
    );
  }

  Future<void> _loadRecentActivity() async {
    final service = ref.read(watchPartyServiceProvider);
    final activities = await service.getRecentActivity(widget.room.id, limit: 20);
    if (!mounted) return;
    setState(() {
      _recentActivity = activities;
    });
  }

  Future<void> _joinRoom() async {
    debugPrint('WatchPartyRoomScreen: Joining room ${widget.room.id}');
    final service = ref.read(watchPartyServiceProvider);
    await service.joinRoom(widget.room.id);
  }

  Future<void> _leaveRoom() async {
    debugPrint('WatchPartyRoomScreen: Leaving room ${widget.room.id}');
    final service = ref.read(watchPartyServiceProvider);
    await service.leaveRoom(widget.room.id);
    debugPrint('WatchPartyRoomScreen: Left room ${widget.room.id}');
  }

  Widget _buildActivityItem(ParticipantActivity activity, ColorScheme cs) {
    String activityText;
    IconData activityIcon;
    Color activityColor;
    
    switch (activity.activityType) {
      case 'created':
        activityText = 'created this room';
        activityIcon = Icons.add_circle;
        activityColor = Colors.purple;
        break;
      case 'joined':
        activityText = 'joined';
        activityIcon = Icons.person_add;
        activityColor = Colors.green;
        break;
      case 'left':
        activityText = 'left';
        activityIcon = Icons.person_remove;
        activityColor = Colors.red;
        break;
      case 'rejoined':
        activityText = 'rejoined';
        activityIcon = Icons.person_add;
        activityColor = Colors.blue;
        break;
      default:
        activityText = 'updated';
        activityIcon = Icons.info;
        activityColor = cs.onSurfaceVariant;
    }

    final timeString = _formatTimeAgo(activity.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // User avatar
          if (activity.userAvatarUrl != null && activity.userAvatarUrl!.isNotEmpty)
            CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(activity.userAvatarUrl!),
            )
          else
            CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.person, size: 16, color: cs.primary),
            ),
          
          const SizedBox(width: 12),
          
          // Activity info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      activityIcon,
                      size: 16,
                      color: activityColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${activity.userName ?? 'Someone'} $activityText at $timeString',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    // Format as HH:MM
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  void _syncToHost(WatchPartyRoom room) {
    if (_playerController == null) return;
    
    _isSyncing = true;
    
    final now = DateTime.now();
    final hostPosition = Duration(milliseconds: (room.currentPosition * 1000).toInt());
    final currentPosition = _playerController!.currentPosition;
    final diff = (hostPosition - currentPosition).inMilliseconds.abs();
    
    // Check if host play state changed
    final hostPlayStateChanged = _lastHostPlayState != null && _lastHostPlayState != room.isPlaying;
    _lastHostPlayState = room.isPlaying;
    
    // Only seek if:
    // 1. Position differs by more than 3 seconds, OR
    // 2. Host play state just changed (play/pause), OR
    // 3. We haven't seeked in the last 5 seconds and diff > 2 seconds
    final timeSinceLastSeek = _lastSeekTime != null 
        ? now.difference(_lastSeekTime!).inSeconds 
        : 999;
    
    final shouldSeek = diff > 3000 || 
        (hostPlayStateChanged && diff > 500) ||
        (timeSinceLastSeek > 5 && diff > 2000);
    
    if (shouldSeek) {
      debugPrint('WatchParty: Seeking - diff: ${diff}ms, hostChanged: $hostPlayStateChanged');
      _playerController!.seekTo(hostPosition);
      _lastSeekTime = now;
    }
    
    // Strictly enforce play/pause state when it changes
    if (room.isPlaying && !_playerController!.isPlaying) {
      debugPrint('WatchParty: Host playing, starting playback');
      _playerController!.play();
    } else if (!room.isPlaying && _playerController!.isPlaying) {
      debugPrint('WatchParty: Host paused, pausing playback');
      _playerController!.pause();
    }
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _isSyncing = false;
    });
  }

  void _startHostSync() {
    if (!_isHost) return;
    
    _syncTimer?.cancel();
    // Host broadcasts state every 1 second for tighter sync
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_playerController == null) return;
      
      final position = _playerController!.currentPosition.inMilliseconds / 1000.0;
      final isPlaying = _playerController!.isPlaying;
      
      ref.read(watchPartyServiceProvider).updatePlaybackState(
        roomId: _room.id,
        position: position,
        isPlaying: isPlaying,
      );
    });
  }

  // Participant sync is handled by Supabase Realtime subscription in _subscribeToRoom
  // No periodic polling needed - Realtime pushes updates when host changes playback state

  VideoSourceConfiguration _getVideoSourceConfig() {
    if (_room.service == 'youtube') {
      return VideoSourceConfiguration.youtube(
        videoUrl: Uri.parse(_room.videoUrl),
        preferredQualities: [
          OmniVideoQuality.high1080,
          OmniVideoQuality.high720,
          OmniVideoQuality.medium480,
        ],
        availableQualities: [
          OmniVideoQuality.high1080,
          OmniVideoQuality.high720,
          OmniVideoQuality.medium480,
          OmniVideoQuality.medium360,
          OmniVideoQuality.low144,
        ],
        enableYoutubeWebViewFallback: true,
        forceYoutubeWebViewOnly: false,
      ).copyWith(
        autoPlay: _isHost || _room.isPlaying,
        initialPosition: Duration(milliseconds: (_room.currentPosition * 1000).toInt()),
        initialVolume: 1.0,
        allowSeeking: _isHost,
      );
    } else {
      // For other services (Netflix, Prime, etc.) use network URL
      return VideoSourceConfiguration.network(
        videoUrl: Uri.parse(_room.videoUrl),
      ).copyWith(
        autoPlay: _isHost || _room.isPlaying,
        initialPosition: Duration(milliseconds: (_room.currentPosition * 1000).toInt()),
        initialVolume: 1.0,
        allowSeeking: _isHost,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveRoom();
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _leaveRoom();
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          _room.videoTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isHost)
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Change Video',
              onPressed: _changeVideo,
            ),
        ],
      ),
      body: Column(
        children: [
          // Video Player with participant overlay
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: OmniVideoPlayer(
                  key: ValueKey(_room.videoUrl),
                  callbacks: VideoPlayerCallbacks(
                    onControllerCreated: _onControllerCreated,
                    onFullScreenToggled: (_) {},
                    onFinished: () {},
                  ),
                  configuration: VideoPlayerConfiguration(
                    videoSourceConfiguration: _getVideoSourceConfig(),
                    playerUIVisibilityOptions: PlayerUIVisibilityOptions().copyWith(
                      showSeekBar: _isHost,
                      showCurrentTime: _isHost,
                      showDurationTime: _isHost,
                      showLoadingWidget: true,
                      showErrorPlaceholder: true,
                      showFullScreenButton: true,
                      showSwitchVideoQuality: true,
                      showPlaybackSpeedButton: _isHost,
                      showMuteUnMuteButton: true,
                      showPlayPauseReplayButton: _isHost,
                      enableForwardGesture: _isHost,
                      enableBackwardGesture: _isHost,
                    ),
                    playerTheme: OmniVideoPlayerThemeData().copyWith(
                      overlays: VideoPlayerOverlayTheme().copyWith(
                        backgroundColor: Colors.black,
                        alpha: 50,
                      ),
                    ),
                    customPlayerWidgets: CustomPlayerWidgets().copyWith(
                      loadingWidget: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Room Info & Controls
          Expanded(
            child: Container(
              color: cs.surface,
              child: Column(
                children: [
                  // Scrollable content (no title - it's in header)
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Host Info
                          Row(
                            children: [
                              if (_room.hostAvatarUrl != null && _room.hostAvatarUrl!.isNotEmpty)
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: NetworkImage(_room.hostAvatarUrl!),
                                )
                              else
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.primaryContainer,
                                  child: Icon(Icons.person, size: 18, color: cs.primary),
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hosted by',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      _room.hostName ?? 'Unknown',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _isHost 
                                      ? cs.primary.withValues(alpha: 0.15)
                                      : cs.secondary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _isHost ? 'Host' : 'Viewer',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _isHost ? cs.primary : cs.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Host controls
                          if (_isHost) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _changeVideo,
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('Change Video'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _closeRoom,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Close Room'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  foregroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await _leaveRoom();
                                  if (mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                icon: const Icon(Icons.exit_to_app_rounded),
                                label: const Text('Leave Room'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Activity Feed
                          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (_recentActivity.isNotEmpty)
                      Text(
                        '${_recentActivity.length} activities',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_recentActivity.isEmpty)
                  Text(
                    'No recent activity',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      primary: false,
                      itemCount: _recentActivity.length,
                      itemBuilder: (context, index) {
                        return _buildActivityItem(
                          _recentActivity[index],
                          cs,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  void _changeVideo() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WatchPartyHostFlow(existingRoom: _room),
      ),
    );
  }

  Future<void> _closeRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Room?'),
        content: const Text('This will end the watch party for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _roomSubscription?.cancel();
      _syncTimer?.cancel();
      
      final service = ref.read(watchPartyServiceProvider);
      await service.closeRoom(_room.id);
      ref.invalidate(publicRoomsProvider);
      
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }
}
