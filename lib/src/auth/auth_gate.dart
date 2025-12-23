import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers.dart';
import 'otp_login_page.dart';
import 'setup_profile_page.dart';
import '../ui/home_shell.dart';
import '../chat/conversation_page.dart';
import '../notify/active_chat_tracker.dart';

/// Result of checking if a user has a profile.
sealed class ProfileCheckResult {}

class ProfileExists extends ProfileCheckResult {}

class ProfileNotFound extends ProfileCheckResult {}

class ProfileCheckError extends ProfileCheckResult {
  final String message;
  ProfileCheckError(this.message);
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  Future<ProfileCheckResult>? _profileCheckFuture;
  String? _lastUserId;

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseProvider);
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = client.auth.currentSession;
        if (session == null) {
          _profileCheckFuture = null;
          _lastUserId = null;
          return const OtpLoginPage();
        }

        final userId = client.auth.currentUser?.id;
        // Reset future if user changed
        if (userId != _lastUserId) {
          _lastUserId = userId;
          _profileCheckFuture = _checkProfile(client);
        }
        _profileCheckFuture ??= _checkProfile(client);

        // Check if user has a profile
        return FutureBuilder<ProfileCheckResult>(
          future: _profileCheckFuture,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final result = profileSnapshot.data;

            if (result is ProfileCheckError) {
              return _buildErrorScreen(result.message, client);
            }

            if (result is ProfileNotFound) {
              return const SetupProfilePage();
            }

            // Check for pending chat navigation - navigate after frame
            final pendingChatId = ActiveChatTracker.pendingNavigationChatId;
            if (pendingChatId != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final navChatId = ActiveChatTracker.consumePendingNavigation();
                if (navChatId != null && context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConversationPage(conversationId: navChatId),
                    ),
                  );
                }
              });
            }

            return const HomeShell();
          },
        );
      },
    );
  }

  Widget _buildErrorScreen(String message, SupabaseClient client) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_off,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              const Text(
                'Connection Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _profileCheckFuture = _checkProfile(client);
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<ProfileCheckResult> _checkProfile(SupabaseClient client) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return ProfileNotFound();

      final result = await client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .limit(1);

      return result.isNotEmpty ? ProfileExists() : ProfileNotFound();
    } catch (e) {
      debugPrint('Error checking profile: $e');
      // Distinguish network errors from other errors
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('socket') ||
          errorMessage.contains('network') ||
          errorMessage.contains('connection') ||
          errorMessage.contains('timeout') ||
          errorMessage.contains('host lookup') ||
          errorMessage.contains('failed host lookup')) {
        return ProfileCheckError(
            'Unable to connect. Please check your internet connection.');
      }
      // For other errors (e.g., server errors), also show error screen
      return ProfileCheckError('Something went wrong. Please try again.');
    }
  }
}