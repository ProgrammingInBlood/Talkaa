import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

    return Scaffold(
      backgroundColor: cs.surface,
      body: profileAsync.when(
        loading: () => _buildContent(
          context,
          cs,
          name: initialName ?? 'Loading...',
          avatarUrl: initialAvatar,
          isLoading: true,
        ),
        error: (_, __) => _buildContent(
          context,
          cs,
          name: initialName ?? 'Unknown',
          avatarUrl: initialAvatar,
          error: 'Failed to load profile',
        ),
        data: (profile) {
          if (profile == null) {
            return _buildContent(
              context,
              cs,
              name: initialName ?? 'Unknown',
              avatarUrl: initialAvatar,
              error: 'Profile not found',
            );
          }
          return _buildContent(
            context,
            cs,
            name: profile['full_name'] ?? profile['username'] ?? initialName ?? 'Unknown',
            username: profile['username'],
            avatarUrl: profile['avatar_url'] ?? initialAvatar,
            bio: profile['bio'],
            createdAt: profile['created_at'],
            lastSeen: profile['last_seen'],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme cs, {
    required String name,
    String? username,
    String? avatarUrl,
    String? bio,
    String? createdAt,
    String? lastSeen,
    bool isLoading = false,
    String? error,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final avatarSize = screenHeight * 0.35;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: avatarSize,
          pinned: true,
          stretch: true,
          backgroundColor: cs.primary,
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
                      Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
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
                        Text(error, style: TextStyle(color: cs.onErrorContainer)),
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
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
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
