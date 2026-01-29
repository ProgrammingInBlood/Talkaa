import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../../storage/signed_url_helper.dart';
import '../chat_utils.dart';
import '../search_user_screen.dart';
import 'package:talka_flutter/src/story/story_uploader.dart';
import 'package:talka_flutter/src/story/story_service.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:talka_flutter/src/story/story_providers.dart';
import 'package:talka_flutter/src/story/story_viewer_screen.dart';

class ChatHeader extends ConsumerWidget {
  const ChatHeader({super.key, required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseProvider);
    final user = client.auth.currentUser!;
    final cs = Theme.of(context).colorScheme;

    return SliverAppBar(
      pinned: true,
      expandedHeight: 168,
      backgroundColor: cs.primary,
      foregroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      surfaceTintColor: Colors.transparent,
      actions: const [],
      flexibleSpace: FlexibleSpaceBar(
        background: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.primary, cs.primaryContainer.withValues(alpha: 0.6)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chat_bubble_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Talka',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SearchUserScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 92,
                      child: Row(
                        children: [
                          FutureBuilder<Map<String, dynamic>?>(
                            future: client
                                .from('profiles')
                                .select('avatar_url, full_name, username')
                                .eq('id', user.id)
                                .maybeSingle(),
                            builder: (context, snap) {
                              final p = snap.data ?? const {};
                              final avatarPath = p['avatar_url'] as String?;
                              // Use FutureBuilder to get signed URL for own avatar
                              return FutureBuilder<String>(
                                future: avatarPath != null && avatarPath.isNotEmpty
                                    ? SignedUrlHelper.getAvatarUrl(client, avatarPath)
                                    : Future.value(''),
                                builder: (context, avatarSnap) {
                                  final avatarUrl = avatarSnap.data ?? '';
                                  Widget avatar;
                                  if (avatarUrl.isNotEmpty) {
                                    avatar = CircleAvatar(
                                      radius: 30,
                                      backgroundImage: NetworkImage(avatarUrl),
                                    );
                                  } else {
                                    avatar = CircleAvatar(
                                      radius: 30,
                                      backgroundColor: cs.primaryContainer,
                                      child: const Icon(Icons.person, color: Colors.white),
                                    );
                                  }
                              return GestureDetector(
                                onTap: () async {
                                  final svc = ref.read(StoryService.storyServiceProvider);
                                  final hasMyStory = await svc.hasActiveStoryForSelf();
                                  if (!context.mounted) return;
                                  await showModalBottomSheet(
                                    context: context,
                                    backgroundColor: cs.surface,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    builder: (ctx) {
                                      return SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.photo_camera_rounded),
                                              title: const Text('Take photo'),
                                              onTap: () async {
                                                Navigator.of(ctx).pop();
                                                final url = await StoryUploader.captureAndUpload(ref);
                                                if (url != null) {
                                                  final svc2 = ref.read(StoryService.storyServiceProvider);
                                                  await svc2.createStory(ref, mediaUrl: url);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Story added')),
                                                  );
                                                }
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.photo_library_rounded),
                                              title: const Text('Choose from gallery'),
                                              onTap: () async {
                                                Navigator.of(ctx).pop();
                                                final url = await StoryUploader.pickFromGalleryAndUpload(ref);
                                                if (url != null) {
                                                  final svc2 = ref.read(StoryService.storyServiceProvider);
                                                  await svc2.createStory(ref, mediaUrl: url);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Story added')),
                                                  );
                                                }
                                              },
                                            ),
                                            if (hasMyStory)
                                              ListTile(
                                                leading: const Icon(Icons.visibility_rounded),
                                                title: const Text('View my story'),
                                                onTap: () async {
                                                  Navigator.of(ctx).pop();
                                                  final svc2 = ref.read(StoryService.storyServiceProvider);
                                                  final messenger = ScaffoldMessenger.of(context);
                                                  final all = await svc2.fetchActiveStories();
                                                  final uid = ref.read(supabaseProvider).auth.currentUser?.id;
                                                  if (uid == null) return;
                                                  final selfStories = all.where((m) => (m['user_id']?.toString() ?? '') == uid).toList();
                                                  if (selfStories.isEmpty) {
                                                    if (!context.mounted) return;
                                                    messenger.showSnackBar(const SnackBar(content: Text('No active story')));
                                                    return;
                                                  }
                                                  if (!context.mounted) return;
                                                  final deleted = await Navigator.of(context).push<bool>(
                                                    PageRouteBuilder(
                                                      opaque: false,
                                                      pageBuilder: (_, __, ___) => StoryViewerScreen(
                                                        stories: selfStories,
                                                        initialIndex: 0,
                                                        isOwnStory: true,
                                                      ),
                                                      transitionsBuilder: (_, animation, __, child) {
                                                        return FadeTransition(opacity: animation, child: child);
                                                      },
                                                    ),
                                                  );
                                                  if (deleted == true) {
                                                    ref.invalidate(realtimeStoriesProvider);
                                                    ref.invalidate(realtimeHasMyStoryProvider);
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Builder(builder: (context) {
                                          final hasMyStoryAsync = ref.watch(realtimeHasMyStoryProvider);
                                          return hasMyStoryAsync.when(
                                            data: (hasMyStory) {
                                              if (hasMyStory) {
                                                return DottedBorder(
                                                  color: Colors.white,
                                                  strokeWidth: 2,
                                                  dashPattern: const [3, 2],
                                                  borderType: BorderType.Circle,
                                                  padding: EdgeInsets.zero,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(2),
                                                    decoration: const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: avatar,
                                                  ),
                                                );
                                              }
                                              return Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.fromBorderSide(BorderSide(color: Colors.white30, width: 2)),
                                                ),
                                                child: avatar,
                                              );
                                            },
                                            loading: () => Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.fromBorderSide(BorderSide(color: Colors.white30, width: 2)),
                                              ),
                                              child: avatar,
                                            ),
                                            error: (_, __) => Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.fromBorderSide(BorderSide(color: Colors.white30, width: 2)),
                                              ),
                                              child: avatar,
                                            ),
                                          );
                                        }),
                                        Positioned(
                                          right: -2,
                                          bottom: -2,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 2),
                                            ),
                                            child: const Icon(Icons.add, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    const SizedBox(
                                      width: 64,
                                      child: Text(
                                        'You',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          height: 1.05,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Builder(builder: (context) {
                                    final storiesAsync = ref.watch(realtimeStoriesProvider);
                                    return storiesAsync.when(
                                      data: (stories) {
                                        final others = stories
                                            .where((s) => (s['user_id']?.toString() ?? '') != user.id)
                                            .toList();
                                        if (others.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        // Group stories by user_id to show one avatar per user
                                        final Map<String, List<Map<String, dynamic>>> groupedByUser = {};
                                        for (final s in others) {
                                          final uid = s['user_id']?.toString() ?? '';
                                          groupedByUser.putIfAbsent(uid, () => []).add(s);
                                        }
                                        final userIds = groupedByUser.keys.toList();
                                        
                                        return Row(
                                          children: [
                                            for (int i = 0; i < userIds.length; i++)
                                              Builder(builder: (context) {
                                                final uid = userIds[i];
                                                final userStories = groupedByUser[uid]!;
                                                final s = userStories.first; // Use first story for user info
                                                // Check if ALL stories from this user have been viewed
                                                final hasViewedAll = userStories.every((story) => story['hasViewed'] == true);
                                                final userProfile = s['user'] as Map<String, dynamic>? ?? const {};
                                                final avatarUrl = (userProfile['avatar_url'] ?? '') as String;
                                                
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7.0),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Stack(
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.all(3),
                                                            decoration: hasViewedAll
                                                                ? const BoxDecoration(
                                                                    shape: BoxShape.circle,
                                                                    border: Border.fromBorderSide(BorderSide(color: Colors.white30, width: 2)),
                                                                  )
                                                                : const BoxDecoration(
                                                                    shape: BoxShape.circle,
                                                                    gradient: LinearGradient(colors: [Color(0xFFFF6A00), Color(0xFFFFD500)]),
                                                                  ),
                                                            child: Container(
                                                              padding: const EdgeInsets.all(2),
                                                              decoration: const BoxDecoration(
                                                                shape: BoxShape.circle,
                                                                color: Color(0x22000000),
                                                              ),
                                                              child: GestureDetector(
                                                                onTap: () async {
                                                                  await Navigator.of(context).push(
                                                                    PageRouteBuilder(
                                                                      opaque: false,
                                                                      pageBuilder: (_, __, ___) => StoryViewerScreen(
                                                                        stories: userStories,
                                                                        initialIndex: 0,
                                                                        isOwnStory: false,
                                                                      ),
                                                                      transitionsBuilder: (_, animation, __, child) {
                                                                        return FadeTransition(opacity: animation, child: child);
                                                                      },
                                                                    ),
                                                                  );
                                                                  ref.invalidate(realtimeStoriesProvider);
                                                                },
                                                                child: CircleAvatar(
                                                                  radius: 30,
                                                                  backgroundColor: cs.primaryContainer,
                                                                  backgroundImage: avatarUrl.isNotEmpty 
                                                                      ? NetworkImage(avatarUrl)
                                                                      : null,
                                                                  child: avatarUrl.isEmpty 
                                                                      ? const Icon(Icons.person, color: Colors.white)
                                                                      : null,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          // Story count badge if multiple stories
                                                          if (userStories.length > 1)
                                                            Positioned(
                                                              right: 0,
                                                              bottom: 0,
                                                              child: Container(
                                                                padding: const EdgeInsets.all(4),
                                                                decoration: BoxDecoration(
                                                                  color: cs.primary,
                                                                  shape: BoxShape.circle,
                                                                  border: Border.all(color: Colors.white, width: 1.5),
                                                                ),
                                                                child: Text(
                                                                  '${userStories.length}',
                                                                  style: const TextStyle(
                                                                    color: Colors.white,
                                                                    fontSize: 10,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 3),
                                                      SizedBox(
                                                        width: 64,
                                                        child: Text(
                                                          titleCase((userProfile['full_name'] ?? userProfile['username'] ?? 'Story') as String),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          textAlign: TextAlign.center,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            height: 1.05,
                                                            fontFamily: 'Roboto',
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                          ],
                                        );
                                      },
                                      loading: () => const SizedBox.shrink(),
                                      error: (_, __) => const SizedBox.shrink(),
                                    );
                                  }),

                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}