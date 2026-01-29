import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which chat is currently being viewed to suppress notifications.
/// Uses both in-memory state and SharedPreferences for persistence.
class ActiveChatTracker {
  static String? _activeChatId;
  static String? _pendingNavigationChatId;
  static const String _prefKey = 'active_chat_id';

  static String? get activeChatId => _activeChatId;
  static String? get pendingNavigationChatId => _pendingNavigationChatId;

  /// Set the active chat when user enters a conversation
  static Future<void> setActiveChat(String? chatId) async {
    _activeChatId = chatId;
    debugPrint('ActiveChatTracker: setActiveChat=$chatId');
    
    // Also persist to SharedPreferences for cross-isolate access
    try {
      final prefs = await SharedPreferences.getInstance();
      if (chatId != null) {
        await prefs.setString(_prefKey, chatId);
        await prefs.setInt('${_prefKey}_time', DateTime.now().millisecondsSinceEpoch);
      } else {
        await prefs.remove(_prefKey);
        await prefs.remove('${_prefKey}_time');
      }
    } catch (e) {
      debugPrint('ActiveChatTracker: Error persisting active chat: $e');
    }
  }

  /// Clear the active chat when user leaves a conversation
  static Future<void> clearActiveChat() async {
    debugPrint('ActiveChatTracker: clearing active chat (was $_activeChatId)');
    _activeChatId = null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      await prefs.remove('${_prefKey}_time');
    } catch (e) {
      debugPrint('ActiveChatTracker: Error clearing active chat: $e');
    }
  }

  /// Check if a chat is currently active (user is viewing it)
  static bool isActive(String chatId) {
    // Check in-memory state first
    final isCurrentlyActive = _activeChatId != null && _activeChatId == chatId;
    final isPendingNav = _pendingNavigationChatId != null && _pendingNavigationChatId == chatId;
    final result = isCurrentlyActive || isPendingNav;
    debugPrint('ActiveChatTracker: isActive($chatId) = $result (current=$_activeChatId, pending=$_pendingNavigationChatId)');
    return result;
  }

  /// Async check that also reads from SharedPreferences (for background isolate)
  static Future<bool> isActiveAsync(String chatId) async {
    // First check in-memory state
    if (_activeChatId == chatId || _pendingNavigationChatId == chatId) {
      debugPrint('ActiveChatTracker: isActiveAsync($chatId) = true (in-memory)');
      return true;
    }
    
    // Fall back to SharedPreferences check
    // IMPORTANT: Reload from disk to get latest value (crucial for background isolate)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Force reload from disk
      final storedChatId = prefs.getString(_prefKey);
      final storedTime = prefs.getInt('${_prefKey}_time');
      
      if (storedChatId == chatId && storedTime != null) {
        // Check if the stored value is recent (within last 5 minutes)
        final storedAt = DateTime.fromMillisecondsSinceEpoch(storedTime);
        final age = DateTime.now().difference(storedAt);
        if (age.inMinutes < 5) {
          debugPrint('ActiveChatTracker: isActiveAsync($chatId) = true (from prefs, age=${age.inSeconds}s)');
          return true;
        }
      }
    } catch (e) {
      debugPrint('ActiveChatTracker: Error checking active chat from prefs: $e');
    }
    
    debugPrint('ActiveChatTracker: isActiveAsync($chatId) = false');
    return false;
  }

  static void setPendingNavigation(String? chatId) {
    _pendingNavigationChatId = chatId;
    debugPrint('ActiveChatTracker: setPendingNavigation=$chatId');
  }

  static String? consumePendingNavigation() {
    final chatId = _pendingNavigationChatId;
    _pendingNavigationChatId = null;
    if (chatId != null) {
      debugPrint('ActiveChatTracker: consumePendingNavigation=$chatId');
    }
    return chatId;
  }
}