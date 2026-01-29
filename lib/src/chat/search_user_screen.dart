import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers.dart';
import '../storage/signed_url_helper.dart';
import 'conversation_page.dart';

class SearchUserScreen extends ConsumerStatefulWidget {
  const SearchUserScreen({super.key});

  @override
  ConsumerState<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends ConsumerState<SearchUserScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(supabaseProvider);
      final currentUserId = client.auth.currentUser?.id;

      final results = await client
          .from('profiles')
          .select('id, username, full_name, avatar_url, last_seen')
          .or('username.ilike.%${query.trim()}%,full_name.ilike.%${query.trim()}%')
          .neq('id', currentUserId ?? '')
          .limit(20);

      // Sign avatar URLs
      final users = List<Map<String, dynamic>>.from(results as List);
      for (int i = 0; i < users.length; i++) {
        final user = Map<String, dynamic>.from(users[i]);
        final avatarUrl = user['avatar_url'] as String?;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          user['avatar_url'] = await SignedUrlHelper.getAvatarUrl(client, avatarUrl);
        }
        users[i] = user;
      }
      
      setState(() {
        _searchResults = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startConversation(Map<String, dynamic> user) async {
    final client = ref.read(supabaseProvider);
    final currentUserId = client.auth.currentUser?.id;
    final otherUserId = user['id'] as String;

    if (currentUserId == null) return;

    try {
      // Use database function to efficiently get or create DM chat
      final result = await client.rpc('get_or_create_dm_chat', params: {
        'user1_id': currentUserId,
        'user2_id': otherUserId,
      });

      final chatId = result as String?;
      
      if (chatId != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ConversationPage(conversationId: chatId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting conversation: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'New Conversation',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by username or name...',
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) => _searchUsers(value),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                'Error: $_error',
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            )
          else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.person_search, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                  ),
                ],
              ),
            )
          else if (_searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Search for users to start a conversation',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  final avatarUrl = user['avatar_url'] as String?;
                  final fullName = (user['full_name'] as String?)?.trim();
                  final username = (user['username'] as String?)?.trim();
                  final displayName = (fullName != null && fullName.isNotEmpty)
                      ? fullName
                      : username ?? 'Unknown';

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    subtitle: username != null && username.isNotEmpty
                        ? Text(
                            '@$username',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          )
                        : null,
                    trailing: Icon(
                      Icons.chat_bubble_outline,
                      color: cs.primary,
                    ),
                    onTap: () => _startConversation(user),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
