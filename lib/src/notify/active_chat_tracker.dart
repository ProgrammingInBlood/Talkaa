import 'package:flutter/foundation.dart';

class ActiveChatTracker {
  static String? _activeChatId;

  static String? get activeChatId => _activeChatId;

  static void setActiveChat(String? chatId) {
    _activeChatId = chatId;
    debugPrint('ActiveChatTracker: setActiveChat=$chatId');
  }

  static void clearActiveChat() {
    debugPrint('ActiveChatTracker: clearing active chat (was $_activeChatId)');
    _activeChatId = null;
  }

  static bool isActive(String chatId) {
    final result = _activeChatId != null && _activeChatId == chatId;
    debugPrint('ActiveChatTracker: isActive($chatId) = $result (current=$_activeChatId)');
    return result;
  }
}