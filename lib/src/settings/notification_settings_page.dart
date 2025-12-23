import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

final notificationPrefsProvider = NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(() {
  return NotificationPrefsNotifier();
});

class NotificationPrefs {
  final bool messagesEnabled;
  final bool callsEnabled;
  final bool storiesEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool showPreview;

  const NotificationPrefs({
    this.messagesEnabled = true,
    this.callsEnabled = true,
    this.storiesEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.showPreview = true,
  });

  NotificationPrefs copyWith({
    bool? messagesEnabled,
    bool? callsEnabled,
    bool? storiesEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? showPreview,
  }) {
    return NotificationPrefs(
      messagesEnabled: messagesEnabled ?? this.messagesEnabled,
      callsEnabled: callsEnabled ?? this.callsEnabled,
      storiesEnabled: storiesEnabled ?? this.storiesEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      showPreview: showPreview ?? this.showPreview,
    );
  }
}

class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() {
    _load();
    return const NotificationPrefs();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotificationPrefs(
      messagesEnabled: prefs.getBool('notif_messages') ?? true,
      callsEnabled: prefs.getBool('notif_calls') ?? true,
      storiesEnabled: prefs.getBool('notif_stories') ?? true,
      soundEnabled: prefs.getBool('notif_sound') ?? true,
      vibrationEnabled: prefs.getBool('notif_vibration') ?? true,
      showPreview: prefs.getBool('notif_preview') ?? true,
    );
  }

  Future<void> setMessagesEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_messages', value);
    state = state.copyWith(messagesEnabled: value);
  }

  Future<void> setCallsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_calls', value);
    state = state.copyWith(callsEnabled: value);
  }

  Future<void> setStoriesEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_stories', value);
    state = state.copyWith(storiesEnabled: value);
  }

  Future<void> setSoundEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_sound', value);
    state = state.copyWith(soundEnabled: value);
  }

  Future<void> setVibrationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_vibration', value);
    state = state.copyWith(vibrationEnabled: value);
  }

  Future<void> setShowPreview(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_preview', value);
    state = state.copyWith(showPreview: value);
  }
}

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends ConsumerState<NotificationSettingsPage> {
  PermissionStatus? _notificationPermission;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() {
        _notificationPermission = status;
      });
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() {
        _notificationPermission = status;
      });
    }
    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'Notification permission is permanently denied. Please enable it from app settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    final isPermissionGranted = _notificationPermission?.isGranted ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_notificationPermission != null && !isPermissionGranted) ...[
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: cs.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notifications Disabled',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enable notifications to receive messages and calls',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onErrorContainer.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _requestPermission,
                      child: const Text('Enable'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Notification Types',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.message_outlined),
                  title: const Text('Messages'),
                  subtitle: const Text('New message notifications'),
                  value: prefs.messagesEnabled,
                  onChanged: (v) => notifier.setMessagesEnabled(v),
                ),
                const Divider(height: 0),
                SwitchListTile(
                  secondary: const Icon(Icons.call_outlined),
                  title: const Text('Calls'),
                  subtitle: const Text('Incoming call notifications'),
                  value: prefs.callsEnabled,
                  onChanged: (v) => notifier.setCallsEnabled(v),
                ),
                const Divider(height: 0),
                SwitchListTile(
                  secondary: const Icon(Icons.amp_stories_outlined),
                  title: const Text('Stories'),
                  subtitle: const Text('New story notifications'),
                  value: prefs.storiesEnabled,
                  onChanged: (v) => notifier.setStoriesEnabled(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Notification Behavior',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('Sound'),
                  subtitle: const Text('Play notification sound'),
                  value: prefs.soundEnabled,
                  onChanged: (v) => notifier.setSoundEnabled(v),
                ),
                const Divider(height: 0),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration),
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrate on notifications'),
                  value: prefs.vibrationEnabled,
                  onChanged: (v) => notifier.setVibrationEnabled(v),
                ),
                const Divider(height: 0),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('Message Preview'),
                  subtitle: const Text('Show message content in notifications'),
                  value: prefs.showPreview,
                  onChanged: (v) => notifier.setShowPreview(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Note: Some notification settings may also be controlled by your device\'s system settings.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
