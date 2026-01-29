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
import 'src/call/ui/call_screen.dart';
import 'src/settings/theme_controller.dart';
import 'src/notify/notification_service.dart';
import 'src/notify/notification_keys.dart';
import 'src/notify/active_chat_tracker.dart';
import 'src/notify/call_notifications.dart';
import 'src/chat/conversation_page.dart';
import 'src/call/model/call_state.dart';

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
  String? _pendingChatId;

  void _navigateToChatIfReady(String chatId) {
    // Set pending navigation to suppress notifications during transition
    ActiveChatTracker.setPendingNavigation(chatId);
    
    final navigator = appNavigatorKey.currentState;
    if (navigator != null) {
      debugPrint('Navigating to chat: $chatId');
      // Check if conversation is already on top of stack
      final currentRoute = ModalRoute.of(navigator.context);
      if (currentRoute?.settings.name == chatId || 
          currentRoute?.settings.arguments == chatId) {
        debugPrint('Conversation already open, not creating duplicate');
        return;
      }
      
      // Push without creating duplicates - keep home route
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ConversationPage(conversationId: chatId),
          settings: RouteSettings(name: chatId, arguments: chatId),
        ),
        (route) => route.isFirst, // Keep only the first (home) route
      );
    } else {
      // Navigator not ready yet, store for later
      _pendingChatId = chatId;
    }
  }

  void _checkPendingNavigation() {
    if (_pendingChatId != null) {
      final chatId = _pendingChatId!;
      _pendingChatId = null;
      // Delay slightly to ensure navigator is fully ready
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigateToChatIfReady(chatId);
      });
    }
  }

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

  Future<void> _markMessagesAsDelivered(String chatId) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      
      final now = DateTime.now().toUtc().toIso8601String();
      // Mark messages as delivered (messages not sent by current user, not yet delivered)
      await client
          .from('messages')
          .update({'delivered_at': now})
          .eq('chat_id', chatId)
          .neq('sender_id', userId)
          .isFilter('delivered_at', null);
      debugPrint('Marked messages as delivered for chat: $chatId');
    } catch (e) {
      debugPrint('Failed to mark messages as delivered: $e');
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
        final data = Map<String, dynamic>.from(message.data);
        if (data['message'] is String) {
          try {
            final msgMap = jsonDecode(data['message'] as String) as Map<String, dynamic>;
            data.putIfAbsent(NotificationKeys.messageType, () => msgMap[NotificationKeys.messageType]);
            data.putIfAbsent(NotificationKeys.content, () => msgMap[NotificationKeys.content]);
            data.putIfAbsent(NotificationKeys.fileUrl, () => msgMap[NotificationKeys.fileUrl]);
          } catch (_) {}
        }
        final type = (data[NotificationKeys.messageType] ?? '').toString().toLowerCase();

        // Handle call_invite - Android native shows notification, but we still need
        // to set up Flutter call state so accept/decline buttons work
        if (type == 'call_invite') {
          final String callerName = (data[NotificationKeys.callerName] ?? message.notification?.title ?? 'Incoming call').toString();
          final String callId = (data[NotificationKeys.callId] ?? data[NotificationKeys.sessionId] ?? DateTime.now().millisecondsSinceEpoch.toString()).toString();
          final String avatarUrl = (data[NotificationKeys.avatarUrl] ?? '').toString();
          
          // CRITICAL: Tell Flutter about the incoming call so it can manage the state
          // This allows notification buttons to work properly
          CallNotifications.emitAction(CallAction(action: 'incoming_call', callId: callId));
          
          // On non-Android platforms, also show the notification
          if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
            await CallNotifications.startForegroundService(
              callerName: callerName,
              callId: callId,
              avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
            );
          }
          return;
        }
        
        // Handle other call events
        if (type == 'call_accept' || type == 'call_cancel' || type == 'call_reject' || 
            type == 'call_decline' || type == 'call_end') {
          final String callId = (data[NotificationKeys.callId] ?? data[NotificationKeys.sessionId] ?? '').toString();
          if (type == 'call_accept') {
            CallNotifications.emitAction(CallAction(action: 'remote_accept', callId: callId));
          } else {
            CallNotifications.emitAction(CallAction(action: 'remote_end', callId: callId));
          }
          return;
        }

        // Chat or other data-only messages: show a normal chat notification
        final chatId = (data[NotificationKeys.chatId] ?? '').toString();
        if (chatId.isNotEmpty) {
          // Mark messages as delivered when notification is received
          _markMessagesAsDelivered(chatId);
          
          // Suppress notification if the conversation screen for this chat is already open
          if (await ActiveChatTracker.isActiveAsync(chatId)) {
            debugPrint('Suppressing chat notification for active conversation: $chatId');
            return;
          }
          final senderId = (data[NotificationKeys.senderId] ?? '').toString();
          final senderName = (data[NotificationKeys.senderName] ?? 'New message').toString();
          final content = (data[NotificationKeys.content] ?? '').toString();
          final imageUrl = (data[NotificationKeys.fileUrl] ?? '').toString();
          final messageType = (data[NotificationKeys.messageType] ?? '').toString();
          final avatarUrl = (data[NotificationKeys.avatarUrl] ?? '').toString();
          await NotificationService.showAndroidChatNotification(
            chatId: chatId,
            senderId: senderId,
            senderName: senderName,
            content: content,
            avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
            imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
            messageType: messageType.isNotEmpty ? messageType : null,
          );
          return;
        }
      });
      // When user taps a notification to open the app
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp: ${message.messageId}');
        final data = message.data;
        final chatId = (data[NotificationKeys.chatId] ?? '').toString();
        if (chatId.isNotEmpty) {
          debugPrint('FCM onMessageOpenedApp: Navigating to chat $chatId');
          _navigateToChatIfReady(chatId);
        }
      });
      
      // Check if app was opened from a terminated state via notification
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM initial message: ${initialMessage.messageId}');
        final data = initialMessage.data;
        final chatId = (data[NotificationKeys.chatId] ?? '').toString();
        if (chatId.isNotEmpty) {
          debugPrint('FCM initial message: Will navigate to chat $chatId');
          _pendingChatId = chatId;
        }
      }
      
      // Check for pending local notification navigation
      final pendingLocalNav = NotificationService.consumePendingNavigation();
      if (pendingLocalNav != null) {
        debugPrint('Pending local notification navigation to: $pendingLocalNav');
        _pendingChatId = pendingLocalNav;
      }
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
    // Check for pending navigation after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1000), _checkPendingNavigation);
    });
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
      // Check pending navigation when app resumes
      _checkPendingNavigation();
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
  final data = Map<String, dynamic>.from(message.data);
  var type = (data[NotificationKeys.messageType] ?? '').toString().toLowerCase();

  // Attempt to parse nested JSON if type is missing
  if (type.isEmpty && data['message'] is String) {
    try {
      final msgMap = jsonDecode(data['message'] as String) as Map<String, dynamic>;
      type = (msgMap[NotificationKeys.messageType] ?? '').toString().toLowerCase();
      if (type.isNotEmpty) {
        if (msgMap[NotificationKeys.sessionId] != null) data[NotificationKeys.sessionId] = msgMap[NotificationKeys.sessionId];
        if (msgMap[NotificationKeys.callId] != null) data[NotificationKeys.callId] = msgMap[NotificationKeys.callId];
        if (msgMap[NotificationKeys.content] != null) data[NotificationKeys.content] = msgMap[NotificationKeys.content];
        if (msgMap[NotificationKeys.fileUrl] != null) data[NotificationKeys.fileUrl] = msgMap[NotificationKeys.fileUrl];
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
      debugPrint('Background call invite handling error: $e');
    }
  }
  if (type == 'call_cancel' ||
      type == 'call_reject' ||
      type == 'call_decline' ||
      type == 'call_end') {
    try {
      await NotificationService.init();
      final String callId = (data[NotificationKeys.callId] ?? data[NotificationKeys.sessionId] ?? '').toString();
      if (callId.isNotEmpty) {
        await NotificationService.cancelAndroidIncomingCallNotificationById(
          callId: callId,
        );
      }
      return;
    } catch (e) {
      debugPrint('Background call cancel handling error: $e');
    }
  }

  // Safeguard: Do NOT show chat notification for call control messages
  if (type.startsWith('call_')) {
    return;
  }

  // Fallback: show chat notification in background for data-only messages
  try {
    await NotificationService.init();
    final chatId = (data[NotificationKeys.chatId] ?? '').toString();
    if (chatId.isNotEmpty) {
      final senderId = (data[NotificationKeys.senderId] ?? '').toString();
      final senderName = (data[NotificationKeys.senderName] ?? 'New message').toString();
      final content = (data[NotificationKeys.content] ?? '').toString();
      final imageUrl = (data[NotificationKeys.fileUrl] ?? '').toString();
      final messageType = (data[NotificationKeys.messageType] ?? '').toString();
      await NotificationService.showAndroidChatNotification(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        content: content,
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        messageType: messageType.isNotEmpty ? messageType : null,
      );
    }
  } catch (e) {
    debugPrint('Background chat notification error: $e');
  }
}

/// Separate Flutter entrypoint for CallActivity (Android only).
/// This entrypoint runs the call-only UI in an isolated Flutter engine,
/// allowing call screens to show on lockscreen and PiP without the main app.
@pragma('vm:entry-point')
Future<void> callMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  // Load environment for Supabase config
  await dotenv.load(fileName: '.env');
  
  // Initialize Supabase for call service
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
      detectSessionInUri: false,
    ),
  );
  
  // Initialize Firebase for call notifications
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init error in callMain: $e');
    }
  }
  
  // Initialize call notifications handler
  CallNotifications.init();
  
  runApp(const ProviderScope(child: CallApp()));
}

/// Minimal app for call-only UI in CallActivity
class CallApp extends ConsumerStatefulWidget {
  const CallApp({super.key});

  @override
  ConsumerState<CallApp> createState() => _CallAppState();
}

class _CallAppState extends ConsumerState<CallApp> {
  @override
  void initState() {
    super.initState();
    debugPrint('CallApp: initState called');
    // Initialize CallManager - CallController will handle pending actions automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('CallApp: Post-frame callback - initializing CallManager');
      CallManager.instance.initialize(ref);
      debugPrint('CallApp: CallManager initialized');
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch call controller to ensure it stays initialized
    ref.watch(callServiceProvider);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Talkaa Call',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      navigatorKey: appNavigatorKey,
      home: const CallAppHome(),
    );
  }
}

/// Home widget for call app - shows call screen or waiting state
class CallAppHome extends ConsumerWidget {
  const CallAppHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callServiceProvider);
    
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        debugPrint('CallAppHome: Building - status: ${controller.status}, hasCall: ${controller.currentCall != null}, userId: ${controller.currentUserId}');
        
        // Show call screen directly when we have an active call
        if (controller.status.isRinging || controller.status.isActive || 
            controller.status == CallStatus.connecting || controller.status == CallStatus.connected) {
          final userId = controller.currentUserId;
          final currentCall = controller.currentCall;
          
          debugPrint('CallAppHome: Call is active - userId: $userId, call: ${currentCall?.id}');
          
          if (currentCall != null && userId != null) {
            debugPrint('CallAppHome: Rendering CallScreen for call ${currentCall.id}');
            return CallScreen(
              callId: currentCall.id,
              callerName: currentCall.remoteUserName(userId),
              callerAvatar: currentCall.remoteUserAvatar(userId),
              initialCallType: controller.callType,
              isIncoming: controller.status == CallStatus.ringing,
            );
          } else {
            debugPrint('CallAppHome: Call is active but missing userId or currentCall');
          }
        }
        
        // Show loading spinner while waiting for call state to load
        debugPrint('CallAppHome: Showing loading spinner');
        return const Scaffold(
          backgroundColor: Color(0xFF1A1A2E),
          body: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
