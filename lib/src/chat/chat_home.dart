import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'conversation_page.dart';
import 'search_user_screen.dart';
import 'widgets/chat_header.dart';
import 'widgets/chat_list_item.dart';
import 'chat_list_provider.dart';
// Removed unused chat_utils import

class ChatHome extends ConsumerWidget {
  final bool showFab;
  const ChatHome({super.key, this.showFab = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseProvider);
    // final user = client.auth.currentUser!; // no longer needed here
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
            return const Center(child: Text('No conversations yet'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(realtimeChatListProvider);
            },
            child: Container(
              color: cs.surface,
              child: CustomScrollView(
                slivers: [
                  ChatHeader(items: items),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final c = items[index];
                        final chat = (c['chat'] as Map<String, dynamic>?) ?? const {};
                        final chatId = chat['id'] as String?;
                        return ChatListItem(
                          item: c,
                          onTap: () => Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                  ConversationPage(conversationId: chatId),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
                              reverseTransitionDuration: const Duration(milliseconds: 250),
                            ),
                          ),
                        );
                      },
                      childCount: items.length,
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