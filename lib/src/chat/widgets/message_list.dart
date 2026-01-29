import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../ui/image_viewer.dart';
import 'message_bubble.dart';

enum _BubblePosition { single, first, middle, last }

class MessageList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final SupabaseClient client;
  final void Function(Map<String, dynamic> message)? onReply;
  final void Function(String messageId)? onDelete;

  const MessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.client,
    this.onReply,
    this.onDelete,
  });

  DateTime _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      return DateTime.now();
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatMessageTime(DateTime date) {
    return DateFormat('HH:mm').format(date.toLocal());
  }

  String _formatDayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay = DateTime(date.year, date.month, date.day);

    if (messageDay == today) {
      return 'Today';
    } else if (messageDay == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildReadReceiptIcon(Map<String, dynamic> message, BuildContext context) {
    final messageId = message['id'];
    final readAt = message['read_at'];
    final deliveredAt = message['delivered_at'];
    
    // Message not yet saved to server (optimistic update)
    if (messageId == null) {
      return const Icon(
        Icons.access_time,
        size: 14,
        color: Colors.white54,
      );
    }
    
    final isRead = readAt != null && readAt.toString().isNotEmpty;
    final isDelivered = deliveredAt != null && deliveredAt.toString().isNotEmpty;
    
    if (isRead) {
      // Double blue tick (read)
      return const Icon(
        Icons.done_all,
        size: 16,
        color: Color(0xFF34B7F1),
      );
    } else if (isDelivered) {
      // Double gray tick (delivered but not read)
      return const Icon(
        Icons.done_all,
        size: 16,
        color: Colors.white70,
      );
    } else {
      // Single gray tick (sent to server)
      return const Icon(
        Icons.check,
        size: 16,
        color: Colors.white70,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            reverse: true,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            addSemanticIndexes: false,
            cacheExtent: 600,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              // Reverse the index to show newest messages at bottom (index 0 in reversed ListView)
              final reverseIndex = messages.length - 1 - index;
              final m = messages[reverseIndex];
              final isMine = m['sender_id'] == client.auth.currentUser?.id;
              final currAt = _parseDate(m['created_at']);
              // In reversed ListView: prev (visually above) is older message, next (visually below) is newer
              final prev = reverseIndex > 0 ? messages[reverseIndex - 1] : null;
              final next = reverseIndex < messages.length - 1 ? messages[reverseIndex + 1] : null;
              final DateTime? prevAt =
                  prev != null ? _parseDate(prev['created_at']) : null;
              final DateTime? nextAt =
                  next != null ? _parseDate(next['created_at']) : null;
              // Show day divider when this message starts a new day (compared to older message above)
              final bool newDay = prevAt == null || !_isSameDay(prevAt, currAt);
              final bool contiguousPrev = prev != null && prev['sender_id'] == m['sender_id'] &&
                  prevAt != null && currAt.difference(prevAt).abs() <= const Duration(minutes: 5);
              final bool contiguousNext = next != null && next['sender_id'] == m['sender_id'] &&
                  nextAt != null && nextAt.difference(currAt).abs() <= const Duration(minutes: 5);
              final _BubblePosition pos = (!contiguousPrev && !contiguousNext)
                  ? _BubblePosition.single
                  : (!contiguousPrev && contiguousNext)
                      ? _BubblePosition.first
                      : (contiguousPrev && contiguousNext)
                          ? _BubblePosition.middle
                          : _BubblePosition.last;
              final showMeta = pos == _BubblePosition.single || pos == _BubblePosition.last;

              // Convert to the imported BubblePosition enum
              final BubblePosition bubblePos = switch (pos) {
                _BubblePosition.single => BubblePosition.single,
                _BubblePosition.first => BubblePosition.first,
                _BubblePosition.middle => BubblePosition.middle,
                _BubblePosition.last => BubblePosition.last,
              };

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (newDay) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                                   ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
                                   : Colors.white,
                               borderRadius: BorderRadius.circular(14),
                               border: Border.all(
                                 color: Theme.of(context).brightness == Brightness.dark
                                     ? cs.onSurface.withValues(alpha: 0.10)
                                     : Colors.black12,
                               ),
                               boxShadow: [
                                 BoxShadow(
                                   color: Theme.of(context).brightness == Brightness.dark
                                       ? Colors.black.withValues(alpha: 0.20)
                                       : Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          _formatDayLabel(currAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                     fontFamily: 'Roboto',
                                     color: cs.onSurface.withValues(alpha: 0.75),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: GestureDetector(
                      onLongPress: () => _showMessageOptions(context, m, isMine),
                      child: ChatBubble(
                        isMine: isMine,
                        position: bubblePos,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Show reply preview if this message is a reply
                            if (m['reply_to_id'] != null) ...[
                              _buildReplyPreview(context, m['reply_to_id'], isMine),
                              const SizedBox(height: 6),
                            ],
                          if (((m['file_url'] ?? '') as String).isNotEmpty) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: GestureDetector(
                                  onTap: () {
                                    final url = (m['file_url'] ?? '').toString();
                                    if (url.isEmpty) return;
                                    final tag = 'img_${m['id'] ?? url}';
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ImageViewerPage(url: url, heroTag: tag),
                                      ),
                                    );
                                  },
                                  child: Hero(
                                    tag: 'img_${m['id'] ?? (m['file_url'] ?? '').toString()}',
                                    child: CachedNetworkImage(
                                      imageUrl: (m['file_url'] ?? '').toString(),
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        height: 140,
                                        color: Colors.black12,
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        height: 140,
                                        color: Colors.black12,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.broken_image, color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            (m['content'] ?? '').toString(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                       color: isMine
                                           ? Colors.white
                                           : cs.onSurface.withValues(alpha: 0.90),
                                  fontFamily: 'Roboto',
                                  height: 1.2,
                                ),
                          ),
                          if (showMeta) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatMessageTime(currAt),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                             color: isMine
                                                 ? Colors.white70
                                                 : cs.onSurface.withValues(alpha: 0.65),
                                        fontFamily: 'Roboto',
                                      ),
                                ),
                                if (isMine) ...[
                                  const SizedBox(width: 6),
                                  _buildReadReceiptIcon(m, context),
                                ],
                              ],
                            ),
                          ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
  
  void _showMessageOptions(BuildContext context, Map<String, dynamic> message, bool isMine) {
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
                leading: Icon(Icons.reply_rounded, color: cs.primary),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply?.call(message);
                },
              ),
              if (isMine) ...[
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                  title: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(context, message);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  void _confirmDelete(BuildContext context, Map<String, dynamic> message) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final messageId = message['id']?.toString();
              if (messageId != null) {
                onDelete?.call(messageId);
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildReplyPreview(BuildContext context, String replyToId, bool isMine) {
    final cs = Theme.of(context).colorScheme;
    // Find the replied message in our messages list
    final repliedMessage = messages.where((m) => m['id'] == replyToId).firstOrNull;
    
    if (repliedMessage == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMine 
              ? Colors.white.withValues(alpha: 0.15)
              : cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMine ? Colors.white70 : cs.primary,
              width: 3,
            ),
          ),
        ),
        child: Text(
          'Original message',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: isMine ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }
    
    final content = (repliedMessage['content'] ?? '').toString();
    final hasImage = ((repliedMessage['file_url'] ?? '') as String).isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMine 
            ? Colors.white.withValues(alpha: 0.15)
            : cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white70 : cs.primary,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            Icon(
              Icons.image_rounded,
              size: 16,
              color: isMine ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              content.isNotEmpty ? content : (hasImage ? 'Photo' : 'Message'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isMine ? Colors.white70 : cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}