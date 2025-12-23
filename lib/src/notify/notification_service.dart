import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'call_notifications.dart';

// Fallback Supabase config for background isolate when payload/statics are missing
const String kSupabaseUrl = 'https://irhcsswgriznsroimnhf.supabase.co';
const String kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlyaGNzc3dncml6bnNyb2ltbmhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwNzQ1MzAsImV4cCI6MjA3MDY1MDUzMH0.AAJnbtrkh5KUh0EDOfvLswOMvx4NRtq89JbP0YcSetg';

final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

const String chatChannelId = 'chat_messages';
const String chatChannelName = 'Chat messages';
const String chatCategoryId = 'message';
const String replyActionId = 'reply';

// Call notification fallback (background isolate)
const String callChannelId = 'incoming_calls';
const String callChannelName = 'Incoming calls';
const String callAnswerActionId = 'call_answer';
const String callDeclineActionId = 'call_decline';

class NotificationService {
  // Cache for accumulated messages per chat (WhatsApp-style)
  static final Map<String, List<_CachedMessage>> _messageCache = {};
  static const int _maxCachedMessages = 10;

  static Uint8List? _getCircularBitmap(Uint8List imageBytes) {
    try {
      final img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return null;
      
      final size = image.width < image.height ? image.width : image.height;
      final img.Image square = img.copyCrop(image,
          x: (image.width - size) ~/ 2,
          y: (image.height - size) ~/ 2,
          width: size,
          height: size);
      
      final img.Image circularImage = img.Image(width: size, height: size);
      final centerX = size / 2;
      final centerY = size / 2;
      final radius = size / 2;
      
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final dx = x - centerX;
          final dy = y - centerY;
          if (dx * dx + dy * dy <= radius * radius) {
            circularImage.setPixel(x, y, square.getPixel(x, y));
          }
        }
      }
      
      return Uint8List.fromList(img.encodePng(circularImage));
    } catch (e) {
      debugPrint('Error creating circular bitmap: $e');
      return null;
    }
  }
  static String? _supabaseUrl;
  static String? _anonKey;

  static Future<void> init() async {
    String? envUrl;
    String? envKey;
    try {
      if (dotenv.isInitialized) {
        envUrl = dotenv.env['SUPABASE_URL'];
        envKey = dotenv.env['SUPABASE_ANON_KEY'];
      }
    } catch (_) {
      // Avoid NotInitializedError in background isolate where dotenv isn't loaded
    }
    _supabaseUrl = envUrl ?? kSupabaseUrl;
    _anonKey = envKey ?? kSupabaseAnonKey;

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          chatCategoryId,
          actions: <DarwinNotificationAction>[
            // Fallback to plain action for broader compatibility
            DarwinNotificationAction.plain(
              replyActionId,
              'Reply',
            ),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.customDismissAction,
          },
        ),
      ],
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings, macOS: null),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Android channels
    const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
      chatChannelId,
      chatChannelName,
      description: 'Notifications for new chat messages',
      importance: Importance.max,
    );
    const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
      callChannelId,
      callChannelName,
      description: 'Incoming call alerts',
      importance: Importance.max,
    );
    final androidImpl = _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(chatChannel);
    await androidImpl?.createNotificationChannel(callChannel);
  }

  static Future<void> showAndroidChatNotification({
    required String chatId,
    required String senderId,
    required String senderName,
    required String content,
    String? avatarUrl,
  }) async {
    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        replyActionId,
        'Reply',
        showsUserInterface: false,
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(label: 'Type a reply')
        ],
      ),
    ];

    // Download and convert avatar to circular bitmap
    AndroidBitmap<Object>? largeIcon;
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(avatarUrl.trim()));
        if (response.statusCode == 200) {
          final circularBytes = _getCircularBitmap(response.bodyBytes);
          if (circularBytes != null) {
            largeIcon = ByteArrayAndroidBitmap(circularBytes);
          } else {
            largeIcon = ByteArrayAndroidBitmap(response.bodyBytes);
          }
        }
      } catch (e) {
        debugPrint('Failed to load avatar: $e');
      }
    }

    // Add message to cache for WhatsApp-style accumulation
    _messageCache.putIfAbsent(chatId, () => []);
    _messageCache[chatId]!.add(_CachedMessage(
      content: content,
      senderName: senderName,
      timestamp: DateTime.now(),
    ));
    // Keep only last N messages
    if (_messageCache[chatId]!.length > _maxCachedMessages) {
      _messageCache[chatId]!.removeAt(0);
    }

    // Build accumulated messages list
    final cachedMessages = _messageCache[chatId]!;
    final messageCount = cachedMessages.length;
    final messagingStyleMessages = cachedMessages.map((m) => Message(
      m.content,
      m.timestamp,
      Person(
        name: m.senderName,
        bot: false,
      ),
    )).toList();

    final androidDetails = AndroidNotificationDetails(
      chatChannelId,
      chatChannelName,
      channelDescription: 'Chat messages',
      importance: Importance.max,
      priority: Priority.high,
      actions: actions,
      category: AndroidNotificationCategory.message,
      largeIcon: largeIcon,
      showWhen: true,
      groupKey: 'chat_messages_group',
      setAsGroupSummary: false,
      number: messageCount,
      styleInformation: MessagingStyleInformation(
        Person(
          name: senderName,
          bot: false,
          important: true,
        ),
        conversationTitle: senderName,
        groupConversation: false,
        messages: messagingStyleMessages,
      ),
    );
    final iosDetails = const DarwinNotificationDetails(
      categoryIdentifier: chatCategoryId,
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    String? accessToken;
    try {
      accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {}

    final payload = jsonEncode({
      'chat_id': chatId,
      'sender_id': senderId,
      'sender_name': senderName,
      // Include Supabase config so background isolate can initialize
      'supabase_url': _supabaseUrl ?? kSupabaseUrl,
      'supabase_anon_key': _anonKey ?? kSupabaseAnonKey,
      'access_token': accessToken,
    });

    await _fln.show(
      chatId.hashCode,
      senderName,
      content.isNotEmpty ? content : 'New message',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );

    // Show group summary notification if multiple chats have notifications
    await _showGroupSummaryIfNeeded();
  }

  static Future<void> _showGroupSummaryIfNeeded() async {
    if (_messageCache.length <= 1) return;

    final totalMessages = _messageCache.values.fold<int>(0, (sum, list) => sum + list.length);
    final chatCount = _messageCache.length;

    final summaryDetails = AndroidNotificationDetails(
      chatChannelId,
      chatChannelName,
      channelDescription: 'Chat messages',
      importance: Importance.max,
      priority: Priority.high,
      groupKey: 'chat_messages_group',
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        _messageCache.entries.take(5).map((e) {
          final lastMsg = e.value.last;
          return '${lastMsg.senderName}: ${lastMsg.content}';
        }).toList(),
        contentTitle: '$totalMessages messages from $chatCount chats',
        summaryText: '$chatCount conversations',
      ),
    );

    await _fln.show(
      0, // Group summary ID
      '$totalMessages new messages',
      'from $chatCount conversations',
      NotificationDetails(android: summaryDetails),
    );
  }

  // Removed: fallback incoming call notification. Native Android handles call-style notifications via CallForegroundService.

  static Future<void> cancelAndroidIncomingCallNotificationById({required String callId}) async {
    try {
      await _fln.cancel(callId.hashCode);
    } catch (_) {}
  }

  /// Cancel chat notification when user opens the conversation
  static Future<void> cancelChatNotification(String chatId) async {
    try {
      // Clear message cache for this chat
      _messageCache.remove(chatId);
      // Cancel the notification
      await _fln.cancel(chatId.hashCode);
      debugPrint('Cancelled notification for chat: $chatId');
    } catch (e) {
      debugPrint('Failed to cancel notification: $e');
    }
  }

  /// Clear all chat notifications
  static Future<void> cancelAllChatNotifications() async {
    try {
      _messageCache.clear();
      await _fln.cancelAll();
    } catch (_) {}
  }

  static Future<void> _onNotificationResponse(NotificationResponse response) async {
    try {
      debugPrint('Notification response: action=${response.actionId ?? ''}, input=${response.input ?? ''}');
      final Map<String, dynamic> data = response.payload != null ? jsonDecode(response.payload!) : {};
      final chatId = data['chat_id'] as String?;
      final text = response.input ?? '';
      final supabaseUrl = (data['supabase_url'] as String?)?.trim();
      final accessToken = (data['access_token'] as String?)?.trim();

      // Handle call actions from fallback incoming call notification
      final callId = data['call_id'] as String?;
      final type = (data['type'] as String?)?.toLowerCase();
      if (response.actionId == callAnswerActionId && callId != null) {
        unawaited(_fln.cancel(callId.hashCode));
        CallNotifications.emitAction(CallAction(action: 'answer', callId: callId));
        return;
      }
      if (response.actionId == callDeclineActionId && callId != null) {
        unawaited(_fln.cancel(callId.hashCode));
        CallNotifications.emitAction(CallAction(action: 'decline', callId: callId));
        return;
      }
      if ((response.actionId == null || response.actionId!.isEmpty) && type == 'call_invite' && callId != null) {
        CallNotifications.emitAction(CallAction(action: 'open', callId: callId));
        return;
      }

      // Inline reply for chat
      if (response.actionId == replyActionId && chatId != null && text.trim().isNotEmpty) {
        unawaited(_fln.cancel(chatId.hashCode));
        debugPrint('Inline reply sending: chatId=$chatId, length=${text.trim().length.toString()}');
        unawaited(_sendReply(
          chatId: chatId,
          text: text.trim(),
          supabaseUrl: supabaseUrl,
          accessToken: accessToken,
        ));
      }
    } catch (e) {
      debugPrint('onNotificationResponse error: ${e.toString()}');
    }
  }

  static Future<void> _sendReply({
    required String chatId,
    required String text,
    String? supabaseUrl,
    String? accessToken,
  }) async {
    try {
      if (!kIsWeb) {
        WidgetsFlutterBinding.ensureInitialized();
        DartPluginRegistrant.ensureInitialized();
        debugPrint('Reply background: Flutter bindings initialized');
      }

      final urlRaw = (supabaseUrl ?? _supabaseUrl)?.trim();
      final baseUrl = (urlRaw != null && urlRaw.isNotEmpty) ? urlRaw : kSupabaseUrl;
      final host = Uri.parse(baseUrl).host;
      final projectRef = host.split('.').first;
      final fnUrl = Uri.parse('https://$projectRef.functions.supabase.co/notification_reply');

      final token = (accessToken ?? '').trim();
      if (token.isEmpty) {
        debugPrint('Reply skipped: missing access token');
        return;
      }

      final res = await http.post(
        fnUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chat_id': chatId,
          'text': text,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('Reply sent via Edge Function');
      } else {
        debugPrint('Reply failed via Edge Function: ${res.statusCode.toString()} ${res.body}');
      }
    } catch (e, st) {
      debugPrint('sendReply error: ${e.toString()}');
      debugPrint('sendReply stack: ${st.toString()}');
    }
  }
}

/// Helper class for caching messages for WhatsApp-style notifications
class _CachedMessage {
  final String content;
  final String senderName;
  final DateTime timestamp;

  _CachedMessage({
    required this.content,
    required this.senderName,
    required this.timestamp,
  });
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  try {
    debugPrint('notificationTapBackground invoked: action=${response.actionId ?? ''}');
    if (!kIsWeb) {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      debugPrint('notificationTapBackground: Flutter bindings initialized');
    }
    unawaited(NotificationService._onNotificationResponse(response));
  } catch (e, st) {
    debugPrint('background response error: ${e.toString()}');
    debugPrint('background response stack: ${st.toString()}');
  }
}