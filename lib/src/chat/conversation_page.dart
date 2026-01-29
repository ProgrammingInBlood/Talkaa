import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import '../storage/media_uploader.dart';
import '../storage/signed_url_helper.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/message_list.dart';
import 'widgets/message_input.dart';
import '../notify/active_chat_tracker.dart';
import '../notify/notification_service.dart';
import 'chat_list_provider.dart';



class ConversationPage extends ConsumerStatefulWidget {
  final String? conversationId;
  const ConversationPage({super.key, required this.conversationId});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _controller = TextEditingController();
  RealtimeChannel? _channel;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  List<Map<String, dynamic>> _messages = [];
  bool _initialLoaded = false;
  
  // Reply state
  Map<String, dynamic>? _replyingTo;
  
  void _setReplyingTo(Map<String, dynamic>? message) {
    setState(() => _replyingTo = message);
    if (message != null) {
      _inputFocus.requestFocus();
    }
  }
  
  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _upsertMessage(Map<String, dynamic> message) async {
    if (!mounted) return;
    
    // Sign file_url if present
    var msg = Map<String, dynamic>.from(message);
    final fileUrl = msg['file_url'] as String?;
    if (fileUrl != null && fileUrl.isNotEmpty && !fileUrl.startsWith('http')) {
      final client = ref.read(supabaseProvider);
      msg['file_url'] = await SignedUrlHelper.getChatFileUrl(client, fileUrl);
    }
    
    if (!mounted) return;
    setState(() {
      final id = msg['id']?.toString();
      if (id == null || id.isEmpty) {
        _messages.add(msg);
        return;
      }
      final index = _messages.indexWhere((m) => m['id']?.toString() == id);
      if (index == -1) {
        _messages.add(msg);
      } else {
        _messages[index] = {..._messages[index], ...msg};
      }
    });
  }
  
  Future<void> _deleteMessage(String messageId) async {
    try {
      final client = ref.read(supabaseProvider);
      // Soft delete - set is_deleted to true
      await client.from('messages').update({
        'is_deleted': true,
      }).eq('id', messageId);
      
      // Remove from local state immediately
      setState(() {
        _messages.removeWhere((m) => m['id'] == messageId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
      }
    }
  }

  // 2025 trending colors palette



  @override
  void initState() {
    super.initState();
    // Track active chat to suppress duplicate notifications when this screen is open
    _initActiveChat();
    // Cancel any existing notifications for this chat
    if (widget.conversationId != null) {
      NotificationService.cancelChatNotification(widget.conversationId!);
    }
    // Start heartbeat updates for current user
    // Reading keeps provider alive for this page lifetime
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(heartbeatProvider);
      } catch (_) {}
      // Mark messages as read when entering the conversation
      _markAsRead();
    });
    final client = ref.read(supabaseProvider);
    _channel = client
        .channel('public:messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            // Guard null conversationId
            value: widget.conversationId ?? '',
          ),
          callback: (payload) async {
            // Fetch latest inserted row and animate into list
            final Map<String, dynamic> row = payload.newRecord;
            if (row['is_deleted'] != true) {
              await _upsertMessage(row);
              // Always pin to bottom when a new message arrives
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
              // Mark incoming messages as read immediately since user is viewing
              _markAsRead();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: widget.conversationId ?? '',
          ),
          callback: (payload) async {
            final Map<String, dynamic> updatedRow = payload.newRecord;
            setState(() {
              final index = _messages.indexWhere((msg) => msg['id'] == updatedRow['id']);
              if (index != -1) {
                if (updatedRow['is_deleted'] == true) {
                  // Remove deleted messages from UI
                  _messages.removeAt(index);
                } else {
                  // Update existing message (including read_at updates)
                  _messages[index] = {..._messages[index], ...updatedRow};
                }
              } else if (updatedRow['is_deleted'] != true) {
                _messages.add(updatedRow);
              }
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: widget.conversationId ?? '',
          ),
          callback: (payload) async {
            final Map<String, dynamic> deletedRow = payload.oldRecord;
            setState(() {
              _messages.removeWhere((msg) => msg['id'] == deletedRow['id']);
            });
          },
        )
        .subscribe();

    // Keep view pinned when input gains focus (keyboard may overlap)
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));
        // Beat when focus gained
        try {
          ref.read(heartbeatProvider);
        } catch (_) {}
      }
    });
  }

  Future<void> _initActiveChat() async {
    await ActiveChatTracker.setActiveChat(widget.conversationId);
  }

  @override
  void dispose() {
    // Clear active chat tracking when leaving this screen
    ActiveChatTracker.clearActiveChat();
    _controller.dispose();
    _channel?.unsubscribe();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    final chatId = widget.conversationId;
    if (chatId == null) return;
    final client = ref.read(supabaseProvider);
    await markMessagesAsRead(client, chatId);
  }

  Future<String?> _getPeerId() async {
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

  Future<void> _notifyRecipient({
    required String messageType,
    String? text,
    String? fileUrl,
  }) async {
    try {
      final client = ref.read(supabaseProvider);
      final recipientId = await _getPeerId();
      final chatId = widget.conversationId;
      final senderId = client.auth.currentUser?.id;
      if (recipientId == null || chatId == null || senderId == null) return;
      
      // Fetch sender profile for better notifications
      String senderName = 'New message';
      String? avatarUrl;
      try {
        final profileRows = await client
            .from('profiles')
            .select('full_name, username, avatar_url')
            .eq('id', senderId)
            .limit(1);
        if ((profileRows as List).isNotEmpty) {
          final profile = profileRows.first;
          final fullName = (profile['full_name'] as String?)?.trim();
          final username = (profile['username'] as String?)?.trim();
          avatarUrl = (profile['avatar_url'] as String?)?.trim();
          senderName = (fullName != null && fullName.isNotEmpty) 
              ? fullName 
              : (username ?? 'New message');
        }
      } catch (_) {
        // Fallback to default name
      }
      
      await client.functions.invoke('notify_message', body: {
        'recipient_id': recipientId,
        'chat_id': chatId,
        'sender_name': senderName,
        'avatar_url': avatarUrl,
        'message': {
          'messageType': messageType,
          'content': text,
          'senderId': senderId,
          'fileUrl': fileUrl,
        },
      });
    } catch (e) {
      // Non-fatal: just log
      debugPrint('notify_message failed: $e');
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // Capture reply info before clearing
    final replyToId = _replyingTo?['id'];
    // Clear input immediately for responsive UX
    _controller.clear();
    _cancelReply();
    _scrollToBottom();
    
    final client = ref.read(supabaseProvider);
    final inserted = await client.from('messages').insert({
      'chat_id': widget.conversationId,
      'content': text,
      'sender_id': client.auth.currentUser?.id,
      'message_type': 'text',
      'is_edited': false,
      'is_deleted': false,
      if (replyToId != null) 'reply_to_id': replyToId,
    }).select().maybeSingle();
    if (!mounted) return;
    if (inserted != null) {
      _upsertMessage(Map<String, dynamic>.from(inserted));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    // Fire and forget notification
    _notifyRecipient(messageType: 'text', text: text);
    // Beat on send
    try {
      ref.read(heartbeatProvider);
    } catch (_) {}
  }

  Future<void> _attachAndSend() async {
    try {
      final url = await MediaUploader.showPickerAndUpload(context, ref, chatId: widget.conversationId!);
      if (url == null || url.isEmpty) return;
      final client = ref.read(supabaseProvider);
      final text = _controller.text.trim();
      // Clear input immediately for responsive UX
      _controller.clear();
      _scrollToBottom();
      
      final replyToId = _replyingTo?['id'];
      _cancelReply();
      final inserted = await client.from('messages').insert({
        'chat_id': widget.conversationId,
        'content': text.isNotEmpty ? text : null,
        'file_url': url,
        'sender_id': client.auth.currentUser?.id,
        'message_type': 'image',
        'is_edited': false,
        'is_deleted': false,
        if (replyToId != null) 'reply_to_id': replyToId,
      }).select().maybeSingle();
      if (!mounted) return;
      if (inserted != null) {
        _upsertMessage(Map<String, dynamic>.from(inserted));
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
      // Fire and forget notification
      _notifyRecipient(
        messageType: 'image',
        text: text.isNotEmpty ? text : null,
        fileUrl: url,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    // With reverse ListView, we scroll to position 0 (top of reversed list = bottom of chat)
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: animated));
      return;
    }
    
    if (animated) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0.0);
    }
  }


  Future<Map<String, String>> _getAppBarInfo() async {
    final client = ref.read(supabaseProvider);
    final chatId = widget.conversationId;
    String name = 'Conversation';
    String avatar = '';
    try {
      // If conversation id is missing, return defaults early
      if (chatId == null) {
        return {'name': name, 'avatar': avatar};
      }
      final String? myId = client.auth.currentUser?.id;
      final rows = await client
          .from('chat_participants')
          .select('user:profiles(full_name, username, avatar_url), user_id')
          .eq('chat_id', chatId)
          .limit(1)
          .withConverter((data) => data);

      final rowsList = rows as List;
      Map<String, dynamic>? otherUser;

      if (myId != null) {
        final filtered = await client
            .from('chat_participants')
            .select('user:profiles(full_name, username, avatar_url), user_id')
            .eq('chat_id', chatId)
            .neq('user_id', myId)
            .limit(1);
        final filteredList = filtered as List;
        if (filteredList.isNotEmpty) {
          otherUser = filteredList.first['user'] as Map<String, dynamic>?;
        } else if (rowsList.isNotEmpty) {
          otherUser = rowsList.first['user'] as Map<String, dynamic>?;
        }
      } else if (rowsList.isNotEmpty) {
        otherUser = rowsList.first['user'] as Map<String, dynamic>?;
      }

      final fullName = otherUser?['full_name'] as String?;
      final username = otherUser?['username'] as String?;
      final avatarPath = otherUser?['avatar_url'] as String?;
      // Sign the avatar URL if it's a storage path
      if (avatarPath != null && avatarPath.isNotEmpty) {
        avatar = await SignedUrlHelper.getAvatarUrl(client, avatarPath);
      }
      if (fullName != null && fullName.trim().isNotEmpty) {
        name = fullName.trim();
      } else if (username != null && username.trim().isNotEmpty) {
        name = username.trim();
      }
      // Removed last_seen computation; presence will provide live activity state.
    } catch (_) {}
    return {'name': name, 'avatar': avatar};
  }

  Future<List<Map<String, dynamic>>> _fetchMessagesWithSignedUrls() async {
    final client = ref.read(supabaseProvider);
    final rows = await client
        .from('messages')
        .select('id, content, file_url, created_at, sender_id, message_type, file_name, file_size, is_edited, reply_to_id, is_deleted, read_at, delivered_at')
        .eq('chat_id', widget.conversationId!)
        .eq('is_deleted', false)
        .order('created_at', ascending: true);
    
    final messages = List<Map<String, dynamic>>.from(rows as List);
    
    // Sign file URLs for chat images
    for (int i = 0; i < messages.length; i++) {
      final fileUrl = messages[i]['file_url'] as String?;
      if (fileUrl != null && fileUrl.isNotEmpty) {
        final msg = Map<String, dynamic>.from(messages[i]);
        msg['file_url'] = await SignedUrlHelper.getChatFileUrl(client, fileUrl);
        messages[i] = msg;
      }
    }
    
    return messages;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseProvider);
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ChatAppBar(
          conversationId: widget.conversationId,
          getAppBarInfo: _getAppBarInfo,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          image: DecorationImage(
            image: AssetImage(
              Theme.of(context).brightness == Brightness.dark
                  ? 'assets/chat/chat-bg-dark.png'
                  : 'assets/chat/chat-bg-light.png',
            ),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            repeat: ImageRepeat.noRepeat,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 64,
          ),
          child: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _fetchMessagesWithSignedUrls(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Error loading messages:\n${snapshot.error}', textAlign: TextAlign.center),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    // Order so newest is last (bottom)
                    if (!_initialLoaded) {
                      _messages = List<Map<String, dynamic>>.from(snapshot.data!);
                      // Ensure we pin to bottom on first load
                      _initialLoaded = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));
                    }
                    return MessageList(
                      messages: _messages,
                      scrollController: _scrollController,
                      client: client,
                      onReply: _setReplyingTo,
                      onDelete: _deleteMessage,
                    );
                  },
                ),
              ),
              MessageInput(
                controller: _controller,
                focusNode: _inputFocus,
                onSend: _send,
                onAttach: _attachAndSend,
                replyingTo: _replyingTo,
                onCancelReply: _cancelReply,
                onChanged: (_) {
                  // Keep recent messages visible while typing
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));
                  // Beat on typing
                  try {
                    ref.read(heartbeatProvider);
                  } catch (_) {}
                },
                onSubmitted: (_) => _send(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}