import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../profile/user_profile_provider.dart';
import '../storage/signed_url_helper.dart';
import 'theme_controller.dart';
import 'edit_profile_page.dart';
import 'notification_settings_page.dart';
import 'autostart_helper.dart';

final currentUserAvatarUrlProvider = FutureProvider<String?>((ref) async {
  final client = ref.read(supabaseProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return null;
  try {
    final row = await client
        .from('profiles')
        .select('avatar_url')
        .eq('id', userId)
        .maybeSingle();
    final path = row?['avatar_url'] as String?;
    if (path != null && path.trim().isNotEmpty) {
      // Sign the avatar URL
      return await SignedUrlHelper.getAvatarUrl(client, path.trim());
    }
  } catch (_) {}
  return null;
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final nameAsync = ref.watch(currentUserDisplayNameProvider);
    final avatarAsync = ref.watch(currentUserAvatarUrlProvider);
    final email = ref.read(supabaseProvider).auth.currentUser?.email ?? '';
    final themeMode = themeModeNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: InkWell(
              onTap: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const EditProfilePage()),
                );
                if (result == true) {
                  ref.invalidate(currentUserDisplayNameProvider);
                  ref.invalidate(currentUserAvatarUrlProvider);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    avatarAsync.when(
                      data: (url) => CircleAvatar(
                        radius: 28,
                        backgroundColor: cs.primaryContainer,
                        backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
                        child: (url == null || url.isEmpty) ? const Icon(Icons.person, size: 24) : null,
                      ),
                      loading: () => CircleAvatar(
                        radius: 28,
                        backgroundColor: cs.primaryContainer,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, __) => CircleAvatar(
                        radius: 28,
                        backgroundColor: cs.primaryContainer,
                        child: const Icon(Icons.person, size: 24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          nameAsync.when(
                            data: (name) => Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            loading: () => const Text('Loading…'),
                            error: (_, __) => const Text('Unknown User'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.color_lens_outlined),
                  title: const Text('Theme'),
                  subtitle: const Text('Choose light, dark, or follow system'),
                  trailing: DropdownButton<ThemeMode>(
                    value: themeMode,
                    onChanged: (mode) {
                      if (mode != null) {
                        themeModeNotifier.value = mode;
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('System'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Notifications'),
                  subtitle: const Text('Manage notification preferences'),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NotificationSettingsPage()),
                    );
                  },
                ),
                if (Platform.isAndroid)
                  FutureBuilder<bool>(
                    future: AutoStartHelper.isAutoStartAvailable(),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) return const SizedBox.shrink();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Divider(height: 0),
                          ListTile(
                            leading: const Icon(Icons.rocket_launch_outlined),
                            title: const Text('Auto-Start'),
                            subtitle: const Text('Enable background start for calls'),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                            onTap: () =>
                                AutoStartHelper.showAutoStartDialog(context),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sign Out'),
              onTap: () async {
                try {
                  final client = ref.read(supabaseProvider);
                  await client.auth.signOut();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
                    Navigator.of(context).maybePop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-out failed: $e')));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}