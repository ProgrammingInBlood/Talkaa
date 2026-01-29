import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import '../storage/signed_url_helper.dart';

class WatchPartyRoom {
  final String id;
  final String hostId;
  final String videoUrl;
  final String videoTitle;
  final String service;
  final bool isPublic;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? hostName;
  final String? hostAvatarUrl;
  final double currentPosition;
  final bool isPlaying;

  WatchPartyRoom({
    required this.id,
    required this.hostId,
    required this.videoUrl,
    required this.videoTitle,
    required this.service,
    required this.isPublic,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.hostName,
    this.hostAvatarUrl,
    this.currentPosition = 0,
    this.isPlaying = false,
  });

  factory WatchPartyRoom.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as Map<String, dynamic>?;
    return WatchPartyRoom(
      id: json['id'] as String? ?? '',
      hostId: json['host_id'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      videoTitle: json['video_title'] as String? ?? 'Untitled',
      service: json['service'] as String? ?? 'youtube',
      isPublic: json['is_public'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : DateTime.now(),
      hostName: host?['full_name'] as String? ?? host?['username'] as String?,
      hostAvatarUrl: host?['avatar_url'] as String?,
      currentPosition: (json['current_position'] as num?)?.toDouble() ?? 0,
      isPlaying: json['is_playing'] as bool? ?? false,
    );
  }

  WatchPartyRoom copyWith({
    String? videoUrl,
    String? videoTitle,
    String? service,
    bool? isActive,
    double? currentPosition,
    bool? isPlaying,
  }) {
    return WatchPartyRoom(
      id: id,
      hostId: hostId,
      videoUrl: videoUrl ?? this.videoUrl,
      videoTitle: videoTitle ?? this.videoTitle,
      service: service ?? this.service,
      isPublic: isPublic,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      hostName: hostName,
      hostAvatarUrl: hostAvatarUrl,
      currentPosition: currentPosition ?? this.currentPosition,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

class ParticipantActivity {
  final String id;
  final String userId;
  final String activityType; // 'joined', 'left', 'rejoined'
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final String? userName;
  final String? userAvatarUrl;

  ParticipantActivity({
    required this.id,
    required this.userId,
    required this.activityType,
    required this.timestamp,
    this.metadata,
    this.userName,
    this.userAvatarUrl,
  });

  factory ParticipantActivity.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['timestamp'] ?? json['activity_timestamp'];
    final parsedTimestamp = rawTimestamp is String
        ? DateTime.parse(rawTimestamp)
        : rawTimestamp is DateTime
            ? rawTimestamp
            : DateTime.now();
    final localTimestamp = parsedTimestamp.toLocal();
    return ParticipantActivity(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      activityType: json['activity_type'] as String? ?? 'joined',
      timestamp: localTimestamp,
      metadata: json['metadata'] as Map<String, dynamic>?,
      userName: json['user_full_name'] as String? ?? json['user_username'] as String?,
      userAvatarUrl: json['user_avatar_url'] as String?,
    );
  }
}

class WatchPartyService {
  final SupabaseClient client;

  WatchPartyService(this.client);

  Future<List<WatchPartyRoom>> fetchPublicRooms() async {
    try {
      // Fetch rooms
      final roomsResponse = await client
          .from('watch_party_rooms')
          .select()
          .eq('is_public', true)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final rooms = roomsResponse as List;
      if (rooms.isEmpty) return [];

      // Get unique host IDs (filter out nulls)
      final hostIds = rooms
          .map((r) => r['host_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();

      // Fetch profiles for all hosts
      Map<String, Map<String, dynamic>> profilesMap = {};
      if (hostIds.isNotEmpty) {
        final profilesResponse = await client
            .from('profiles')
            .select('id, full_name, username, avatar_url')
            .inFilter('id', hostIds);

        // Create a map of host_id -> profile
        for (final profile in profilesResponse as List) {
          final id = profile['id'] as String?;
          if (id != null) {
            profilesMap[id] = profile as Map<String, dynamic>;
          }
        }
      }

      // Sign avatar URLs for profiles
      for (final id in profilesMap.keys) {
        final profile = profilesMap[id]!;
        final avatarPath = profile['avatar_url'] as String?;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          profile['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
        }
      }

      // Combine rooms with profiles
      return rooms.map((room) {
        final hostId = room['host_id'] as String?;
        final profile = hostId != null ? profilesMap[hostId] : null;
        return WatchPartyRoom.fromJson({
          ...room as Map<String, dynamic>,
          'host': profile,
        });
      }).toList();
    } catch (e) {
      debugPrint('WatchPartyService: fetchPublicRooms error: $e');
      return [];
    }
  }

  Future<WatchPartyRoom?> createRoom({
    required String videoUrl,
    required String videoTitle,
    required String service,
    bool isPublic = true,
  }) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // Create the room
      final roomResponse = await client
          .from('watch_party_rooms')
          .insert({
            'host_id': userId,
            'video_url': videoUrl,
            'video_title': videoTitle,
            'service': service,
            'is_public': isPublic,
            'is_active': true,
          })
          .select()
          .single();

      // Fetch the host profile
      final profileResponse = await client
          .from('profiles')
          .select('id, full_name, username, avatar_url')
          .eq('id', userId)
          .single();

      // Sign avatar URL
      final profile = Map<String, dynamic>.from(profileResponse);
      final avatarPath = profile['avatar_url'] as String?;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        profile['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
      }

      return WatchPartyRoom.fromJson({
        ...roomResponse,
        'host': profile,
      });
    } catch (e) {
      debugPrint('WatchPartyService: createRoom error: $e');
      return null;
    }
  }

  Future<WatchPartyRoom?> updateRoom({
    required String roomId,
    String? videoUrl,
    String? videoTitle,
    String? service,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (videoUrl != null) updates['video_url'] = videoUrl;
      if (videoTitle != null) updates['video_title'] = videoTitle;
      if (service != null) updates['service'] = service;
      if (isActive != null) updates['is_active'] = isActive;

      if (updates.isEmpty) return null;

      // Update the room
      final roomResponse = await client
          .from('watch_party_rooms')
          .update(updates)
          .eq('id', roomId)
          .select()
          .single();

      // Fetch the host profile
      final hostId = roomResponse['host_id'] as String;
      final profileResponse = await client
          .from('profiles')
          .select('id, full_name, username, avatar_url')
          .eq('id', hostId)
          .single();

      return WatchPartyRoom.fromJson({
        ...roomResponse,
        'host': profileResponse,
      });
    } catch (e) {
      debugPrint('WatchPartyService: updateRoom error: $e');
      return null;
    }
  }

  Future<void> closeRoom(String roomId) async {
    try {
      await client
          .from('watch_party_rooms')
          .update({'is_active': false})
          .eq('id', roomId);
    } catch (e) {
      debugPrint('WatchPartyService: closeRoom error: $e');
    }
  }

  Future<void> updatePlaybackState({
    required String roomId,
    required double position,
    required bool isPlaying,
  }) async {
    try {
      await client
          .from('watch_party_rooms')
          .update({
            'current_position': position,
            'is_playing': isPlaying,
            'last_sync_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', roomId);
    } catch (e) {
      debugPrint('WatchPartyService: updatePlaybackState error: $e');
    }
  }

  Stream<WatchPartyRoom> subscribeToRoom(String roomId) {
    return client
        .from('watch_party_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((data) {
          if (data.isEmpty) throw Exception('Room not found');
          return WatchPartyRoom.fromJson(data.first);
        });
  }

  Future<WatchPartyRoom?> getRoom(String roomId) async {
    try {
      // Fetch the room
      final roomResponse = await client
          .from('watch_party_rooms')
          .select()
          .eq('id', roomId)
          .single();

      // Fetch the host profile
      final hostId = roomResponse['host_id'] as String;
      final profileResponse = await client
          .from('profiles')
          .select('id, full_name, username, avatar_url')
          .eq('id', hostId)
          .single();

      return WatchPartyRoom.fromJson({
        ...roomResponse,
        'host': profileResponse,
      });
    } catch (e) {
      debugPrint('WatchPartyService: getRoom error: $e');
      return null;
    }
  }

  // Participant activity methods
  Future<void> joinRoom(String roomId) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      debugPrint('WatchPartyService: Attempting to join room $roomId for user $userId');

      // Check if already a participant
      final existing = await client
          .from('watch_party_participants')
          .select('id, status')
          .eq('room_id', roomId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        debugPrint('WatchPartyService: User already a participant, reactivating');
        // Reactivate if previously left
        await client
            .from('watch_party_participants')
            .update({
              'status': 'active',
              'left_at': null,
            })
            .eq('id', existing['id']);
      } else {
        debugPrint('WatchPartyService: Joining as new participant');
        // Join as new participant
        await client
            .from('watch_party_participants')
            .insert({
              'room_id': roomId,
              'user_id': userId,
              'status': 'active',
            });
      }
      
      debugPrint('WatchPartyService: Successfully joined room $roomId');
    } catch (e) {
      debugPrint('WatchPartyService: joinRoom error: $e');
    }
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      await client
          .from('watch_party_participants')
          .update({
            'status': 'left',
            'left_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('room_id', roomId)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('WatchPartyService: leaveRoom error: $e');
    }
  }

  Future<int> getActiveParticipantCount(String roomId) async {
    try {
      final response = await client
          .from('watch_party_participants')
          .select('id')
          .eq('room_id', roomId)
          .eq('status', 'active');
      return (response as List).length;
    } catch (e) {
      debugPrint('WatchPartyService: getActiveParticipantCount error: $e');
      return 0;
    }
  }

  Stream<int> subscribeToParticipantCount(String roomId) {
    return client
        .from('watch_party_participants')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .map((participants) {
          final active = participants.where((p) => p['status'] == 'active').length;
          return active;
        });
  }

  Future<List<ParticipantActivity>> getRecentActivity(String roomId, {int limit = 10}) async {
    try {
      final response = await client
          .rpc('get_recent_room_activity', params: {
            'p_room_id': roomId,
            'p_limit': limit,
          });

      final activities = response as List;
      final result = <ParticipantActivity>[];
      for (final activity in activities) {
        final map = Map<String, dynamic>.from(activity as Map<String, dynamic>);
        // Sign avatar URL
        final avatarPath = map['user_avatar_url'] as String?;
        if (avatarPath != null && avatarPath.isNotEmpty) {
          map['user_avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
        }
        result.add(ParticipantActivity.fromJson(map));
      }
      return result;
    } catch (e) {
      debugPrint('WatchPartyService: getRecentActivity error: $e');
      return [];
    }
  }

  Stream<List<ParticipantActivity>> subscribeToActivity(String roomId) {
    debugPrint('WatchPartyService: Setting up activity subscription for room $roomId');
    
    return client
        .from('watch_party_activity_log')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('timestamp', ascending: false)
        .asyncMap((activities) async {
          debugPrint('WatchPartyService: Received activity update: ${activities.length} activities');
          
          final activityList = activities as List;
          if (activityList.isEmpty) return <ParticipantActivity>[];
          
          // Get user profiles for all activities
          final userIds = activityList
              .map((a) => a['user_id'] as String?)
              .where((id) => id != null)
              .cast<String>()
              .toSet()
              .toList();
          
          Map<String, Map<String, dynamic>> profilesMap = {};
          if (userIds.isNotEmpty) {
            final profilesResponse = await client
                .from('profiles')
                .select('id, full_name, username, avatar_url')
                .inFilter('id', userIds);
            
            for (final profile in profilesResponse as List) {
              final id = profile['id'] as String?;
              if (id != null) {
                final profileCopy = Map<String, dynamic>.from(profile as Map<String, dynamic>);
                // Sign avatar URL
                final avatarPath = profileCopy['avatar_url'] as String?;
                if (avatarPath != null && avatarPath.isNotEmpty) {
                  profileCopy['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
                }
                profilesMap[id] = profileCopy;
              }
            }
          }
          
          // Combine activities with profiles
          final result = activityList.map((activity) {
            final userId = activity['user_id'] as String?;
            final profile = userId != null ? profilesMap[userId] : null;
            return ParticipantActivity.fromJson({
              ...activity as Map<String, dynamic>,
              'user_full_name': profile?['full_name'],
              'user_username': profile?['username'],
              'user_avatar_url': profile?['avatar_url'],
            });
          }).toList();
          
          debugPrint('WatchPartyService: Processed ${result.length} activities with profiles');
          return result;
        });
  }
}

final watchPartyServiceProvider = Provider<WatchPartyService>((ref) {
  final client = ref.read(supabaseProvider);
  return WatchPartyService(client);
});

// One-time fetch for initial load
final publicRoomsProvider = FutureProvider<List<WatchPartyRoom>>((ref) async {
  final service = ref.read(watchPartyServiceProvider);
  return service.fetchPublicRooms();
});

// Realtime stream for public rooms - auto updates when rooms change
final publicRoomsStreamProvider = StreamProvider<List<WatchPartyRoom>>((ref) {
  final client = ref.read(supabaseProvider);
  
  return client
      .from('watch_party_rooms')
      .stream(primaryKey: ['id'])
      .eq('is_public', true)
      .order('created_at', ascending: false)
      .asyncMap((rooms) async {
        // Filter only active rooms
        final activeRooms = rooms.where((r) => r['is_active'] == true).toList();
        if (activeRooms.isEmpty) return <WatchPartyRoom>[];
        
        // Get unique host IDs
        final hostIds = activeRooms
            .map((r) => r['host_id'] as String?)
            .where((id) => id != null)
            .cast<String>()
            .toSet()
            .toList();
        
        // Fetch profiles for all hosts
        Map<String, Map<String, dynamic>> profilesMap = {};
        if (hostIds.isNotEmpty) {
          final profilesResponse = await client
              .from('profiles')
              .select('id, full_name, username, avatar_url')
              .inFilter('id', hostIds);
          
          for (final profile in profilesResponse as List) {
            final id = profile['id'] as String?;
            if (id != null) {
              profilesMap[id] = profile as Map<String, dynamic>;
            }
          }
        }
        
        // Combine rooms with profiles
        final roomsWithProfiles = activeRooms.map((room) {
          final hostId = room['host_id'] as String?;
          final profile = hostId != null ? profilesMap[hostId] : null;
          return WatchPartyRoom.fromJson({
            ...room,
            'host': profile,
          });
        }).toList();
        
        return roomsWithProfiles;
      });
});
