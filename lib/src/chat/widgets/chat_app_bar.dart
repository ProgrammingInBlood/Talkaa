import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../../providers.dart';
import '../chat_utils.dart';
import 'package:talka_flutter/src/ui/navigation.dart';
import 'package:talka_flutter/src/call/call_service.dart';
import 'package:talka_flutter/src/call/call_manager.dart';
import 'package:talka_flutter/src/call/model/call_state.dart';
import 'package:talka_flutter/src/profile/user_profile_screen.dart';

class ChatAppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final String? conversationId;
  final Future<Map<String, String>> Function() getAppBarInfo;

  const ChatAppBar({
    super.key,
    required this.conversationId,
    required this.getAppBarInfo,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  ConsumerState<ChatAppBar> createState() => _ChatAppBarState();
}

class _ChatAppBarState extends ConsumerState<ChatAppBar> {
  Timer? _heartbeatTimer;
  bool _wasOnline = false;
  String? _cachedPeerName;
  String? _cachedPeerAvatar;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(const Duration(seconds: 70), () {
      if (mounted) {
        setState(() {
          // Force rebuild to show last seen status after 70 seconds
        });
      }
    });
  }

  void _stopHeartbeatTimer() {
    _heartbeatTimer?.cancel();
  }

  Future<String?> _getPeerId(WidgetRef ref) async {
    final client = ref.read(supabaseProvider);
    final chatId = widget.conversationId;
    if (chatId == null) return null;
    try {
      final String? myId = client.auth.currentUser?.id;
      if (myId == null) return null;
      final rows = await client
          .from('chat_participants')
          .select('user_id')
          .eq('chat_id', chatId)
          .neq('user_id', myId)
          .limit(1);
      final list = rows as List;
      if (list.isNotEmpty) {
        return list.first['user_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const Color headerGreen = Color(0xFF7FA66A);
    const double headerHeight = 64;

    return AppBar(
      backgroundColor: headerGreen,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: headerHeight,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: FutureBuilder<Map<String, String>>(
        future: widget.getAppBarInfo(),
        builder: (context, snap) {
          final data = snap.data ?? const {};
          final name = data['name'] ?? 'Conversation';
          final avatarUrl = data['avatar'] ?? '';
          // Cache peer info for call buttons
          _cachedPeerName = name;
          _cachedPeerAvatar = avatarUrl.isNotEmpty ? avatarUrl : null;
          final chatId = widget.conversationId ?? '';
          return Row(
            children: [
              const SizedBox(width: 6),
              FutureBuilder<String?>(
                future: _getPeerId(ref),
                builder: (context, peerSnap) {
                  final peerId = peerSnap.data;
                  return GestureDetector(
                    onTap: peerId != null ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userId: peerId,
                            initialName: name,
                            initialAvatar: avatarUrl.isNotEmpty ? avatarUrl : null,
                          ),
                        ),
                      );
                    } : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Hero(
                        tag: 'profile_avatar_${peerId ?? 'unknown'}',
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white24,
                          backgroundImage:
                              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? const Icon(Icons.person, color: Colors.white, size: 16)
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FutureBuilder<String?>(
                  future: _getPeerId(ref),
                  builder: (context, peerIdSnap) {
                    final peerId = peerIdSnap.data;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: peerId != null ? () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  userId: peerId,
                                  initialName: name,
                                  initialAvatar: avatarUrl.isNotEmpty ? avatarUrl : null,
                                ),
                              ),
                            );
                          } : null,
                          child: Text(
                            titleCase(name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    // Presence-based status text: always show with "Active" or "Offline"
                    if (chatId.isNotEmpty)
                      FutureBuilder<String?>(
                          future: _getPeerId(ref),
                        builder: (context, snapshot) {
                          final peerId = snapshot.data;
                          if (peerId == null || peerId.isEmpty) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.white38,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Offline',
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            );
                          }
                          
                          return Consumer(
                            builder: (context, ref, _) {
                              final lastSeenAsync = ref.watch(lastSeenProvider(peerId));
                              
                              return lastSeenAsync.when(
                                data: (dt) {
                                  final status = formatLastSeenStatus(dt);
                                  final isOnline = status == 'Online';
                                  
                                  // Smart timer logic: start timer when user comes online
                                  if (isOnline && !_wasOnline) {
                                    _startHeartbeatTimer();
                                    _wasOnline = true;
                                  } else if (!isOnline && _wasOnline) {
                                    _stopHeartbeatTimer();
                                    _wasOnline = false;
                                  }
                                  
                                  // Debug logging for Flutter console
                                  debugPrint('DEBUG: status=$status, isOnline=$isOnline, dt=$dt, peerId=$peerId');
                                  debugPrint('DEBUG: lastSeenAsync.hasValue=${lastSeenAsync.hasValue}, lastSeenAsync.isLoading=${lastSeenAsync.isLoading}');
                                  
                                  // Browser console logging (web only)
                                  if (kIsWeb) {
                                    debugPrint('BROWSER DEBUG: status=$status, isOnline=$isOnline, dt=$dt, peerId=$peerId');
                                    debugPrint('BROWSER DEBUG: lastSeenAsync.hasValue=${lastSeenAsync.hasValue}, lastSeenAsync.isLoading=${lastSeenAsync.isLoading}');
                                  }
                                  
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isOnline ? Colors.greenAccent : Colors.white38,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white.withValues(alpha: 0.95),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                                loading: () => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.white38,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Loading...',
                                      style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                error: (_, __) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.white38,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Offline',
                                      style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Offline',
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                  },
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          onPressed: () async {
            final peerId = await _getPeerId(ref);
            final chatId = widget.conversationId;
            if (peerId == null || chatId == null) return;
            final peerName = _cachedPeerName ?? 'Unknown';
            final peerAvatar = _cachedPeerAvatar;
            final controller = ref.read(callServiceProvider);
            await CallManager.instance.showOutgoingCallScreen(
              calleeId: peerId,
              callType: CallType.video,
              chatId: chatId,
              calleeName: peerName,
              calleeAvatar: peerAvatar,
              controller: controller,
            );
          },
          icon: const Icon(Icons.videocam_rounded, size: 28, color: Colors.white),
          splashRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () async {
            try {
              final peerId = await _getPeerId(ref);
              final chatId = widget.conversationId;
              if (peerId == null || chatId == null) return;
              final peerName = _cachedPeerName ?? 'Unknown';
              final peerAvatar = _cachedPeerAvatar;
              final controller = ref.read(callServiceProvider);
              await CallManager.instance.showOutgoingCallScreen(
                calleeId: peerId,
                callType: CallType.audio,
                chatId: chatId,
                calleeName: peerName,
                calleeAvatar: peerAvatar,
                controller: controller,
              );
            } catch (e) {
              final navCtx = appNavigatorKey.currentContext;
              if (navCtx != null && navCtx.mounted) {
                ScaffoldMessenger.of(navCtx).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          },
          icon: const Icon(Icons.call_rounded, size: 28, color: Colors.white),
          splashRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          constraints: const BoxConstraints(minWidth: 48),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}