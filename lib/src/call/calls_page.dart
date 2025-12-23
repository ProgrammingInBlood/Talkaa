import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../providers.dart';
import 'call_service.dart';
import 'call_manager.dart';
import 'model/call_state.dart';

/// Page displaying call history
class CallsPage extends ConsumerStatefulWidget {
  const CallsPage({super.key});

  @override
  ConsumerState<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends ConsumerState<CallsPage> {
  List<Map<String, dynamic>> _calls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCalls();
  }

  Future<void> _loadCalls() async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Use 'calls' table which has proper FK relationships to 'profiles'
      final response = await client
          .from('calls')
          .select('''
            *,
            caller:profiles!calls_caller_id_fkey(id, full_name, username, avatar_url),
            callee:profiles!calls_callee_id_fkey(id, full_name, username, avatar_url)
          ''')
          .or('caller_id.eq.$userId,callee_id.eq.$userId')
          .order('started_at', ascending: false)
          .limit(50);

      setState(() {
        _calls = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('CallsPage: Error loading calls: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Calls'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement call search
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
              ? _buildEmptyState(cs)
              : RefreshIndicator(
                  onRefresh: _loadCalls,
                  child: ListView.builder(
                    itemCount: _calls.length,
                    itemBuilder: (context, index) {
                      return _CallHistoryTile(
                        call: _calls[index],
                        currentUserId: ref.read(supabaseProvider).auth.currentUser?.id ?? '',
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.call_outlined,
            size: 80,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No calls yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a call from any chat',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallHistoryTile extends ConsumerWidget {
  final Map<String, dynamic> call;
  final String currentUserId;

  const _CallHistoryTile({
    required this.call,
    required this.currentUserId,
  });

  void _initiateCall(BuildContext context, WidgetRef ref, String otherUserId, String name, String? avatarUrl, CallType callType, String? chatId) {
    debugPrint('_CallHistoryTile._initiateCall: userId=$otherUserId, type=$callType, name=$name, chatId=$chatId');
    final controller = ref.read(callServiceProvider);
    CallManager.instance.showOutgoingCallScreen(
      calleeId: otherUserId,
      callType: callType,
      chatId: chatId,
      calleeName: name,
      calleeAvatar: avatarUrl,
      controller: controller,
    );
  }

  void _showCallOptions(BuildContext context, WidgetRef ref, String otherUserId, String name, String? avatarUrl) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Call $name',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallOptionButton(
                    icon: Icons.call_rounded,
                    label: 'Voice Call',
                    color: cs.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _initiateCall(context, ref, otherUserId, name, avatarUrl, CallType.audio, call['chat_id'] as String?);
                    },
                  ),
                  _CallOptionButton(
                    icon: Icons.videocam_rounded,
                    label: 'Video Call',
                    color: cs.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _initiateCall(context, ref, otherUserId, name, avatarUrl, CallType.video, call['chat_id'] as String?);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    
    final callerId = call['caller_id'] as String;
    final isOutgoing = callerId == currentUserId;
    final otherUser = isOutgoing ? call['callee'] : call['caller'];
    final otherUserId = otherUser?['id'] as String? ?? (isOutgoing ? call['callee_id'] : call['caller_id']) as String;
    final name = otherUser?['full_name'] ?? otherUser?['username'] ?? 'Unknown';
    final avatarUrl = otherUser?['avatar_url'] as String?;
    
    final status = call['status'] as String? ?? 'ended';
    final type = call['type'] as String? ?? 'audio';
    final startedAt = DateTime.tryParse(call['started_at'] as String? ?? '');
    final durationSeconds = call['duration_seconds'] as int?;

    String durationText = '';
    if (durationSeconds != null && durationSeconds > 0) {
      if (durationSeconds >= 3600) {
        final h = durationSeconds ~/ 3600;
        final m = (durationSeconds % 3600) ~/ 60;
        durationText = '${h}h ${m}m';
      } else if (durationSeconds >= 60) {
        final m = durationSeconds ~/ 60;
        final s = durationSeconds % 60;
        durationText = '${m}m ${s}s';
      } else {
        durationText = '${durationSeconds}s';
      }
    }

    IconData statusIcon;
    Color statusColor;
    String statusText;

    if (status == 'rejected' || status == 'declined') {
      statusIcon = isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded;
      statusColor = Colors.red;
      statusText = 'Declined';
    } else if (status == 'timeout' || status == 'missed') {
      statusIcon = isOutgoing ? Icons.call_made_rounded : Icons.call_missed_rounded;
      statusColor = Colors.red;
      statusText = isOutgoing ? 'No answer' : 'Missed';
    } else if (status == 'accepted' || status == 'ended') {
      statusIcon = isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded;
      statusColor = const Color(0xFF659254);
      statusText = durationText.isNotEmpty ? durationText : 'Ended';
    } else {
      statusIcon = isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded;
      statusColor = cs.onSurface.withValues(alpha: 0.5);
      statusText = status;
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: cs.primary.withValues(alpha: 0.1),
        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
            ? CachedNetworkImageProvider(avatarUrl)
            : null,
        child: avatarUrl == null || avatarUrl.isEmpty
            ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Row(
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          if (startedAt != null)
            Text(
              _formatTime(startedAt),
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          type == 'video' ? Icons.videocam_rounded : Icons.call_rounded,
          color: cs.primary,
        ),
        onPressed: () {
          final callType = type == 'video' ? CallType.video : CallType.audio;
          _initiateCall(context, ref, otherUserId, name, avatarUrl, callType, call['chat_id'] as String?);
        },
      ),
      onTap: () => _showCallOptions(context, ref, otherUserId, name, avatarUrl),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return DateFormat.jm().format(dt);
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return DateFormat.E().format(dt);
    } else {
      return DateFormat.MMMd().format(dt);
    }
  }
}

class _CallOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallOptionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
