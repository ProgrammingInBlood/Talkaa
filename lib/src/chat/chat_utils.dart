import 'package:intl/intl.dart';

// Utility helpers for chat module
String titleCase(String input) {
  final trimmed = (input).trim();
  if (trimmed.isEmpty) return '';
  final parts = trimmed.split(RegExp(r"\s+"));
  final cased = parts
      .map((p) {
        if (p.isEmpty) return '';
        final lower = p.toLowerCase();
        return lower.length == 1
            ? lower.toUpperCase()
            : lower[0].toUpperCase() + lower.substring(1);
      })
      .where((e) => e.isNotEmpty)
      .join(' ');
  return cased;
}

String formatTimestamp(String ts) {
  if (ts.isEmpty) return '';
  final parsed = DateTime.tryParse(ts);
  if (parsed == null) return '';
  final local = parsed.toLocal();
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  final yesterday = now.subtract(const Duration(days: 1));
  if (sameDay(local, now)) {
    return DateFormat('HH:mm').format(local);
  } else if (sameDay(local, yesterday)) {
    return 'Yesterday';
  } else {
    return DateFormat('dd/MM/yy').format(local);
  }
}

// Format last-seen status according to product rules
// - "Online" if within 1 minute and 10 seconds (70 seconds with buffer)
// - "X minutes ago" when under 1 hour
// - "HH:MM" for today's activity
// - "MM/DD/YYYY" for older activity
String formatLastSeenStatus(DateTime? lastSeen) {
  if (lastSeen == null) return 'Offline';
  final now = DateTime.now();
  final local = lastSeen.toLocal();
  final diff = now.difference(local);
  if (diff.inSeconds <= 70) { // 60 seconds heartbeat + 10 seconds buffer
    return 'Online';
  }
  if (diff.inMinutes < 60) {
    final mins = diff.inMinutes;
    return mins <= 1 ? '1 minute ago' : '$mins minutes ago';
  }
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(local, now)) {
    return DateFormat('HH:mm').format(local);
  }
  return DateFormat('MM/dd/yyyy').format(local);
}