import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat_utils.dart';
import '../chat_list_provider.dart';
import '../../profile/user_profile_screen.dart';

class ChatListItem extends ConsumerWidget {
  const ChatListItem({
    super.key, 
    required this.item, 
    required this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final void Function(String chatId)? onDelete;

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

    // Get other user info for profile navigation
    final otherUserId = chatId != null && !isGroup
        ? ref.watch(chatOtherUserIdProvider(chatId)).value
        : null;
    final otherUserName = chatId != null && !isGroup
        ? ref.watch(chatOtherUserNameProvider(chatId)).value
        : null;
    final otherUserAvatar = chatId != null && !isGroup
        ? ref.watch(chatOtherUserAvatarProvider(chatId)).value
        : null;

    final avatarWidget = isGroup
        ? (chatId != null
            ? ref.watch(chatGroupAvatarProvider(chatId)).maybeWhen(
                data: (url) {
                  final raw = (url ?? '').trim();
                  final isValidUrl = raw.isNotEmpty;
                  return CircleAvatar(
                    radius: 26,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: isValidUrl ? NetworkImage(raw) : null,
                    child: isValidUrl ? null : const Icon(Icons.group, size: 22),
                  );
                },
                orElse: () => CircleAvatar(
                  radius: 26,
                  backgroundColor: cs.primaryContainer,
                  child: const Icon(Icons.group, size: 22),
                ),
              )
            : CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: const Icon(Icons.group, size: 22),
              ))
        : (chatId != null
            ? ref.watch(chatOtherUserAvatarProvider(chatId)).maybeWhen(
                data: (url) {
                  final raw = (url ?? '').trim();
                  // Provider returns signed URL, just check if non-empty
                  final isValidUrl = raw.isNotEmpty;
                  return CircleAvatar(
                    radius: 26,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: isValidUrl ? NetworkImage(raw) : null,
                    child: isValidUrl ? null : const Icon(Icons.person, size: 22),
                  );
                },
                orElse: () => CircleAvatar(
                  radius: 26,
                  backgroundColor: cs.primaryContainer,
                  child: const Icon(Icons.person, size: 22),
                ),
              )
            : CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: const Icon(Icons.person, size: 22),
              ));

    // Wrap avatar with GestureDetector for profile navigation (DMs only)
    final avatar = !isGroup && otherUserId != null
        ? GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userId: otherUserId,
                    initialName: otherUserName,
                    initialAvatar: otherUserAvatar,
                  ),
                ),
              );
            },
            child: avatarWidget,
          )
        : avatarWidget;

    final titleWidget = isGroup || (chatName != null && chatName.isNotEmpty)
        ? Text(
            titleCase(chatName ?? 'Conversation'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
          )
        : (chatId == null
            ? Text(
                'Conversation',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
              )
            : ref.watch(chatOtherUserNameProvider(chatId)).maybeWhen(
                data: (raw) {
                  final name = titleCase((raw ?? '').trim());
                  return Text(
                    name.isNotEmpty ? name : 'Conversation',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                  );
                },
                orElse: () => Text(
                  'Conversation',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                ),
              ));

    final subtitle = (item['last_message_content'] as String?) ?? '';
    final borderColor = cs.outline.withValues(alpha: 0.08);
    final tileColor = cs.surfaceContainerHighest.withValues(alpha: 0.3);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: tileColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: chatId != null ? () => _showOptions(context, chatId) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleWidget,
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (unread > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 16),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _showOptions(BuildContext context, String chatId) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                title: Text('Delete Conversation', style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, chatId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _confirmDelete(BuildContext context, String chatId) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('Delete Conversation'),
        content: const Text('Are you sure you want to delete this conversation? This will remove all messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call(chatId);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}