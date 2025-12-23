import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'theme.dart';
import 'src/auth/auth_gate.dart';
import 'src/ui/navigation.dart';
import 'src/call/call_service.dart';
import 'src/call/call_manager.dart';
import 'src/settings/theme_controller.dart';
import 'src/notify/notification_service.dart';
import 'src/notify/call_notifications.dart';
import 'src/notify/active_chat_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure GoogleFonts uses local asset files only (no HTTP fetching)
  GoogleFonts.config.allowRuntimeFetching = false;
  await dotenv.load(fileName: '.env');

  // Try to set high refresh rate on supported Android devices
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      final active = await FlutterDisplayMode.active;
      debugPrint('Display active: ${active.width}x${active.height} @ ${active.refreshRate}Hz');
    } catch (_) {
      // Silently ignore on unsupported platforms/devices
    }
  }

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
      detectSessionInUri: true,
    ),
  );

  // Initialize Firebase (Android/iOS use native config files). Skip on web.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // Initialize call notification action handler
      CallNotifications.init();
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }
  runApp(const ProviderScope(child: RootInitializer(child: MyApp())));
}

class RootInitializer extends StatefulWidget {
  final Widget child;
  const RootInitializer({super.key, required this.child});

  @override
  State<RootInitializer> createState() => _RootInitializerState();
}

class _RootInitializerState extends State<RootInitializer> with WidgetsBindingObserver {
  Future<void> _applyHighRefresh() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      final active = await FlutterDisplayMode.active;
      debugPrint('Refresh applied: ${active.refreshRate}Hz');
    } catch (_) {}
  }

  Future<void> _saveFcmToken(String token) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || token.isEmpty) return;
      String platform = 'unknown';
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          platform = 'android';
          break;
        case TargetPlatform.iOS:
          platform = 'ios';
          break;
        case TargetPlatform.macOS:
          platform = 'macos';
          break;
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          platform = 'unknown';
          break;
      }
      // Avoid unique constraint violations on device_tokens(token)
      final existing = await client
          .from('device_tokens')
          .select('token,user_id,platform')
          .eq('token', token)
          .maybeSingle();

      if (existing == null) {
        await client.from('device_tokens').insert({
          'user_id': uid,
          'token': token,
          'platform': platform,
        });
      } else {
        // Update the existing row for this token
        await client
            .from('device_tokens')
            .update({
              'user_id': uid,
              'platform': platform,
            })
            .eq('token', token);
      }
      debugPrint('FCM token saved to Supabase: $platform');
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  Future<void> _initNotifications() async {
    if (kIsWeb) return; // Web requires separate service worker setup
    try {
      // Android 13+ runtime permission for notifications
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      }
      // Request user permission (iOS/macOS + Android 13+)
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      // Ensure notifications show in foreground on Apple platforms
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      // Initialize local notifications for actions and inline reply
      await NotificationService.init();
      // Log and persist the FCM token for server-side notifications
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('FCM token: $token');
      if (token != null) {
        await _saveFcmToken(token);
      }
      // Persist refreshed tokens
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('FCM token refreshed');
        await _saveFcmToken(newToken);
      });
      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        final data = message.data;
        final type = (data['message_type'] ?? data['type'] ?? '').toString().toLowerCase();

        // Handle call_invite - Android native shows notification, but we still need
        // to set up Flutter call state so accept/decline buttons work
        if (type == 'call_invite') {
          final String callerName = (data['callerName'] ?? data['caller_name'] ?? message.notification?.title ?? 'Incoming call').toString();
          final String callId = (data['callId'] ?? data['session_id'] ?? data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString();
          final String? avatarUrl = (data['avatarUrl'] ?? data['avatar_url'])?.toString();
          
          // CRITICAL: Tell Flutter about the incoming call so it can manage the state
          // This allows notification buttons to work properly
          CallNotifications.emitAction(CallAction(action: 'incoming_call', callId: callId));
          
          // On non-Android platforms, also show the notification
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
            await CallNotifications.startForegroundService(
              callerName: callerName,
              callId: callId,
              avatarUrl: avatarUrl,
            );
          }
          return;
        }
        
        // Handle other call events
        if (type == 'call_accept' || type == 'call_cancel' || type == 'call_reject' || 
            type == 'call_decline' || type == 'call_end') {
          final String callId = (data['callId'] ?? data['session_id'] ?? data['call_id'] ?? '').toString();
          if (type == 'call_accept') {
            CallNotifications.emitAction(CallAction(action: 'remote_accept', callId: callId));
          } else {
            CallNotifications.emitAction(CallAction(action: 'remote_end', callId: callId));
          }
          return;
        }

        // Chat or other data-only messages: show a normal chat notification
        final chatId = (data['chat_id'] ?? '').toString();
        if (chatId.isNotEmpty) {
          // Suppress notification if the conversation screen for this chat is already open
          if (ActiveChatTracker.isActive(chatId)) {
            debugPrint('Suppressing chat notification for active conversation: ' + chatId);
            return;
          }
          final senderId = (data['sender_id'] ?? '').toString();
          final senderName = (data['sender_name'] ?? 'New message').toString();
          final content = (data['content'] ?? '').toString();
          final avatarUrl = (data['avatar_url'] ?? '').toString();
          await NotificationService.showAndroidChatNotification(
            chatId: chatId,
            senderId: senderId,
            senderName: senderName,
            content: content,
            avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
          );
          return;
        }
      });
      // When user taps a notification to open the app
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp: ${message.messageId}');
      });
    } catch (e) {
      debugPrint('FCM setup error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyHighRefresh();
    _initNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyHighRefresh();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize call manager after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallManager.instance.initialize(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ensure CallService is initialized app-wide for incoming calls
    final callController = ref.watch(callServiceProvider);
    debugPrint('MyApp build: root widget rebuilt, call status: ${callController.status}');
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Talka',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: const AuthGate(),
        );
      },
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final data = message.data;
  var type = (data['message_type'] ?? data['type'] ?? '').toString().toLowerCase();

  // Attempt to parse nested JSON if type is missing
  if (type.isEmpty && data['message'] is String) {
    try {
      final msgMap = jsonDecode(data['message'] as String);
      type = (msgMap['message_type'] ?? msgMap['type'] ?? '').toString().toLowerCase();
      if (type.isNotEmpty) {
          if (msgMap['session_id'] != null) data['session_id'] = msgMap['session_id'];
          if (msgMap['call_id'] != null) data['call_id'] = msgMap['call_id'];
      }
    } catch (_) {}
  }

  if (type == 'call_accept') {
    // On Android, native service handles accept updates; skip in Dart
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return;
    }
    return;
  }
  if (type == 'call_invite') {
    try {
      // On Android, the native FirebaseMessagingService starts the CallForegroundService.
      // Skip the fallback local notification to avoid duplicate incoming-call notifications.
      if (defaultTargetPlatform == TargetPlatform.android) {
        return;
      }
      // Using native call notifications; no Dart fallback.
      return;
    } catch (e) {
      debugPrint('Background call invite handling error: ' + e.toString());
    }
  }
  if (type == 'call_cancel' || type == 'call_reject' || type == 'call_decline' || type == 'call_end') {
    try {
      await NotificationService.init();
      final String callId = (data['callId'] ?? data['session_id'] ?? data['call_id'] ?? '').toString();
      if (callId.isNotEmpty) {
        await NotificationService.cancelAndroidIncomingCallNotificationById(callId: callId);
      }
      return;
    } catch (e) {
      debugPrint('Background call cancel handling error: ' + e.toString());
    }
  }
  
  // Safeguard: Do NOT show chat notification for call control messages
  if (type.startsWith('call_')) {
    return;
  }

  // Fallback: show chat notification in background for data-only messages
  try {
    await NotificationService.init();
    final chatId = (data['chat_id'] ?? '').toString();
    if (chatId.isNotEmpty) {
      final senderId = (data['sender_id'] ?? '').toString();
      final senderName = (data['sender_name'] ?? 'New message').toString();
      final content = (data['content'] ?? '').toString();
      await NotificationService.showAndroidChatNotification(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        content: content,
      );
    }
  } catch (e) {
    debugPrint('Background chat notification error: ' + e.toString());
  }
}
