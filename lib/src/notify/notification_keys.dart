/// Single source of truth for FCM notification data keys.
/// FCM requires camelCase keys (no underscores allowed).
class NotificationKeys {
  NotificationKeys._();

  // Message keys
  static const String messageType = 'messageType';
  static const String content = 'content';
  static const String fileUrl = 'fileUrl';
  static const String chatId = 'chatId';
  static const String senderId = 'senderId';
  static const String senderName = 'senderName';
  static const String avatarUrl = 'avatarUrl';

  // Call keys
  static const String callId = 'callId';
  static const String sessionId = 'sessionId';
  static const String callerName = 'callerName';
  static const String calleeName = 'calleeName';
  static const String callType = 'callType';
}
