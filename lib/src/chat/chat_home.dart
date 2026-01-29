import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../story/story_providers.dart';
import 'conversation_page.dart';
import 'search_user_screen.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_list_item.dart';
import 'chat_list_provider.dart';
// Removed unused chat_utils import

class ChatHome extends ConsumerWidget {
  final bool showFab;
  const ChatHome({super.key, this.showFab = true});

  Future<void> _deleteConversation(BuildContext context, WidgetRef ref, String chatId) async {
    try {
      final client = ref.read(supabaseProvider);
      
      // Delete all messages in the conversation first
      await client.from('messages').delete().eq('chat_id', chatId);
      
      // Delete chat participants
      await client.from('chat_participants').delete().eq('chat_id', chatId);
      
      // Delete the chat itself
      await client.from('chats').delete().eq('id', chatId);
      
      // Refresh the chat list
      ref.invalidate(realtimeChatListProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete conversation: $e')),
        );
      }
    }
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 56,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Start a Conversation',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Connect with friends and family.\nTap the button below to start chatting!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurfaceVariant,
                height: 1.5,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchUserScreen()),
                );
              },
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Find People'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchUserScreen()),
                );
              },
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search by username'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    // Start heartbeat updates for current user at app level
    // This ensures online status is updated whenever user is in the app
    ref.watch(heartbeatProvider);

    final chatListAsync = ref.watch(realtimeChatListProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: chatListAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('Error loading chats: \n${err.toString()}', textAlign: TextAlign.center),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return _buildEmptyState(context, cs);
          }
          return RefreshIndicator(
            onRefresh: () async {
              // Refresh both chat list and stories
              ref.invalidate(realtimeChatListProvider);
              ref.invalidate(realtimeStoriesProvider);
              ref.invalidate(realtimeHasMyStoryProvider);
              // Wait for the provider to refetch
              await ref.read(realtimeChatListProvider.future);
            },
            child: Container(
              color: cs.surface,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  ChatHeader(items: items),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Messages',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            '${items.length}',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final c = items[index];
                          final chat =
                              (c['chat'] as Map<String, dynamic>?) ?? const {};
                          final chatId = chat['id'] as String?;
                          return ChatListItem(
                            item: c,
                            onTap: () => Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        ConversationPage(conversationId: chatId),
                                transitionsBuilder:
                                    (context, animation, secondaryAnimation, child) {
                                  final tween = Tween<Offset>(
                                    begin: const Offset(0, 1),
                                    end: Offset.zero,
                                  ).chain(CurveTween(curve: Curves.easeOutCubic));
                                  return SlideTransition(
                                    position: animation.drive(tween),
                                    child: child,
                                  );
                                },
                                transitionDuration: const Duration(milliseconds: 300),
                                reverseTransitionDuration:
                                    const Duration(milliseconds: 250),
                              ),
                            ),
                            onDelete: (id) => _deleteConversation(context, ref, id),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}