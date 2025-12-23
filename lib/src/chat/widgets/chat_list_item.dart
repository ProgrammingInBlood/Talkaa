import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Removed unused supabase import
import '../chat_utils.dart';
import '../chat_list_provider.dart';

class ChatListItem extends ConsumerWidget {
  const ChatListItem({super.key, required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  // Removed unused helper to satisfy analyzer's unused_element warning.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // Removed unused client/user variables

    final chat = (item['chat'] as Map<String, dynamic>?) ?? const {};
    final chatId = chat['id'] as String?;
    final isGroup = (chat['is_group'] ?? false) == true;
    final chatName = (chat['name'] as String?)?.trim();
    final ts = (chat['last_message_at'] ?? '').toString();
    final timeLabel = formatTimestamp(ts);
    // Removed unused lastReadAt
    final unread = (item['unread_count'] as int?) ?? 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isGroup)
            (() {
              final chatAvatar = (chat['avatar_url'] as String?)?.trim();
              final hasChatAvatar = chatAvatar != null && chatAvatar.isNotEmpty;
              return CircleAvatar(
                radius: 28,
                backgroundColor: cs.primaryContainer,
                backgroundImage: hasChatAvatar ? NetworkImage(chatAvatar) : null,
                child: hasChatAvatar ? null : const Icon(Icons.person, size: 24),
              );
            })()
          else if (chatId != null)
            ref.watch(chatOtherUserAvatarProvider(chatId)).maybeWhen(
              data: (url) {
                final raw = (url ?? '').trim();
                final hasUrl = raw.isNotEmpty;
                return CircleAvatar(
                  radius: 28,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: hasUrl ? NetworkImage(raw) : null,
                  child: hasUrl ? null : const Icon(Icons.person, size: 24),
                );
              },
              orElse: () => CircleAvatar(
                radius: 28,
                backgroundColor: cs.primaryContainer,
                child: const Icon(Icons.person, size: 24),
              ),
            )
          else
            CircleAvatar(
              radius: 28,
              backgroundColor: cs.primaryContainer,
              child: const Icon(Icons.person, size: 24),
            ),
          // Online status indicator removed - only show in conversation page
        ],
      ),
      title: isGroup || (chatName != null && chatName.isNotEmpty)
          ? Text(
              titleCase(chatName ?? 'Conversation'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Roboto',
                height: 1.1,
              ),
            )
          : (chatId == null
              ? Text(
                  'Conversation',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Roboto',
                    height: 1.1,
                  ),
                )
              : ref.watch(chatOtherUserNameProvider(chatId)).maybeWhen(
                  data: (raw) {
                    final name = titleCase((raw ?? '').trim());
                    return Text(
                      name.isNotEmpty ? name : 'Conversation',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Roboto',
                        height: 1.1,
                      ),
                    );
                  },
                  orElse: () => const Text(
                    'Conversation',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Roboto',
                      height: 1.1,
                    ),
                  ),
                )),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          (item['last_message_content'] as String?) ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.75),
                fontFamily: 'Roboto',
              ),
        ),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeLabel,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Roboto'),
          ),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(14)),
              child: Text('$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      fontFamily: 'Roboto')),
            ),
          // Removed extra FutureBuilder for unread calculation; rely on unread_count
        ],
      ),
      onTap: onTap,
    );
  }
}