import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers.dart';

final userProfileProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) async {
  final client = ref.read(supabaseProvider);
  try {
    final row = await client
        .from('profiles')
        .select('id, full_name, username, avatar_url, bio, created_at, last_seen')
        .eq('id', userId)
        .maybeSingle();
    return row;
  } catch (_) {
    return null;
  }
});

// Provider to fetch shared media between current user and target user
final sharedMediaProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, targetUserId) async {
  final client = ref.read(supabaseProvider);
  final myId = client.auth.currentUser?.id;
  if (myId == null) return [];
  
  try {
    // Find chats where both users are participants
    final myChats = await client
        .from('chat_participants')
        .select('chat_id')
        .eq('user_id', myId);
    
    final myChatIds = (myChats as List).map((e) => e['chat_id'] as String).toList();
    if (myChatIds.isEmpty) return [];
    
    final theirChats = await client
        .from('chat_participants')
        .select('chat_id')
        .eq('user_id', targetUserId)
        .inFilter('chat_id', myChatIds);
    
    final sharedChatIds = (theirChats as List).map((e) => e['chat_id'] as String).toList();
    if (sharedChatIds.isEmpty) return [];
    
    // Fetch all image messages from shared chats
    final messages = await client
        .from('messages')
        .select('id, file_url, created_at, sender_id')
        .inFilter('chat_id', sharedChatIds)
        .eq('message_type', 'image')
        .not('file_url', 'is', null)
        .order('created_at', ascending: false)
        .limit(50);
    
    return (messages as List)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => (m['file_url'] as String?)?.isNotEmpty == true)
        .toList();
  } catch (_) {
    return [];
  }
});

class UserProfileScreen extends ConsumerWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatar;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(userProfileProvider(userId));
    final sharedMediaAsync = ref.watch(sharedMediaProvider(userId));

    return Scaffold(
      backgroundColor: cs.surface,
      body: profileAsync.when(
        loading: () => _buildContent(
          context,
          ref,
          cs,
          name: initialName ?? 'Loading...',
          avatarUrl: initialAvatar,
          isLoading: true,
          sharedMedia: const [],
        ),
        error: (_, __) => _buildContent(
          context,
          ref,
          cs,
          name: initialName ?? 'Unknown',
          avatarUrl: initialAvatar,
          error: 'Failed to load profile',
          sharedMedia: const [],
        ),
        data: (profile) {
          if (profile == null) {
            return _buildContent(
              context,
              ref,
              cs,
              name: initialName ?? 'Unknown',
              avatarUrl: initialAvatar,
              error: 'Profile not found',
              sharedMedia: const [],
            );
          }
          return _buildContent(
            context,
            ref,
            cs,
            name: profile['full_name'] ?? profile['username'] ?? initialName ?? 'Unknown',
            username: profile['username'],
            avatarUrl: profile['avatar_url'] ?? initialAvatar,
            bio: profile['bio'],
            createdAt: profile['created_at'],
            lastSeen: profile['last_seen'],
            sharedMedia: sharedMediaAsync.value ?? const [],
            isMediaLoading: sharedMediaAsync.isLoading,
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ColorScheme cs, {
    required String name,
    String? username,
    String? avatarUrl,
    String? bio,
    String? createdAt,
    String? lastSeen,
    bool isLoading = false,
    String? error,
    required List<Map<String, dynamic>> sharedMedia,
    bool isMediaLoading = false,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final avatarSize = screenHeight * 0.38;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: avatarSize,
          pinned: true,
          stretch: true,
          backgroundColor: const Color(0xFF7FA66A),
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            stretchModes: const [
              StretchMode.zoomBackground,
              StretchMode.fadeTitle,
            ],
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
            background: GestureDetector(
              onTap: () {
                if (avatarUrl != null && avatarUrl.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FullScreenImageViewer(
                        imageUrl: avatarUrl,
                        heroTag: 'profile_avatar_$userId',
                      ),
                    ),
                  );
                }
              },
              child: Hero(
                tag: 'profile_avatar_$userId',
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (avatarUrl != null && avatarUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: cs.primaryContainer,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: cs.primaryContainer,
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: cs.onPrimaryContainer.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    else
                      Container(
                        color: cs.primaryContainer,
                        child: Icon(
                          Icons.person,
                          size: 100,
                          color: cs.onPrimaryContainer.withValues(alpha: 0.5),
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: cs.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(child: Text(error, style: TextStyle(color: cs.onErrorContainer))),
                      ],
                    ),
                  )
                else if (isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else ...[
                  // Quick action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        context,
                        cs,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _buildActionButton(
                        context,
                        cs,
                        icon: Icons.call_outlined,
                        label: 'Audio',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      _buildActionButton(
                        context,
                        cs,
                        icon: Icons.videocam_outlined,
                        label: 'Video',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Info section
                  Text(
                    'Info',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  if (username != null && username.isNotEmpty) ...[
                    _buildInfoCard(
                      context,
                      cs,
                      icon: Icons.alternate_email,
                      label: 'Username',
                      value: '@$username',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (bio != null && bio.isNotEmpty) ...[
                    _buildInfoCard(
                      context,
                      cs,
                      icon: Icons.info_outline,
                      label: 'Bio',
                      value: bio,
                      isMultiLine: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (createdAt != null) ...[
                    _buildInfoCard(
                      context,
                      cs,
                      icon: Icons.calendar_today_outlined,
                      label: 'Joined',
                      value: _formatJoinDate(createdAt),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (lastSeen != null) ...[
                    _buildInfoCard(
                      context,
                      cs,
                      icon: Icons.access_time,
                      label: 'Last Active',
                      value: _formatLastSeen(lastSeen),
                    ),
                  ],
                  
                  // Shared Media section
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Shared Media',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      if (sharedMedia.isNotEmpty)
                        Text(
                          '${sharedMedia.length} items',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (isMediaLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (sharedMedia.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 48,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No shared media yet',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _buildMediaGrid(context, cs, sharedMedia, screenWidth),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildActionButton(
    BuildContext context,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: cs.primary, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMediaGrid(
    BuildContext context,
    ColorScheme cs,
    List<Map<String, dynamic>> media,
    double screenWidth,
  ) {
    final crossAxisCount = 3;
    final spacing = 4.0;
    final itemSize = (screenWidth - 40 - (spacing * (crossAxisCount - 1))) / crossAxisCount;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: media.length,
      itemBuilder: (context, index) {
        final item = media[index];
        final imageUrl = item['file_url'] as String? ?? '';
        
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FullScreenImageViewer(
                  imageUrl: imageUrl,
                  heroTag: 'shared_media_$index',
                ),
              ),
            );
          },
          child: Hero(
            tag: 'shared_media_$index',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: itemSize,
                height: itemSize,
                placeholder: (_, __) => Container(
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
    bool isMultiLine = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: isMultiLine ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJoinDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('MMMM d, yyyy').format(date);
    } catch (_) {
      return 'Unknown';
    }
  }

  String _formatLastSeen(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 2) {
        return 'Online now';
      } else if (diff.inMinutes < 60) {
        return '${diff.inMinutes} minutes ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} hours ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return DateFormat('MMM d, yyyy').format(date);
      }
    } catch (_) {
      return 'Unknown';
    }
  }
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 100,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
