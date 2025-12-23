import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../ui/image_viewer.dart';
import '../chat_utils.dart';
import 'message_bubble.dart';

enum _BubblePosition { single, first, middle, last }

class MessageList extends StatelessWidget {
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final SupabaseClient client;

  const MessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.client,
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
    final readAt = message['read_at'];
    final isRead = readAt != null && readAt.toString().isNotEmpty;
    
    if (isRead) {
      // Double check mark (read)
      return const Icon(
        Icons.done_all,
        size: 16,
        color: Color(0xFF34B7F1), // Blue tick color like WhatsApp
      );
    } else {
      // Single check mark (sent but not read)
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
              left: 12,
              right: 12,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom,
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
                    child: ChatBubble(
                      isMine: isMine,
                      position: bubblePos,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatTimestamp((m['created_at'] ?? '').toString()),
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
}